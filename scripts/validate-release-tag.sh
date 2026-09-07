#!/usr/bin/env bash
set -Eeuo pipefail

tag="${1:-${GITHUB_REF_NAME:-}}"
require_annotated="${2:-}"
containerfile="${CONTAINERFILE:-Containerfile}"
changelog="${CHANGELOG_FILE:-CHANGELOG.md}"
if [[ ! "${tag}" =~ ^v([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)-ubi([0-9]+\.[0-9]+)-([1-9][0-9]*)$ ]]; then
    echo "Release tag must match v<clickhouse-version>-ubi<ubi-version>-<packaging-revision>" >&2
    exit 1
fi

tag_clickhouse="${BASH_REMATCH[1]}"
tag_ubi="${BASH_REMATCH[2]}"

mapfile -t clickhouse_versions < <(
    sed -n 's/^ARG CLICKHOUSE_VERSION="\([^"]*\)"/\1/p' "${containerfile}" | sort -u
)
mapfile -t ubi_versions < <(
    sed -n 's|^ARG UBI_.*_IMAGE="[^:"]*:\([^@"]*\)@sha256:[0-9a-f]*"|\1|p' "${containerfile}" | sort -u
)

if (( ${#clickhouse_versions[@]} != 1 )) || [[ "${clickhouse_versions[0]}" != "${tag_clickhouse}" ]]; then
    echo "Tag ClickHouse version ${tag_clickhouse} does not match Containerfile" >&2
    exit 1
fi

if (( ${#ubi_versions[@]} != 1 )) || [[ "${ubi_versions[0]}" != "${tag_ubi}" ]]; then
    echo "Tag UBI version ${tag_ubi} does not match Containerfile" >&2
    exit 1
fi

if ! grep -Eq "^## \[${tag}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "${changelog}"; then
    echo "CHANGELOG.md must contain a dated '## [${tag}] - YYYY-MM-DD' section" >&2
    exit 1
fi

if [[ "${require_annotated}" == "--require-annotated" ]] && \
    ! git cat-file -e "refs/tags/${tag}^{tag}" 2>/dev/null; then
    echo "Release tag ${tag} must be an annotated Git tag" >&2
    exit 1
fi

echo "Validated release tag ${tag}"
