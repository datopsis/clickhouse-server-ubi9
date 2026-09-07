#!/usr/bin/env bash
set -Eeuo pipefail

runtime="${CONTAINER_RUNTIME:-docker}"
image="${IMAGE:-ghcr.io/datopsis/clickhouse-server-ubi9:test}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_id="${RANDOM}-$$"
prefix="clickhouse-ubi9-smoke-${run_id}"
network="${prefix}-network"
data_volume="${prefix}-data"
arbitrary_volume="${prefix}-arbitrary-data"
tls_volume="${prefix}-tls-data"
custom_volume="${prefix}-custom-data"
secret_dir="$(mktemp -d "${repo_root}/.smoke-secrets.XXXXXX")"
password="smoke-test-password"

primary="${prefix}-primary"
restart="${prefix}-restart"
passwordless="${prefix}-passwordless"
password_file_server="${prefix}-password-file"
arbitrary_uid="${prefix}-arbitrary-uid"
tls_server="${prefix}-tls"
custom_server="${prefix}-custom"
custom_restart="${prefix}-custom-restart"
legacy_data_dir="${prefix}-legacy-data-dir"
nonwritable="${prefix}-nonwritable"
nonwritable_disk="${prefix}-nonwritable-disk"
relative_primary="${prefix}-relative-primary"
empty_primary="${prefix}-empty-primary"

cleanup() {
    "${runtime}" rm -f \
        "${primary}" "${restart}" "${passwordless}" \
        "${password_file_server}" "${arbitrary_uid}" \
        "${tls_server}" "${custom_server}" "${custom_restart}" \
        "${legacy_data_dir}" "${nonwritable}" "${nonwritable_disk}" \
        "${relative_primary}" "${empty_primary}" >/dev/null 2>&1 || true
    "${runtime}" network rm "${network}" >/dev/null 2>&1 || true
    "${runtime}" volume rm \
        "${data_volume}" "${arbitrary_volume}" "${tls_volume}" \
        "${custom_volume}" >/dev/null 2>&1 || true
    rm -rf "${secret_dir}"
}
trap cleanup EXIT

run_server() {
    local server_name=$1
    shift

    "${runtime}" run --detach \
        --name "${server_name}" \
        --network "${network}" \
        --read-only \
        --tmpfs /tmp:size=256m,mode=1777 \
        --cap-drop ALL \
        --security-opt no-new-privileges:true \
        --ulimit nofile=262144:262144 \
        "$@" \
        "${image}" >/dev/null
}

wait_healthy() {
    local server_name=$1
    local status

    for _ in {1..90}; do
        status="$("${runtime}" inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${server_name}")"
        if [[ "${status}" == healthy ]]; then
            return
        fi
        if [[ "${status}" == unhealthy ]]; then
            "${runtime}" logs "${server_name}"
            return 1
        fi
        sleep 1
    done

    "${runtime}" logs "${server_name}"
    echo "Timed out waiting for ${server_name} to become healthy" >&2
    return 1
}

wait_failed_with() {
    local server_name=$1
    local expected_message=$2
    local running

    for _ in {1..30}; do
        running="$("${runtime}" inspect --format '{{.State.Running}}' "${server_name}")"
        if [[ "${running}" == false ]]; then
            "${runtime}" logs "${server_name}" 2>&1 | grep -Fq "${expected_message}"
            return
        fi
        sleep 1
    done

    "${runtime}" logs "${server_name}"
    echo "Expected ${server_name} to fail startup" >&2
    return 1
}

query_server() {
    local server_name=$1
    local server_password=$2
    local query=$3

    "${runtime}" exec "${server_name}" clickhouse-client \
        --user default --password "${server_password}" --query "${query}"
}

query_remote() {
    local host=$1
    local server_password=$2
    local query=$3

    "${runtime}" run --rm \
        --network "${network}" \
        --entrypoint clickhouse-client \
        "${image}" \
        --host "${host}" --user default --password "${server_password}" --query "${query}"
}

"${runtime}" network create "${network}" >/dev/null
"${runtime}" volume create "${data_volume}" >/dev/null
"${runtime}" volume create "${arbitrary_volume}" >/dev/null
"${runtime}" volume create "${tls_volume}" >/dev/null
"${runtime}" volume create "${custom_volume}" >/dev/null

run_server "${primary}" \
    --network-alias primary \
    --env CLICKHOUSE_PASSWORD="${password}" \
    --volume "${data_volume}:/var/lib/clickhouse" \
    --volume "${repo_root}/tests/fixtures:/docker-entrypoint-initdb.d:ro"
