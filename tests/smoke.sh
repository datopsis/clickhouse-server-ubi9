#!/usr/bin/env bash
set -Eeuo pipefail

runtime="${CONTAINER_RUNTIME:-docker}"
image="${IMAGE:-ghcr.io/datopsis/clickhouse-server-ubi9:test}"
name="clickhouse-ubi9-smoke-${RANDOM}"
password="smoke-test-password"

cleanup() {
    "${runtime}" rm -f "${name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${runtime}" run -d \
    --name "${name}" \
    --read-only \
    --tmpfs /tmp:size=256m,mode=1777 \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --ulimit nofile=262144:262144 \
    -e CLICKHOUSE_PASSWORD="${password}" \
    --volume "$(pwd)/tests/fixtures:/docker-entrypoint-initdb.d:ro" \
    "${image}" >/dev/null

for _ in {1..60}; do
    status="$("${runtime}" inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${name}")"
    if [[ "${status}" == healthy ]]; then
        break
    fi
    if [[ "${status}" == unhealthy ]]; then
        "${runtime}" logs "${name}"
        exit 1
    fi
    sleep 1
done

if [[ "$("${runtime}" inspect --format '{{.State.Health.Status}}' "${name}")" != healthy ]]; then
    "${runtime}" logs "${name}"
    exit 1
fi

actual_version="$("${runtime}" exec "${name}" clickhouse-client \
    --user default --password "${password}" --query 'SELECT version()')"
expected_version="$("${runtime}" inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "${image}")"
test "${actual_version}" = "${expected_version}"

test "$("${runtime}" exec "${name}" id -u)" = 101
"${runtime}" exec "${name}" sh -c '! command -v microdnf && ! command -v dnf && ! command -v yum'
"${runtime}" exec "${name}" clickhouse-client \
    --user default --password "${password}" --query 'SELECT 1' | grep -qx 1
"${runtime}" exec "${name}" clickhouse-client \
    --user default --password "${password}" \
    --query 'SELECT value FROM default.container_smoke_test' | grep -qx 'initialized'

echo "Smoke test passed for ClickHouse ${actual_version}"
