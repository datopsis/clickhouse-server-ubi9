#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="$(mktemp -d)"
trap 'rm -rf "${fixture_dir}"' EXIT

cp "${repo_root}/Containerfile" "${fixture_dir}/Containerfile"
printf '# Changelog\n\n## [v26.8.2.7-ubi9.8-1] - 2026-09-06\n' \
    > "${fixture_dir}/CHANGELOG.md"

run_validator() {
    CONTAINERFILE="${fixture_dir}/Containerfile" \
        CHANGELOG_FILE="${fixture_dir}/CHANGELOG.md" \
        bash "${repo_root}/scripts/validate-release-tag.sh" "$@"
}

expect_failure() {
    if run_validator "$@" >/dev/null 2>&1; then
        echo "Release tag unexpectedly passed validation: $*" >&2
        exit 1
    fi
}

run_validator v26.8.2.7-ubi9.8-1
expect_failure v26.8.2.8-ubi9.8-1
expect_failure v26.8.2.7-ubi9.9-1
expect_failure v26.8.2.7-ubi9.8-0
expect_failure release-26.8.2.7

git -C "${fixture_dir}" init --quiet
git -C "${fixture_dir}" config user.name "Release test"
git -C "${fixture_dir}" config user.email "release-test@example.invalid"
git -C "${fixture_dir}" add Containerfile CHANGELOG.md
git -C "${fixture_dir}" commit --quiet --message "test fixture"
git -C "${fixture_dir}" tag --annotate v26.8.2.7-ubi9.8-1 --message "test release"
(
    cd "${fixture_dir}"
    run_validator v26.8.2.7-ubi9.8-1 --require-annotated
)
git -C "${fixture_dir}" tag --delete v26.8.2.7-ubi9.8-1 >/dev/null
git -C "${fixture_dir}" tag v26.8.2.7-ubi9.8-1
if (
    cd "${fixture_dir}"
    run_validator v26.8.2.7-ubi9.8-1 --require-annotated >/dev/null 2>&1
); then
    echo "Lightweight release tag unexpectedly passed validation" >&2
    exit 1
fi

printf '# Changelog\n' > "${fixture_dir}/CHANGELOG.md"
expect_failure v26.8.2.7-ubi9.8-1

echo "Release tag validation tests passed"