wait_healthy "${primary}"

actual_version="$(query_server "${primary}" "${password}" 'SELECT version()')"
expected_version="$("${runtime}" inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "${image}")"
test "${actual_version}" = "${expected_version}"
test "$("${runtime}" inspect --format '{{.Config.User}}' "${image}")" = "101:0"
if "${runtime}" inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${image}" | \
    grep -q '^CLICKHOUSE_DATA_DIR='; then
    echo "Image metadata unexpectedly contains CLICKHOUSE_DATA_DIR" >&2
    exit 1
fi
test "$("${runtime}" exec "${primary}" id -u)" = 101
test "$("${runtime}" exec "${primary}" stat -c '%a' /tmp/clickhouse-entrypoint/users.xml)" = 600
"${runtime}" exec "${primary}" test ! -e /var/lib/clickhouse/generated/users.xml
"${runtime}" exec "${primary}" sh -c \
    '! command -v microdnf && ! command -v dnf && ! command -v yum && ! command -v rpm && ! command -v curl && ! command -v wget'
query_server "${primary}" "${password}" 'SELECT 1' | grep -qx 1
query_server "${primary}" "${password}" \
    'SELECT value FROM default.container_smoke_test' | grep -qx initialized
query_remote primary "${password}" 'SELECT 1' | grep -qx 1

# A normal stop must reach ClickHouse and produce a successful exit status.
"${runtime}" stop --time 30 "${primary}" >/dev/null
test "$("${runtime}" inspect --format '{{.State.ExitCode}}' "${primary}")" = 0
"${runtime}" rm "${primary}" >/dev/null

# Reusing the volume proves persistence; mounting the fixture again proves that
# initialization scripts are not rerun against an initialized data directory.
run_server "${restart}" \
    --env CLICKHOUSE_PASSWORD="${password}" \
    --volume "${data_volume}:/var/lib/clickhouse" \
    --volume "${repo_root}/tests/fixtures:/docker-entrypoint-initdb.d:ro"
wait_healthy "${restart}"
query_server "${restart}" "${password}" \
    'SELECT count() FROM default.container_smoke_test' | grep -qx 1
"${runtime}" rm -f "${restart}" >/dev/null

# With no password, local health checks work but another container is denied.
run_server "${passwordless}" --network-alias passwordless
wait_healthy "${passwordless}"
if query_remote passwordless "" 'SELECT 1' >/dev/null 2>&1; then
    echo "Passwordless default user unexpectedly accepted a remote connection" >&2
    exit 1
fi
"${runtime}" rm -f "${passwordless}" >/dev/null

# A mounted secret must work without putting the password directly in the
# server container's environment.
printf '%s\n' "${password}" > "${secret_dir}/password"
chmod 0444 "${secret_dir}/password"
run_server "${password_file_server}" \
    --network-alias password-file \
    --env CLICKHOUSE_PASSWORD_FILE=/run/secrets/clickhouse-password \
    --volume "${secret_dir}/password:/run/secrets/clickhouse-password:ro"
wait_healthy "${password_file_server}"
query_remote password-file "${password}" 'SELECT 1' | grep -qx 1
"${runtime}" rm -f "${password_file_server}" >/dev/null

# OpenShift commonly assigns an arbitrary UID while retaining group 0.
run_server "${arbitrary_uid}" \
    --user 100123:0 \
    --env CLICKHOUSE_PASSWORD="${password}" \
    --volume "${arbitrary_volume}:/var/lib/clickhouse"
wait_healthy "${arbitrary_uid}"
test "$("${runtime}" exec "${arbitrary_uid}" id -u)" = 100123
query_server "${arbitrary_uid}" "${password}" 'SELECT 1' | grep -qx 1

# Storage paths come from the effective ClickHouse configuration. The
# entrypoint creates configured subdirectories as the current non-root user.
run_server "${custom_server}" \
    --user 100124:0 \
    --env CLICKHOUSE_PASSWORD="${password}" \
    --volume "${custom_volume}:/var/lib/clickhouse" \
    --volume "${repo_root}/tests/config.d/custom-storage.xml:/etc/clickhouse-server/config.d/custom-storage.xml:ro" \
    --volume "${repo_root}/tests/fixtures:/docker-entrypoint-initdb.d:ro"
