#!/usr/bin/env bash
set -Eeuo pipefail

readonly input_tar="/input/rootfs.tar"
readonly scan_root="/scan-root"
readonly results_dir="/results"
readonly data_stream="/opt/scap/ssg-rhel9-ds.xml"
readonly profile="xccdf_org.ssgproject.content_profile_standard"

if [[ ! -r "${input_tar}" ]]; then
    echo "SCAP input is not readable: ${input_tar}" >&2
    exit 1
fi
if [[ ! -d "${results_dir}" || ! -w "${results_dir}" ]]; then
    echo "SCAP results directory is not writable: ${results_dir}" >&2
    exit 1
fi
if [[ ! -d "${scan_root}" || ! -w "${scan_root}" ]]; then
    echo "SCAP extraction directory must be a writable tmpfs: ${scan_root}" >&2
    exit 1
fi

# Docker/Podman creates this archive from a stopped container. Extracting here
# as namespaced root preserves the numeric owners OpenSCAP evaluates. Target
# content is data only: nothing from the exported filesystem is executed.
tar --extract --file "${input_tar}" --directory "${scan_root}" --same-owner

sha256sum "${data_stream}" > "${results_dir}/datastream.sha256"
oscap --version > "${results_dir}/openscap-version.txt"
rpm --query openscap openscap-scanner > "${results_dir}/openscap-packages.txt"
rpm --query --all --queryformat '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' \
    | sort > "${results_dir}/scanner-packages.txt"

# OSCAP_PROBE_ROOT is OpenSCAP's documented offline-filesystem mechanism and
# is what the oscap-chroot convenience wrapper configures. UBI AppStream ships
# openscap-scanner but not the openscap-utils package containing that wrapper.
export OSCAP_PROBE_ROOT="${scan_root}"

set +e
oscap xccdf eval \
    --profile "${profile}" \
    --results-arf "${results_dir}/results.arf.xml" \
    --results "${results_dir}/results.xccdf.xml" \
    --report "${results_dir}/report.html" \
    "${data_stream}"
oscap_status=$?
set -e

printf '%s\n' "${oscap_status}" > "${results_dir}/oscap-exit-code.txt"
case "${oscap_status}" in
    0 | 2)
        # OpenSCAP uses 2 for a completed evaluation with noncompliant rules.
        # Findings are report-only during baseline discovery.
        ;;
    *)
        echo "OpenSCAP evaluation failed with exit code ${oscap_status}" >&2
        exit "${oscap_status}"
        ;;
esac
