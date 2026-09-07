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
secret_dir="$(mktemp -d "${repo_root}/.smoke-secrets.XXXXXX")"
password="smoke-test-password"

primary="${prefix}-primary"
restart="${prefix}-restart"
passwordless="${prefix}-passwordless"
password_file_server="${prefix}-password-file"
arbitrary_uid="${prefix}-arbitrary-uid"

cleanup() {
    "${runtime}" rm -f \
        "${primary}" "${restart}" "${passwordless}" \
        "${password_file_server}" "${arbitrary_uid}" >/dev/null 2>&1 || true
    "${runtime}" network rm "${network}" >/dev/null 2>&1 || true
    "${runtime}" volume rm "${data_volume}" "${arbitrary_volume}" >/dev/null 2>&1 || true
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
test "$("${runtime}" exec "${primary}" id -u)" = 101
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
chmod 0600 "${secret_dir}/password"
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

echo "Smoke tests passed for ClickHouse ${actual_version}"