wait_healthy "${custom_server}"
test "$("${runtime}" exec "${custom_server}" id -u)" = 100124
query_server "${custom_server}" "${password}" \
    "SELECT path FROM system.disks WHERE name = 'default'" | grep -qx '/var/lib/clickhouse/custom/'
query_server "${custom_server}" "${password}" \
    'SELECT value FROM default.container_smoke_test' | grep -qx initialized
"${runtime}" exec "${custom_server}" test -d /var/lib/clickhouse/custom/custom-tmp
"${runtime}" exec "${custom_server}" test -d /var/lib/clickhouse/custom-user-files
"${runtime}" exec "${custom_server}" test -d /var/lib/clickhouse/custom-format-schemas
"${runtime}" exec "${custom_server}" test -d /var/lib/clickhouse/additional
"${runtime}" exec "${custom_server}" test -d /var/lib/clickhouse/custom-logs
"${runtime}" rm -f "${custom_server}" >/dev/null

# Initialization detection must follow the configured primary path on restart.
run_server "${custom_restart}" \
    --user 100124:0 \
    --env CLICKHOUSE_PASSWORD="${password}" \
    --volume "${custom_volume}:/var/lib/clickhouse" \
    --volume "${repo_root}/tests/config.d/custom-storage.xml:/etc/clickhouse-server/config.d/custom-storage.xml:ro" \
    --volume "${repo_root}/tests/fixtures:/docker-entrypoint-initdb.d:ro"
wait_healthy "${custom_restart}"
query_server "${custom_restart}" "${password}" \
    'SELECT count() FROM default.container_smoke_test' | grep -qx 1
"${runtime}" rm -f "${custom_restart}" >/dev/null

# The removed legacy environment variable must fail instead of silently
# disagreeing with the ClickHouse configuration.
run_server "${legacy_data_dir}" --env CLICKHOUSE_DATA_DIR=/different-data
wait_failed_with "${legacy_data_dir}" 'CLICKHOUSE_DATA_DIR is not supported'

# A configured path on the read-only root must fail early with operator-facing
# identity and permission guidance.
run_server "${nonwritable}" \
    --volume "${repo_root}/tests/config.d/nonwritable-storage.xml:/etc/clickhouse-server/config.d/nonwritable-storage.xml:ro"
wait_failed_with "${nonwritable}" 'Required ClickHouse directory is not writable: /etc/clickhouse-data'

run_server "${nonwritable_disk}" \
    --volume "${repo_root}/tests/config.d/nonwritable-disk.xml:/etc/clickhouse-server/config.d/nonwritable-disk.xml:ro"
wait_failed_with "${nonwritable_disk}" 'Required ClickHouse directory is not writable: /etc/clickhouse-disk'

run_server "${relative_primary}" \
    --volume "${repo_root}/tests/config.d/relative-primary.xml:/etc/clickhouse-server/config.d/relative-primary.xml:ro"
wait_failed_with "${relative_primary}" 'ClickHouse <path> must resolve to a non-empty absolute directory'

run_server "${empty_primary}" \
    --volume "${repo_root}/tests/config.d/empty-primary.xml:/etc/clickhouse-server/config.d/empty-primary.xml:ro"
wait_failed_with "${empty_primary}" 'ClickHouse <path> must resolve to a non-empty absolute directory'

# A TLS-only native listener must support initialization and the image health
# check without retaining the clear-text native port.
env -u MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL='/CN=' \
    openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
    -keyout "${secret_dir}/tls.key" \
    -out "${secret_dir}/tls.crt" \
    -subj '/CN=localhost' \
    -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' >/dev/null 2>&1
chmod 0444 "${secret_dir}/tls.key" "${secret_dir}/tls.crt"
run_server "${tls_server}" \
    --env CLICKHOUSE_PASSWORD="${password}" \
    --volume "${tls_volume}:/var/lib/clickhouse" \
    --volume "${repo_root}/container/config.d/tls.example.xml:/etc/clickhouse-server/config.d/tls.xml:ro" \
    --volume "${secret_dir}/tls.crt:/etc/clickhouse-server/certs/tls.crt:ro" \
    --volume "${secret_dir}/tls.key:/etc/clickhouse-server/certs/tls.key:ro"
wait_healthy "${tls_server}"
"${runtime}" exec "${tls_server}" clickhouse-client \
    --secure --accept-invalid-certificate --host 127.0.0.1 --port 9440 \
    --user default --password "${password}" --query 'SELECT 1' | grep -qx 1

echo "Smoke tests passed for ClickHouse ${actual_version}"
