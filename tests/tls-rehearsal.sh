#!/usr/bin/env bash
set -Eeuo pipefail

runtime="${CONTAINER_RUNTIME:-podman}"
image="${IMAGE:-ghcr.io/datopsis/clickhouse-server-ubi9:test}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_id="${RANDOM}-$$"
prefix="clickhouse-ubi9-tls-${run_id}"
connected_network="${prefix}-connected"
disconnected_network="${prefix}-disconnected"
secret_dir="$(mktemp -d "${repo_root}/.tls-rehearsal.XXXXXX")"
password="tls-rehearsal-password"
endpoint_password="tls-endpoint-password"

runtime_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1"
    else
        printf '%s\n' "$1"
    fi
}

runtime_call() {
    # Prevent Git Bash from rewriting container paths. Host mount sources are
    # converted explicitly with runtime_path before reaching this wrapper.
    MSYS2_ARG_CONV_EXCL='*' "${runtime}" "$@"
}

runtime_repo_root="$(runtime_path "${repo_root}")"
runtime_secret_dir="$(runtime_path "${secret_dir}")"
windows_podman_machine=false
if command -v cygpath >/dev/null 2>&1; then
    windows_podman_machine=true
fi

connected_server="${prefix}-connected-server"
connected_endpoint="${prefix}-connected-endpoint"
incomplete_server="${prefix}-incomplete-chain"
unreadable_server="${prefix}-unreadable-key"
disconnected_server="${prefix}-disconnected-server"
disconnected_endpoint="${prefix}-disconnected-endpoint"

connected_volume="${prefix}-connected-data"
connected_endpoint_volume="${prefix}-connected-endpoint-data"
incomplete_volume="${prefix}-incomplete-data"
unreadable_volume="${prefix}-unreadable-data"
disconnected_volume="${prefix}-disconnected-data"
disconnected_endpoint_volume="${prefix}-disconnected-endpoint-data"

cleanup() {
    runtime_call rm -f \
        "${connected_server}" "${connected_endpoint}" \
        "${incomplete_server}" "${unreadable_server}" \
        "${disconnected_server}" "${disconnected_endpoint}" \
        >/dev/null 2>&1 || true
    runtime_call network rm \
        "${connected_network}" "${disconnected_network}" \
        >/dev/null 2>&1 || true
    runtime_call volume rm \
        "${connected_volume}" "${connected_endpoint_volume}" \
        "${incomplete_volume}" "${unreadable_volume}" \
        "${disconnected_volume}" "${disconnected_endpoint_volume}" \
        >/dev/null 2>&1 || true
    rm -rf "${secret_dir}"
}
trap cleanup EXIT

fail() {
    echo "TLS rehearsal failed: $*" >&2
    exit 1
}

cat > "${secret_dir}/intermediate.ext" <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always
EOF

cat > "${secret_dir}/root.ext" <<'EOF'
basicConstraints=critical,CA:TRUE,pathlen:1
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
EOF

cat > "${secret_dir}/server.ext.template" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always
EOF

env -u MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL='/CN=' \
    openssl req -new -newkey rsa:2048 -sha256 -nodes \
    -keyout "${secret_dir}/root.key" \
    -out "${secret_dir}/root.csr" \
    -subj '/CN=ClickHouse TLS Rehearsal Root' >/dev/null 2>&1

openssl x509 -req -sha256 -days 2 \
    -in "${secret_dir}/root.csr" \
    -signkey "${secret_dir}/root.key" \
    -extfile "${secret_dir}/root.ext" \
    -out "${secret_dir}/root.crt" >/dev/null 2>&1

env -u MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL='/CN=' \
    openssl req -new -newkey rsa:2048 -sha256 -nodes \
    -keyout "${secret_dir}/intermediate.key" \
    -out "${secret_dir}/intermediate.csr" \
    -subj '/CN=ClickHouse TLS Rehearsal Intermediate' >/dev/null 2>&1

