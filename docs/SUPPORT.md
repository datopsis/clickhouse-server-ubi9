# First-release support boundary

## Image and ClickHouse versions

Each published tag supports only the exact ClickHouse version, UBI image
digests, architectures, configuration contract, and evidence recorded for that
release. The Containerfile accepts build arguments for engineering tests, but a
different ClickHouse or UBI version is a new unqualified image until the full
build, smoke, TLS, scanner, SBOM, and platform suite passes. Version selection
is a build-time decision, not a runtime switch.

The intended first-release architectures are native `linux/amd64` and
`linux/arm64`.

## Host and runtime boundary

The proposed production support baseline is:

- a currently supported RHEL 9 container host with its vendor-supported Podman
  and OCI runtime, matching the UBI 9 major version; or
- a qualified OpenShift 4 release whose RHCOS/RHEL basis and restricted security
  policy pass the documented OpenShift procedure.

Podman 5.3.1 is the oldest engine on which the current smoke suite has been
recorded, producing the existing 5.3-or-newer test floor. The exact release
candidate still needs a recorded RHEL minor release, Podman client/server, OCI
runtime, kernel, SELinux state, and OpenShift release before v1.0. Record them
in `docs/QUALIFICATION.md`; do not infer production support from an image build
alone.

Red Hat's current
[container compatibility matrix](https://access.redhat.com/support/policy/rhel-container-compatibility)
lists UBI 9 images as runnable on supported RHEL 8, 9, and 10 hosts, but calls a
matching image/host major version the fully compatible configuration. Newer
userspace on an older kernel carries additional workload-specific conditions
and risk. For the first release, RHEL 8, RHEL 10, non-Red-Hat Linux, Docker,
desktop Podman machines, and upstream Kubernetes are portability or CI evidence,
not production-support claims, unless separately qualified and recorded.

Red Hat support for this community ClickHouse image is limited to eligible Red
Hat/UBI layers and platform components under the applicable subscription and
[container support policy](https://access.redhat.com/support/policy/container-support-policy).
It does not make ClickHouse or this assembled community image a Red Hat-supported
application.

## Host responsibilities

Containers share the host kernel. The host/platform owns kernel security,
cgroups, namespaces, seccomp, SELinux enforcement, FIPS mode, time, storage
drivers, network enforcement, runtime patching, and node vulnerability
management. The image owns its userspace files, non-root default, entrypoint,
ClickHouse configuration contract, and declared dependencies. Deployment
manifests and operational automation belong in `clickhouse-production-stack`.

## TLS modes

The container can run both with and without TLS:

- the default ClickHouse ports `8123` and `9000` are clear text and are intended
  for controlled development or a deployment where an approved platform
  component terminates TLS;
- mounting the documented TLS configuration enables `8443` and `9440` and
  removes the clear-text client listeners;
- a custom configuration can support mixed listeners, but that is not the
  recommended production profile and must be assessed as a distinct exposure.

The runtime does not generate keys or silently enable TLS. The operator selects
the mode through mounted configuration and controls which ports are published.
