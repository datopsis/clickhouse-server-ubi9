#!/usr/bin/env bash
set -Eeuo pipefail

runtime="${CONTAINER_RUNTIME:-podman}"
target_image="${IMAGE:-ghcr.io/datopsis/clickhouse-server-ubi9:test}"
scanner_image="${SCAP_SCANNER_IMAGE:-localhost/datopsis-openscap:0.1.82}"
architecture="${ARCHITECTURE:-$(uname -m)}"
results_dir="${SCAP_RESULTS_DIR:-scap-results-${architecture}}"

case "${runtime}" in
    podman | docker) ;;
    *)
        echo "Unsupported CONTAINER_RUNTIME '${runtime}'; use podman or docker" >&2
        exit 1
        ;;
esac

command -v "${runtime}" >/dev/null 2>&1 || {
    echo "Container runtime not found: ${runtime}" >&2
    exit 1
}
command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required to create the SCAP result inventory" >&2
    exit 1
}

mkdir -p "${results_dir}"
results_dir="$(cd "${results_dir}" && pwd -P)"
rootfs_tar="${results_dir}/rootfs.tar"
container_id=""

cleanup() {
    if [[ -n "${container_id}" ]]; then
        "${runtime}" rm --force "${container_id}" >/dev/null 2>&1 || true
    fi
    rm -f -- "${rootfs_tar}"
}
trap cleanup EXIT

container_id="$("${runtime}" create "${target_image}")"
"${runtime}" export --output "${rootfs_tar}" "${container_id}"
"${runtime}" rm "${container_id}" >/dev/null
container_id=""

target_image_id="$("${runtime}" image inspect --format '{{.Id}}' "${target_image}")"
scanner_image_id="$("${runtime}" image inspect --format '{{.Id}}' "${scanner_image}")"

volume_label=""
if [[ "${runtime}" == "podman" ]]; then
    volume_label=",Z"
fi

"${runtime}" run --rm \
    --network none \
    --read-only \
    --user 0:0 \
    --cap-drop all \
    --cap-add chown \
    --cap-add dac_override \
    --cap-add fowner \
    --cap-add sys_chroot \
    --security-opt no-new-privileges \
    --pids-limit 256 \
    --memory 4g \
    --tmpfs /scan-root:rw,nosuid,nodev,size=3g \
    --tmpfs /tmp:rw,nosuid,nodev,size=512m \
    --volume "${rootfs_tar}:/input/rootfs.tar:ro${volume_label}" \
    --volume "${results_dir}:/results:rw${volume_label}" \
    "${scanner_image}"

python3 scripts/scap-summary.py \
    --results "${results_dir}/results.xccdf.xml" \
    --output "${results_dir}/summary.json" \
    --architecture "${architecture}" \
    --profile xccdf_org.ssgproject.content_profile_standard \
    --target-image "${target_image}" \
    --target-image-id "${target_image_id}" \
    --scanner-image "${scanner_image}" \
    --scanner-image-id "${scanner_image_id}" \
    --datastream-sha256 92204daafbf4f38011671ef034fae4cffb48f708516186710346a9ec702a1f8f

echo "SCAP discovery evidence written to ${results_dir}"