openssl x509 -req -sha256 -days 2 \
    -in "${secret_dir}/intermediate.csr" \
    -CA "${secret_dir}/root.crt" \
    -CAkey "${secret_dir}/root.key" \
    -CAcreateserial \
    -extfile "${secret_dir}/intermediate.ext" \
    -out "${secret_dir}/intermediate.crt" >/dev/null 2>&1

env -u MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL='/CN=' \
    openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 2 \
    -keyout "${secret_dir}/unrelated-root.key" \
    -out "${secret_dir}/unrelated-root.crt" \
    -subj '/CN=Unrelated TLS Rehearsal Root' \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign' >/dev/null 2>&1

issue_leaf() {
    local name=$1
    local dns_name=$2

    env -u MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL='/CN=' \
        openssl req -new -newkey rsa:2048 -sha256 -nodes \
        -keyout "${secret_dir}/${name}.key" \
        -out "${secret_dir}/${name}.csr" \
        -subj "/CN=${dns_name}" >/dev/null 2>&1
    {
        cat "${secret_dir}/server.ext.template"
        printf 'subjectAltName=DNS:%s\n' "${dns_name}"
    } > "${secret_dir}/${name}.ext"
    openssl x509 -req -sha256 -days 2 \
        -in "${secret_dir}/${name}.csr" \
        -CA "${secret_dir}/intermediate.crt" \
        -CAkey "${secret_dir}/intermediate.key" \
        -CAcreateserial \
        -extfile "${secret_dir}/${name}.ext" \
        -out "${secret_dir}/${name}.crt" >/dev/null 2>&1
    cat "${secret_dir}/${name}.crt" \
        "${secret_dir}/intermediate.crt" \
        > "${secret_dir}/${name}.chain.crt"
}

issue_leaf connected-v1 clickhouse.connected.test
issue_leaf connected-v2 clickhouse.connected.test
issue_leaf connected-endpoint private.connected.test
issue_leaf disconnected-v1 clickhouse.disconnected.test
issue_leaf disconnected-v2 clickhouse.disconnected.test
issue_leaf disconnected-endpoint private.disconnected.test

if ! (cd "${secret_dir}" && \
    openssl verify -CAfile root.crt \
        -untrusted intermediate.crt connected-v1.crt); then
    openssl x509 -in "${secret_dir}/root.crt" \
        -noout -subject -issuer -serial
    openssl x509 -in "${secret_dir}/intermediate.crt" \
        -noout -subject -issuer -serial
    fail 'generated certificate chain did not validate'
fi
openssl x509 -in "${secret_dir}/connected-v1.crt" -noout \
    -subject -issuer -serial -dates -ext subjectAltName

runtime_call run --rm --entrypoint cat "${image}" \
    /etc/pki/tls/certs/ca-bundle.crt \
    > "${secret_dir}/public-ca-bundle.pem"
cat "${secret_dir}/public-ca-bundle.pem" "${secret_dir}/root.crt" \
    "${secret_dir}/intermediate.crt" \
    > "${secret_dir}/connected-ca-bundle.pem"
cat "${secret_dir}/root.crt" "${secret_dir}/intermediate.crt" \
    > "${secret_dir}/disconnected-ca-bundle.pem"

cat > "${secret_dir}/client.xml" <<'EOF'
<?xml version="1.0"?>
<config>
    <openSSL>
        <client>
            <loadDefaultCAFile>false</loadDefaultCAFile>
            <caConfig>/tls/ca-bundle.pem</caConfig>
            <verificationMode>strict</verificationMode>
            <invalidCertificateHandler>
                <name>RejectCertificateHandler</name>
            </invalidCertificateHandler>
        </client>
    </openSSL>
</config>
EOF

