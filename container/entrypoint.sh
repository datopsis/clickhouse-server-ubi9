#!/usr/bin/bash
set -Eeuo pipefail
shopt -s nullglob

readonly CONFIG_FILE="${CLICKHOUSE_CONFIG:-/etc/clickhouse-server/config.xml}"
readonly HEALTH_CLIENT_CONFIG="/usr/local/share/clickhouse-health-client.xml"
readonly GENERATED_DIR="/tmp/clickhouse-entrypoint"
readonly USERS_FILE="${GENERATED_DIR}/users.xml"
readonly INIT_DIR="/docker-entrypoint-initdb.d"
DATA_DIR=""

extract_config_values() {
    local key=$1

    clickhouse extract-from-config \
        --config-file "${CONFIG_FILE}" --key "${key}" --try 2>/dev/null || true
}

normalize_directory() {
    local path=$1

    if [[ "${path}" == /* ]]; then
        printf '%s\n' "${path%/}"
    elif [[ "${path}" == "." ]]; then
        printf '%s\n' "${DATA_DIR}"
    else
        printf '%s\n' "${DATA_DIR}/${path%/}"
    fi
}

prepare_directory() {
    local path=$1

    if ! mkdir -p -- "${path}" || [[ ! -d "${path}" || ! -w "${path}" || ! -x "${path}" ]]; then
        echo "Required ClickHouse directory is not writable: ${path}" >&2
        echo "Container identity: uid=$(id -u) gid=$(id -g)" >&2
        echo "Provision the mount for this identity or an OpenShift-compatible writable group; this image does not start as root or change ownership." >&2
        exit 1
    fi
}

prepare_configured_directories() {
    local key path log_path
    local -a values=()
    local -A prepared=()

    if [[ -n "${CLICKHOUSE_DATA_DIR:-}" ]]; then
        echo "CLICKHOUSE_DATA_DIR is not supported because ClickHouse storage is controlled by <path> in ${CONFIG_FILE}." >&2
        echo "Mount a configuration fragment that sets <path> and provision that configured directory instead." >&2
        exit 1
    fi

    DATA_DIR="$(extract_config_values path)"
    DATA_DIR="${DATA_DIR%/}"
    if [[ -z "${DATA_DIR}" || "${DATA_DIR}" != /* ]]; then
        echo "ClickHouse <path> must resolve to a non-empty absolute directory in ${CONFIG_FILE}." >&2
        exit 1
    fi

    prepare_directory "${DATA_DIR}"
    prepared["${DATA_DIR}"]=1

    for key in tmp_path user_files_path format_schema_path \
        'storage_configuration.disks.*.path' \
        'storage_configuration.disks.*.metadata_path'; do
        readarray -t values < <(extract_config_values "${key}")
        for path in "${values[@]}"; do
            [[ -z "${path}" ]] && continue
            path="$(normalize_directory "${path}")"
            if [[ -z "${prepared["${path}"]:-}" ]]; then
                prepare_directory "${path}"
                prepared["${path}"]=1
            fi
        done
    done

    for key in logger.log logger.errorlog; do
        log_path="$(extract_config_values "${key}")"
        [[ -z "${log_path}" ]] && continue
        if [[ "${log_path}" == /* && -e "${log_path}" && -w "${log_path}" ]]; then
            continue
        fi
        path="$(normalize_directory "$(dirname -- "${log_path}")")"
        if [[ -z "${prepared["${path}"]:-}" ]]; then
            prepare_directory "${path}"
            prepared["${path}"]=1
        fi
    done
}

load_password() {
    if [[ -n "${CLICKHOUSE_PASSWORD_FILE:-}" ]]; then
        if [[ ! -r "${CLICKHOUSE_PASSWORD_FILE}" ]]; then
            echo "CLICKHOUSE_PASSWORD_FILE is not readable: ${CLICKHOUSE_PASSWORD_FILE}" >&2
            exit 1
        fi
        CLICKHOUSE_PASSWORD="$(<"${CLICKHOUSE_PASSWORD_FILE}")"
    fi
    export CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-}"
}

write_users_config() {
    local networks

    mkdir -p "${GENERATED_DIR}"
    if [[ -n "${CLICKHOUSE_PASSWORD}" ]]; then
        networks='<ip>::/0</ip>'
    else
        networks='<ip>::1</ip><ip>127.0.0.1</ip>'
        echo "No CLICKHOUSE_PASSWORD was supplied; the default user is restricted to localhost." >&2
    fi

    cat > "${USERS_FILE}" <<EOF
<?xml version="1.0"?>
<clickhouse>
    <profiles>
        <default/>
    </profiles>
    <users>
        <default>
            <password from_env="CLICKHOUSE_PASSWORD"/>
            <networks>${networks}</networks>
            <profile>default</profile>
            <quota>default</quota>
            <access_management>1</access_management>
        </default>
    </users>
    <quotas>
        <default>
            <interval>
                <duration>3600</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>0</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </default>
    </quotas>
</clickhouse>
EOF
    chmod 0600 "${USERS_FILE}"
}

client_command() {
    local -n command_ref=$1
    local port

    command_ref=(
        env -u CLICKHOUSE_CONFIG
        clickhouse-client
        --config-file "${HEALTH_CLIENT_CONFIG}"
        --host 127.0.0.1
        --user default
    )
    if [[ -n "${CLICKHOUSE_PASSWORD}" ]]; then
        command_ref+=(--password "${CLICKHOUSE_PASSWORD}")
    fi

    port="$(clickhouse extract-from-config \
        --config-file "${CONFIG_FILE}" --key tcp_port --try 2>/dev/null || true)"
    if [[ -n "${port}" ]]; then
        command_ref+=(--port "${port}")
        return
    fi

    port="$(clickhouse extract-from-config \
        --config-file "${CONFIG_FILE}" --key tcp_port_secure --try 2>/dev/null || true)"
    if [[ -z "${port}" ]]; then
        echo "Neither tcp_port nor tcp_port_secure is configured" >&2
        exit 1
    fi

    # This client connects only over container loopback for initialization and
    # health. External clients must validate the server certificate normally.
    command_ref+=(--port "${port}" --secure)
}

healthcheck() {
    local -a client
    load_password
    client_command client
    exec "${client[@]}" --query "SELECT 1"
}

initialize_database() {
    local -a init_files=("${INIT_DIR}"/*)
    local -a client
    local server_pid tries file

    if [[ -d "${DATA_DIR}/data" && -z "${CLICKHOUSE_ALWAYS_RUN_INITDB_SCRIPTS:-}" ]]; then
        return
    fi
    if [[ ${#init_files[@]} -eq 0 && -z "${CLICKHOUSE_DB:-}" ]]; then
        return
    fi

    echo "Starting temporary ClickHouse server for initialization"
    clickhouse-server --config-file="${CONFIG_FILE}" -- --listen_host=127.0.0.1 &
    server_pid=$!
    trap 'kill -TERM "${server_pid}" 2>/dev/null || true; wait "${server_pid}" 2>/dev/null || true' EXIT

    client_command client
    tries="${CLICKHOUSE_INIT_TIMEOUT:-60}"
    until "${client[@]}" --query "SELECT 1" >/dev/null 2>&1; do
        if ! kill -0 "${server_pid}" 2>/dev/null; then
            echo "Temporary ClickHouse server exited during initialization" >&2
            wait "${server_pid}"
            exit 1
        fi
        if (( tries <= 0 )); then
            echo "Timed out waiting for ClickHouse initialization server" >&2
            exit 1
        fi
        ((tries--))
        sleep 1
    done

    if [[ -n "${CLICKHOUSE_DB:-}" ]]; then
        if [[ ! "${CLICKHOUSE_DB}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            echo "CLICKHOUSE_DB must be an unquoted ClickHouse identifier" >&2
            exit 1
        fi
        "${client[@]}" --query "CREATE DATABASE IF NOT EXISTS \`${CLICKHOUSE_DB}\`"
    fi

    for file in "${init_files[@]}"; do
        case "${file}" in
            *.sh)
                echo "Running ${file}"
                if [[ -x "${file}" ]]; then
                    "${file}"
                else
                    # shellcheck source=/dev/null
                    source "${file}"
                fi
                ;;
            *.sql)
                echo "Running ${file}"
                "${client[@]}" --multiquery < "${file}"
                ;;
            *.sql.gz)
                echo "Running ${file}"
                gzip -dc "${file}" | "${client[@]}" --multiquery
                ;;
            *) echo "Ignoring ${file}" ;;
        esac
    done

    kill -TERM "${server_pid}"
    wait "${server_pid}"
    trap - EXIT
}

main() {
    if [[ "${1:-}" == "healthcheck" ]]; then
        healthcheck
    fi

    if [[ "${CLICKHOUSE_USER:-default}" != "default" ]]; then
        echo "This image currently configures only the default ClickHouse user; create additional users with SQL or mounted configuration." >&2
        exit 1
    fi

    if [[ $# -eq 0 || "${1:-}" == --* ]]; then
        load_password
        prepare_configured_directories
        write_users_config
        initialize_database
        cd "${DATA_DIR}"
        exec clickhouse-server --config-file="${CONFIG_FILE}" "$@"
    fi

    exec "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
