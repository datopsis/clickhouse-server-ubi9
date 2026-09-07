#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"

cleanup() {
    rm -rf "${test_root}"
}
trap cleanup EXIT

# shellcheck source=container/entrypoint.sh
source "${repo_root}/container/entrypoint.sh"

# Isolate directory preparation from ClickHouse itself so every supported key,
# including object-storage metadata paths, can be checked deterministically.
extract_config_values() {
    case "$1" in
        path) printf '%s/\n' "${test_root}/data" ;;
        tmp_path) printf '%s\n' 'relative-tmp/' ;;
        user_files_path) printf '%s/\n' "${test_root}/user-files" ;;
        format_schema_path) printf '%s/\n' "${test_root}/format-schemas" ;;
        'storage_configuration.disks.*.path')
            printf '%s\n' 'relative-disk/'
            ;;
        'storage_configuration.disks.*.metadata_path')
            printf '%s/\n' "${test_root}/disk-metadata"
            ;;
        logger.log) printf '%s\n' '/dev/stdout' ;;
        logger.errorlog) printf '%s\n' 'logs/error.log' ;;
    esac
}

prepare_configured_directories

for expected in \
    "${test_root}/data" \
    "${test_root}/data/relative-tmp" \
    "${test_root}/user-files" \
    "${test_root}/format-schemas" \
    "${test_root}/data/relative-disk" \
    "${test_root}/disk-metadata" \
    "${test_root}/data/logs"; do
    test -d "${expected}"
done

echo "Entrypoint configured-path tests passed"