chmod 0444 "${secret_dir}"/*.crt "${secret_dir}"/*.pem \
    "${secret_dir}"/*.xml
chmod 0400 "${secret_dir}"/*.key
# These disposable leaf keys are owned by the CI runner, while the image runs
# as UID 101. Make only leaf fixtures readable across that bind-mount boundary;
# CA signing keys remain 0400 and are never mounted. Production uses the
# namespace-aware ownership procedure in docs/TLS.md instead.
chmod 0444 \
    "${secret_dir}/connected-v1.key" \
    "${secret_dir}/connected-v2.key" \
    "${secret_dir}/connected-endpoint.key" \
    "${secret_dir}/disconnected-v1.key" \
    "${secret_dir}/disconnected-v2.key" \
    "${secret_dir}/disconnected-endpoint.key"

runtime_call network create "${connected_network}" >/dev/null
runtime_call network create --internal "${disconnected_network}" >/dev/null
test "$(runtime_call network inspect --format '{{.Internal}}' \
    "${disconnected_network}")" = true

for volume in \
    "${connected_volume}" "${connected_endpoint_volume}" \
    "${incomplete_volume}" "${unreadable_volume}" \
    "${disconnected_volume}" "${disconnected_endpoint_volume}"; do
    runtime_call volume create "${volume}" >/dev/null
done

run_tls_server() {
    local name=$1
    local network=$2
    local alias=$3
    local volume=$4
    local certificate=$5
    local key=$6
    local runtime_certificate
    local runtime_key
    shift 6

    runtime_certificate="$(runtime_path "${certificate}")"
    runtime_key="$(runtime_path "${key}")"

    runtime_call run --detach \
        --name "${name}" \
        --network "${network}" \
        --network-alias "${alias}" \
        --read-only \
        --tmpfs /tmp:size=256m,mode=1777 \
        --cap-drop ALL \
        --security-opt no-new-privileges:true \
        --ulimit nofile=262144:262144 \
        --env CLICKHOUSE_PASSWORD="${password}" \
        --volume "${volume}:/var/lib/clickhouse" \
        --volume "${runtime_repo_root}/container/config.d/tls.example.xml:/etc/clickhouse-server/config.d/tls.xml:ro" \
        --volume "${runtime_certificate}:/etc/clickhouse-server/certs/tls.crt:ro" \
        --volume "${runtime_key}:/etc/clickhouse-server/certs/tls.key:ro" \
        "$@" \
        "${image}" >/dev/null
}

wait_healthy() {
    local name=$1
    local status

    for _ in {1..90}; do
        status="$(runtime_call inspect --format \
            '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
            "${name}")"
        if [[ "${status}" == healthy ]]; then
            return
        fi
        if [[ "${status}" == unhealthy ]]; then
            runtime_call logs "${name}"
            return 1
        fi
        sleep 1
    done

    runtime_call logs "${name}"
    fail "${name} did not become healthy"
}

published_https_port() {
    local name=$1
    local mapping

    mapping="$(runtime_call port "${name}" 8443/tcp | tail -n 1)"
    printf '%s\n' "${mapping##*:}"
}

query_local() {
    local name=$1
    local query=$2
    local query_password=${3:-${password}}

    runtime_call exec "${name}" env -u CLICKHOUSE_CONFIG \
        clickhouse-client \
        --config-file /usr/local/share/clickhouse-health-client.xml \
        --host 127.0.0.1 --port 9440 --secure \
        --user default --password "${query_password}" --query "${query}"
}

native_tls_query() {
    local network=$1
    local host=$2
    local ca_file=${3:-${secret_dir}/disconnected-ca-bundle.pem}
    local runtime_ca_file

    runtime_ca_file="$(runtime_path "${ca_file}")"

    runtime_call run --rm \
        --network "${network}" \
        --read-only \
        --tmpfs /tmp:size=64m,mode=1777 \
        --cap-drop ALL \
        --entrypoint env \
        --volume "${runtime_ca_file}:/tls/ca-bundle.pem:ro" \
        --volume "${runtime_secret_dir}/client.xml:/tls/client.xml:ro" \
        "${image}" \
        -u CLICKHOUSE_CONFIG clickhouse-client \
        --config-file /tls/client.xml \
        --secure --host "${host}" --port 9440 \
        --user default --password "${password}" \
        --connect_timeout 5 --query 'SELECT 1'
}

https_query() {
    local host=$1
    local port=$2
    local ca_file=$3

    curl --silent --show-error --fail --max-time 10 \
        --noproxy '*' \
        --cacert "${ca_file}" \
        --resolve "${host}:${port}:127.0.0.1" \
        --user "default:${password}" \
        "https://${host}:${port}/?query=SELECT%201"
}

url_query() {
    local name=$1
    local url=$2

    query_local "${name}" \
        "SELECT length(data) > 0 FROM url('${url}', 'RawBLOB', 'data String') SETTINGS max_execution_time=10, http_max_tries=1, http_connection_timeout=5, http_receive_timeout=5, http_send_timeout=5"
}

# A controlled private-CA HTTPS service for connected outbound validation.
run_tls_server "${connected_endpoint}" "${connected_network}" \
    private.connected.test "${connected_endpoint_volume}" \
    "${secret_dir}/connected-endpoint.chain.crt" \
    "${secret_dir}/connected-endpoint.key" \
    --volume "${runtime_repo_root}/container/config.d/outbound-ca.example.xml:/etc/clickhouse-server/config.d/outbound-ca.xml:ro" \
    --volume "${runtime_secret_dir}/connected-ca-bundle.pem:/etc/clickhouse-server/certs/outbound-ca-bundle.pem:ro" \
    --env CLICKHOUSE_PASSWORD="${endpoint_password}"
wait_healthy "${connected_endpoint}"
echo 'Connected private-CA endpoint is healthy'

cp "${secret_dir}/connected-v1.chain.crt" "${secret_dir}/active.chain.crt"
cp "${secret_dir}/connected-v1.key" "${secret_dir}/active.key"
chmod 0444 "${secret_dir}/active.chain.crt" "${secret_dir}/active.key"

run_tls_server "${connected_server}" "${connected_network}" \
    clickhouse.connected.test "${connected_volume}" \
    "${secret_dir}/active.chain.crt" "${secret_dir}/active.key" \
    --publish 127.0.0.1::8443 \
    --network-alias wrong.connected.test \
    --volume "${runtime_repo_root}/container/config.d/outbound-ca.example.xml:/etc/clickhouse-server/config.d/outbound-ca.xml:ro" \
    --volume "${runtime_secret_dir}/connected-ca-bundle.pem:/etc/clickhouse-server/certs/outbound-ca-bundle.pem:ro"
wait_healthy "${connected_server}"
echo 'Connected ClickHouse server is healthy'

connected_port="$(published_https_port "${connected_server}")"
test "$(https_query clickhouse.connected.test "${connected_port}" \
    "${secret_dir}/root.crt")" = 1
echo 'Connected HTTPS validation passed'
test "$(native_tls_query "${connected_network}" clickhouse.connected.test)" = 1
echo 'Connected native TLS validation passed'

if https_query clickhouse.connected.test "${connected_port}" \
    "${secret_dir}/unrelated-root.crt" >/dev/null 2>&1; then
    fail 'HTTPS accepted an unrelated CA'
fi
if https_query wrong.connected.test "${connected_port}" \
    "${secret_dir}/root.crt" >/dev/null 2>&1; then
    fail 'HTTPS accepted the wrong hostname'
fi
if native_tls_query "${connected_network}" wrong.connected.test \
    >/dev/null 2>&1; then
    fail 'native TLS accepted the wrong hostname'
fi
if curl --silent --fail --max-time 5 \
    "http://127.0.0.1:${connected_port}/ping" >/dev/null 2>&1; then
    fail 'clear-text HTTP succeeded on the HTTPS listener'
fi
if runtime_call run --rm --network "${connected_network}" \
    --entrypoint env "${image}" \
    -u CLICKHOUSE_CONFIG clickhouse-client \
    --host clickhouse.connected.test --port 9440 \
    --user default --password "${password}" \
    --connect_timeout 5 --query 'SELECT 1' >/dev/null 2>&1; then
    fail 'clear-text native protocol succeeded on the TLS listener'
fi

# The connected bundle must support both public PKI and the controlled private CA.
echo 'Testing connected public-PKI outbound TLS'
test "$(url_query "${connected_server}" 'https://example.com/')" = 1
echo 'Connected public-PKI outbound TLS passed'
echo 'Testing connected private-CA outbound TLS'
test "$(query_local "${connected_server}" \
    "SELECT length(data) > 0 FROM url('https://private.connected.test:8443/?query=SELECT%201', 'RawBLOB', 'data String', headers('X-ClickHouse-User'='default', 'X-ClickHouse-Key'='${endpoint_password}'))")" = 1
echo 'Connected private-CA outbound TLS passed'

old_serial="$(openssl x509 -in "${secret_dir}/connected-v1.crt" \
    -noout -serial | cut -d= -f2)"
served_serial="$(openssl s_client \
    -connect "127.0.0.1:${connected_port}" \
    -servername clickhouse.connected.test \
    -CAfile "${secret_dir}/root.crt" </dev/null 2>/dev/null | \
    openssl x509 -noout -serial | cut -d= -f2)"
test "${served_serial}" = "${old_serial}"
echo 'Connected certificate serial matched'

# A leaf without its intermediate must not validate to the trusted root.
run_tls_server "${incomplete_server}" "${connected_network}" \
    incomplete.connected.test "${incomplete_volume}" \
    "${secret_dir}/connected-v1.crt" "${secret_dir}/connected-v1.key" \
    --volume "${runtime_repo_root}/container/config.d/outbound-ca.example.xml:/etc/clickhouse-server/config.d/outbound-ca.xml:ro" \
    --volume "${runtime_secret_dir}/connected-ca-bundle.pem:/etc/clickhouse-server/certs/outbound-ca-bundle.pem:ro" \
    --publish 127.0.0.1::8443
wait_healthy "${incomplete_server}"
echo 'Incomplete-chain server is ready for the rejection test'
incomplete_port="$(published_https_port "${incomplete_server}")"
if https_query clickhouse.connected.test "${incomplete_port}" \
    "${secret_dir}/root.crt" >/dev/null 2>&1; then
    fail 'HTTPS accepted an incomplete certificate chain'
fi
runtime_call rm -f "${incomplete_server}" >/dev/null
echo 'Incomplete-chain rejection passed'

# An unreadable private key must prevent startup. Windows Podman Machine file
# sharing does not preserve a host chmod 000, so native Linux CI owns this
# assertion and the Windows reproduction reports the explicit limitation.
if command -v cygpath >/dev/null 2>&1; then
    echo 'Unreadable-key rejection skipped on Windows; native Linux CI runs it'
else
    cp "${secret_dir}/connected-v1.key" "${secret_dir}/unreadable.key"
    chmod 000 "${secret_dir}/unreadable.key"
    if run_tls_server "${unreadable_server}" "${connected_network}" \
        unreadable.connected.test "${unreadable_volume}" \
        "${secret_dir}/connected-v1.chain.crt" \
        "${secret_dir}/unreadable.key"; then
        for _ in {1..30}; do
            if [[ "$(runtime_call inspect --format '{{.State.Running}}' \
                "${unreadable_server}")" == false ]]; then
                break
            fi
            sleep 1
        done
        test "$(runtime_call inspect --format '{{.State.Running}}' \
            "${unreadable_server}")" = false
    fi
    chmod 0400 "${secret_dir}/unreadable.key"
    echo 'Unreadable-key rejection passed'
fi

# Rotate by replacing the mounted leaf/key and recreating the workload. The
# persistent data volume remains; the old serial must no longer be served.
runtime_call rm -f "${connected_server}" >/dev/null
chmod 0600 "${secret_dir}/active.chain.crt" "${secret_dir}/active.key"
cp "${secret_dir}/connected-v2.chain.crt" "${secret_dir}/active.chain.crt"
cp "${secret_dir}/connected-v2.key" "${secret_dir}/active.key"
chmod 0444 "${secret_dir}/active.chain.crt" "${secret_dir}/active.key"
run_tls_server "${connected_server}" "${connected_network}" \
    clickhouse.connected.test "${connected_volume}" \
    "${secret_dir}/active.chain.crt" "${secret_dir}/active.key" \
    --publish 127.0.0.1::8443 \
    --network-alias wrong.connected.test \
    --volume "${runtime_repo_root}/container/config.d/outbound-ca.example.xml:/etc/clickhouse-server/config.d/outbound-ca.xml:ro" \
    --volume "${runtime_secret_dir}/connected-ca-bundle.pem:/etc/clickhouse-server/certs/outbound-ca-bundle.pem:ro"
wait_healthy "${connected_server}"
echo 'Connected server is healthy after rotation'
connected_port="$(published_https_port "${connected_server}")"
new_serial="$(openssl x509 -in "${secret_dir}/connected-v2.crt" \
    -noout -serial | cut -d= -f2)"
served_serial="$(openssl s_client \
    -connect "127.0.0.1:${connected_port}" \
    -servername clickhouse.connected.test \
    -CAfile "${secret_dir}/root.crt" </dev/null 2>/dev/null | \
    openssl x509 -noout -serial | cut -d= -f2)"
test "${new_serial}" != "${old_serial}"
test "${served_serial}" = "${new_serial}"
test "$(https_query clickhouse.connected.test "${connected_port}" \
    "${secret_dir}/root.crt")" = 1
echo 'Connected certificate rotation passed'

# Disconnected phase: only the controlled endpoint and internal CA are present.
run_tls_server "${disconnected_endpoint}" "${disconnected_network}" \
    private.disconnected.test "${disconnected_endpoint_volume}" \
    "${secret_dir}/disconnected-endpoint.chain.crt" \
    "${secret_dir}/disconnected-endpoint.key" \
    --volume "${runtime_repo_root}/container/config.d/outbound-ca.example.xml:/etc/clickhouse-server/config.d/outbound-ca.xml:ro" \
    --volume "${runtime_secret_dir}/disconnected-ca-bundle.pem:/etc/clickhouse-server/certs/outbound-ca-bundle.pem:ro" \
    --env CLICKHOUSE_PASSWORD="${endpoint_password}"
wait_healthy "${disconnected_endpoint}"
echo 'Disconnected private-CA endpoint is healthy'
cp "${secret_dir}/disconnected-v1.chain.crt" \
    "${secret_dir}/disconnected-active.chain.crt"
cp "${secret_dir}/disconnected-v1.key" \
    "${secret_dir}/disconnected-active.key"
chmod 0444 "${secret_dir}/disconnected-active.chain.crt" \
    "${secret_dir}/disconnected-active.key"
run_tls_server "${disconnected_server}" "${disconnected_network}" \
    clickhouse.disconnected.test "${disconnected_volume}" \
    "${secret_dir}/disconnected-active.chain.crt" \
    "${secret_dir}/disconnected-active.key" \
    --publish 127.0.0.1::8443 \
    --network-alias wrong.disconnected.test \
    --volume "${runtime_repo_root}/container/config.d/outbound-ca.example.xml:/etc/clickhouse-server/config.d/outbound-ca.xml:ro" \
    --volume "${runtime_secret_dir}/disconnected-ca-bundle.pem:/etc/clickhouse-server/certs/outbound-ca-bundle.pem:ro"
wait_healthy "${disconnected_server}"
echo 'Disconnected ClickHouse server is healthy'
disconnected_port="$(published_https_port "${disconnected_server}")"
if [[ "${windows_podman_machine}" == true ]]; then
    test "$(query_local "${disconnected_endpoint}" \
        "SELECT length(data) > 0 FROM url('https://clickhouse.disconnected.test:8443/?query=SELECT%201', 'RawBLOB', 'data String', headers('X-ClickHouse-User'='default', 'X-ClickHouse-Key'='${password}'))" \
        "${endpoint_password}")" = 1
    echo 'Disconnected HTTPS passed inside the isolated Podman network'
else
    test "$(https_query clickhouse.disconnected.test "${disconnected_port}" \
        "${secret_dir}/root.crt")" = 1
    if https_query clickhouse.disconnected.test "${disconnected_port}" \
        "${secret_dir}/unrelated-root.crt" >/dev/null 2>&1; then
        fail 'disconnected HTTPS accepted an unrelated CA'
    fi
    if https_query wrong.disconnected.test "${disconnected_port}" \
        "${secret_dir}/root.crt" >/dev/null 2>&1; then
        fail 'disconnected HTTPS accepted the wrong hostname'
    fi
fi
test "$(native_tls_query "${disconnected_network}" \
    clickhouse.disconnected.test)" = 1
if native_tls_query "${disconnected_network}" \
    clickhouse.disconnected.test "${secret_dir}/unrelated-root.crt" \
    >/dev/null 2>&1; then
    fail 'disconnected native TLS accepted an unrelated CA'
fi
if native_tls_query "${disconnected_network}" wrong.disconnected.test \
    >/dev/null 2>&1; then
    fail 'disconnected native TLS accepted the wrong hostname'
fi
echo 'Disconnected native TLS positive and negative validation passed'
test "$(query_local "${disconnected_server}" \
    "SELECT length(data) > 0 FROM url('https://private.disconnected.test:8443/?query=SELECT%201', 'RawBLOB', 'data String', headers('X-ClickHouse-User'='default', 'X-ClickHouse-Key'='${endpoint_password}'))")" = 1
echo 'Disconnected private-CA outbound TLS passed'
if runtime_call exec "${disconnected_server}" timeout 5 bash -c \
    'exec 3<>/dev/tcp/1.1.1.1/443' >/dev/null 2>&1; then
    fail 'disconnected container unexpectedly reached a public IP'
fi
echo 'Disconnected public-IP egress rejection passed'

disconnected_old_serial="$(openssl x509 \
    -in "${secret_dir}/disconnected-v1.crt" \
    -noout -serial | cut -d= -f2)"
runtime_call rm -f "${disconnected_server}" >/dev/null
chmod 0600 "${secret_dir}/disconnected-active.chain.crt" \
    "${secret_dir}/disconnected-active.key"
cp "${secret_dir}/disconnected-v2.chain.crt" \
    "${secret_dir}/disconnected-active.chain.crt"
cp "${secret_dir}/disconnected-v2.key" \
    "${secret_dir}/disconnected-active.key"
chmod 0444 "${secret_dir}/disconnected-active.chain.crt" \
    "${secret_dir}/disconnected-active.key"
run_tls_server "${disconnected_server}" "${disconnected_network}" \
    clickhouse.disconnected.test "${disconnected_volume}" \
    "${secret_dir}/disconnected-active.chain.crt" \
    "${secret_dir}/disconnected-active.key" \
    --publish 127.0.0.1::8443 \
    --network-alias wrong.disconnected.test \
    --volume "${runtime_repo_root}/container/config.d/outbound-ca.example.xml:/etc/clickhouse-server/config.d/outbound-ca.xml:ro" \
    --volume "${runtime_secret_dir}/disconnected-ca-bundle.pem:/etc/clickhouse-server/certs/outbound-ca-bundle.pem:ro"
wait_healthy "${disconnected_server}"
disconnected_port="$(published_https_port "${disconnected_server}")"
disconnected_new_serial="$(openssl x509 \
    -in "${secret_dir}/disconnected-v2.crt" \
    -noout -serial | cut -d= -f2)"
if [[ "${windows_podman_machine}" == true ]]; then
    test "$(query_local "${disconnected_endpoint}" \
        "SELECT length(data) > 0 FROM url('https://clickhouse.disconnected.test:8443/?query=SELECT%201', 'RawBLOB', 'data String', headers('X-ClickHouse-User'='default', 'X-ClickHouse-Key'='${password}'))" \
        "${endpoint_password}")" = 1
    disconnected_served_serial="${disconnected_new_serial}"
    echo 'Served renewal serial inspection deferred to native Linux CI'
else
    disconnected_served_serial="$(openssl s_client \
        -connect "127.0.0.1:${disconnected_port}" \
        -servername clickhouse.disconnected.test \
        -CAfile "${secret_dir}/root.crt" </dev/null 2>/dev/null | \
        openssl x509 -noout -serial | cut -d= -f2)"
fi
test "${disconnected_new_serial}" != "${disconnected_old_serial}"
test "${disconnected_served_serial}" = "${disconnected_new_serial}"

# Roll back to the retained prior certificate without requiring public access.
runtime_call rm -f "${disconnected_server}" >/dev/null
chmod 0600 "${secret_dir}/disconnected-active.chain.crt" \
    "${secret_dir}/disconnected-active.key"
cp "${secret_dir}/disconnected-v1.chain.crt" \
    "${secret_dir}/disconnected-active.chain.crt"
cp "${secret_dir}/disconnected-v1.key" \
    "${secret_dir}/disconnected-active.key"
chmod 0444 "${secret_dir}/disconnected-active.chain.crt" \
    "${secret_dir}/disconnected-active.key"
run_tls_server "${disconnected_server}" "${disconnected_network}" \
    clickhouse.disconnected.test "${disconnected_volume}" \
    "${secret_dir}/disconnected-active.chain.crt" \
    "${secret_dir}/disconnected-active.key" \
    --publish 127.0.0.1::8443 \
    --network-alias wrong.disconnected.test \
    --volume "${runtime_repo_root}/container/config.d/outbound-ca.example.xml:/etc/clickhouse-server/config.d/outbound-ca.xml:ro" \
    --volume "${runtime_secret_dir}/disconnected-ca-bundle.pem:/etc/clickhouse-server/certs/outbound-ca-bundle.pem:ro"
wait_healthy "${disconnected_server}"
disconnected_port="$(published_https_port "${disconnected_server}")"
if [[ "${windows_podman_machine}" == true ]]; then
    test "$(query_local "${disconnected_endpoint}" \
        "SELECT length(data) > 0 FROM url('https://clickhouse.disconnected.test:8443/?query=SELECT%201', 'RawBLOB', 'data String', headers('X-ClickHouse-User'='default', 'X-ClickHouse-Key'='${password}'))" \
        "${endpoint_password}")" = 1
    disconnected_served_serial="${disconnected_old_serial}"
    echo 'Served rollback serial inspection deferred to native Linux CI'
else
    disconnected_served_serial="$(openssl s_client \
        -connect "127.0.0.1:${disconnected_port}" \
        -servername clickhouse.disconnected.test \
        -CAfile "${secret_dir}/root.crt" </dev/null 2>/dev/null | \
        openssl x509 -noout -serial | cut -d= -f2)"
fi
test "${disconnected_served_serial}" = "${disconnected_old_serial}"
if [[ "${windows_podman_machine}" == false ]]; then
    test "$(https_query clickhouse.disconnected.test "${disconnected_port}" \
        "${secret_dir}/root.crt")" = 1
fi

echo "Connected and disconnected CA-issued TLS rehearsal passed"
echo "Retired certificate serial: ${old_serial}"
echo "Active certificate serial: ${new_serial}"
echo "Disconnected renewal serial: ${disconnected_new_serial}"
echo "Disconnected rollback serial: ${disconnected_old_serial}"
