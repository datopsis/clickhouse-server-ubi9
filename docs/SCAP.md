# SCAP compliance scanning

SCAP is useful as a configuration-compliance control for this image, but an
unmodified RHEL host profile is not an appropriate release gate for a minimal
container. Many RHEL rules govern the kernel, boot loader, partitions, systemd,
audit daemon, host networking, or machine-wide security policy. Those controls
belong to the container host or deployment platform and are outside this
image's control.

The project will therefore establish a measured baseline first, then maintain
a tailored UBI 9 Micro container profile containing only applicable,
image-owned rules. Passing that profile means the inspected image filesystem
meets the documented rules; it is not a claim that the image, host, OpenShift
cluster, or complete ClickHouse deployment is CIS- or STIG-certified.

## Recommended CI architecture

Do not run Podman inside Podman and do not mount a Docker or Podman socket into
the scanner. Nested container engines commonly require additional namespace,
device, seccomp, and capability allowances. A mounted engine socket also gives
the job control over the host engine. Either design makes the scanner a larger
privileged attack surface than the artifact being inspected warrants.

Use this flow instead:

1. Build and smoke-test the architecture-specific image in the existing native
   CI job.
2. Create a stopped container and export its merged filesystem into an
   ephemeral staging directory. Exporting does not execute image content.
3. Run a digest-pinned UBI 9 OpenSCAP tool image with the exported filesystem
   mounted read-only and a separate results directory mounted read-write.
4. Run `oscap-chroot` against the read-only root and a pinned RHEL 9 data
   stream. Give the scanner no engine socket, host namespaces, secrets, or
   network access during evaluation. Grant only the minimum chroot-related
   capability proven necessary by the qualification test.
5. Upload the ARF XML, XCCDF results, HTML report, tool/content versions, data
   stream hash, image digest, architecture, and tailoring hash as CI evidence.
6. Delete the exported root filesystem and stopped container after the job.

The scanner process may run as UID 0 *inside its isolated scanner container* so
it can inspect the mounted tree. That is different from granting the workflow a
privileged container, host root, an engine socket, or broad host mounts. The
target filesystem remains read-only and the ClickHouse image is never started
as root.

The implementation must first prove whether `CAP_SYS_CHROOT` alone is needed.
If the selected runner cannot operate with that narrow allowance, stop and
review the design rather than adding `--privileged` or broad capabilities.

## Profile-development method

The first implementation pull request should:

- pin the OpenSCAP engine, ComplianceAsCode content, and scanner-image digest;
- verify the downloaded or packaged RHEL 9 data stream and record its SHA-256;
- run the upstream RHEL 9 Standard profile in discovery/report-only mode;
- classify every result as applicable, not applicable, inherited from the
  platform, pass, fail, error, or not checked;
- commit an XCCDF tailoring file with a Datopsis-specific profile identifier;
- commit a rationale table mapping each selected rule to the image-owned file,
  package, account, or permission it evaluates;
- explicitly exclude host-only rules for the kernel, boot loader, partitions,
  mount layout, system services, audit subsystem, host firewall, host sysctls,
  SELinux enforcement mode, and FIPS mode;
- avoid automatic remediation, because remediation can silently mutate the
  image after its tested build steps and invalidate other evidence.

Candidate rule families include RPM/package integrity and signatures, account
and password-file permissions, empty-password checks, unexpected setuid/setgid
or world-writable files, service-account shells, and relevant crypto-policy
files. Exact rule IDs must come from the pinned data stream after discovery;
they must not be guessed from another RHEL content version.

## Enforcement rollout

SCAP integration should be incremental:

1. **Discovery:** publish complete reports without blocking while the tailoring
   and applicability decisions are reviewed.
2. **Stabilization:** require the scan to execute successfully on native AMD64
   and ARM64 for at least three scheduled or `main` runs. Evaluation errors
   always fail; selected-rule findings remain visible but temporarily
   non-blocking.
3. **Enforcement:** make failure of a selected, image-owned rule blocking. Keep
   exclusions and any accepted exception documented with owner, rationale, and
   review date.
4. **Drift review:** re-run discovery whenever the UBI major version, OpenSCAP
   engine, ComplianceAsCode data stream, or tailoring changes.

Before enforcement, compare one image digest's `oscap-chroot` result with
`oscap-podman` on a disposable RHEL 9 host. Investigate differences in platform
facts, applicability, and rule results. This is a qualification cross-check,
not a reason to give routine GitHub-hosted CI root access.

## Local Red Hat reproduction

On a disposable RHEL 9 test host with the OpenSCAP container tooling installed,
the reference scan remains:

```console
sudo oscap-podman <image-id> xccdf eval \
  --profile <datopsis-profile-id> \
  --tailoring-file datopsis-ubi9-micro-tailoring.xml \
  --results-arf results.arf.xml \
  --report report.html \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
```

`oscap-podman` requires root because it integrates with local container storage.
Use only a dedicated test host containing no unrelated workloads or secrets.
Record the exact image digest, host version, Podman/OpenSCAP versions, content
package version, tailoring hash, command, and sanitized results.

## Security boundaries beyond SCAP

SCAP complements rather than replaces vulnerability scanning, behavioral
tests, supply-chain verification, and deployment controls. Before the first
release, also complete a concise image threat model, review SBOM/package drift,
exercise secret and certificate rotation without log disclosure, and define a
base-image rebuild and vulnerability-response SLA.

The separate `clickhouse-production-stack` repository should own admission
policy for digest/signature/attestation verification, NetworkPolicy and egress
allowlists, platform TLS automation, secret-store integration, backup
encryption and immutable/off-site copies, restore tests, audit-log routing,
monitoring, and deployment-level incident response. Those controls cannot be
proven by scanning this image filesystem.

Authoritative references:

- [Red Hat RHEL 9 Security hardening: scanning container and container images](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/security_hardening/scanning-the-system-for-configuration-compliance-and-vulnerabilities_security-hardening)
- [OpenSCAP User Manual: scanning an arbitrary filesystem](https://static.open-scap.org/openscap-1.3/oscap_user_manual.html)
- [ComplianceAsCode content and container applicability](https://github.com/ComplianceAsCode/content)
