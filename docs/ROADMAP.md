# First-release roadmap

This roadmap is the release gate for the first supported image. A checked item must have reviewable evidence in a pull request, successful workflow run, release asset, or linked issue. Items marked **deferred** are deliberate non-blockers and must not silently become release requirements.

## Release blockers

### Immediate priorities

1. Triage the current unfixed matches according to [VULNERABILITY-MANAGEMENT.md](VULNERABILITY-MANAGEMENT.md), then rebuild on the newest reviewed UBI digests and retain the before/after evidence.
2. Validate [TLS.md](TLS.md) with CA-issued certificates for HTTPS and native TCP, including rotation and a fully disconnected rehearsal.
3. Execute [PRODUCTION.md](PRODUCTION.md) on native `amd64`, native `arm64`, and OpenShift, recording resource, storage, backup/restore, shutdown, and recovery evidence.
4. Complete the ClickHouse/UBI notice and SBOM review described in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
5. Establish the tailored container SCAP baseline in [SCAP.md](SCAP.md), retain both architecture reports, and review every applicability decision before enforcing selected rules.
6. Complete the reviewed [security-control engineering and SCTM export](SECURITY-CONTROLS.md), including Database SRG/STIG provenance, control procedures, OSCAL/CSV artifacts, and ownership boundaries.
7. Resolve the [FIPS](FIPS.md) and [host/runtime support](SUPPORT.md) gates without making unsupported cryptographic or platform claims, and review the [architecture diagrams](ARCHITECTURE.md) against the release candidate.
8. Publish the first signed GHCR release only after every blocker below is complete. Reconsider Docker Hub and paid security services after that release has real consumer demand.

### Incremental delivery plan

Complete these work packages in order. Each package should normally be a separate pull request and commit so its behavior, documentation, and evidence can be reviewed before the next package changes the same release surface. Do not check a package merely because its implementation exists; retain the listed exit evidence.

This repository owns image-specific behavior, basic usage, and minimal platform qualification. Production-ready deployment compositions, cluster topology, operational automation, and environment overlays belong in the separate `clickhouse-production-stack` repository. Qualification fixtures here should be directly reusable there where practical, but must not grow into a second deployment stack.

#### 1. Rootless storage and configuration contract

**Implementation**

- [x] Replace `CLICKHOUSE_DATA_DIR` as an independent source of truth. Extract the effective ClickHouse `path` from `CLICKHOUSE_CONFIG`, use it for initialization-state detection and the server working directory, and either remove the environment variable or make any retained compatibility behavior fail on disagreement.
- [x] Make the generated users-configuration path consistent with a custom primary data path without requiring a writable container root.
- [x] Discover local writable paths from the effective configuration: the primary path, `tmp_path`, `user_files_path`, `format_schema_path`, file log directories, and every configured disk `path` and `metadata_path`.
- [x] Create missing directories as the current identity and validate that required paths are writable. Never start as root or perform an entrypoint `chown`; report the failing path and current UID/GID with actionable guidance.
- [x] Preserve compatibility with arbitrary OpenShift UIDs, UID `101`, group `0`, read-only roots, SELinux bind mounts, and storage backends where root squash prevents ownership repair.

**Tests**

- [x] Add smoke and deterministic cases for the default path, a custom config-derived primary path, additional local disk and metadata paths, restart persistence, and initialization detection on an existing custom data directory.
- [x] Add negative cases for a non-writable primary path, non-writable additional disk, disagreement with any retained legacy environment variable, relative or empty path handling, and operation without root or extra capabilities.
- [x] Run the path suite with UID `101:0` and an arbitrary OpenShift-style UID. Confirm that failures occur before partial initialization and contain no secret values.

**User documentation and exit evidence**

- [x] Add `docs/ROOTLESS.md` explaining the security model, why the image does not start as root, supported UID/GID patterns, named volumes, bind-mount preparation, Kubernetes `fsGroup`, OpenShift arbitrary UIDs, SELinux `:Z`, NFS/root-squash limitations, custom data paths, additional disks, and permission troubleshooting.
- [x] Update the README environment table, production guide, and official-image comparison so none imply that an environment variable changes ClickHouse storage by itself.
- [ ] Retain successful and intentional-failure smoke logs demonstrating every path and identity case. Review the final entrypoint against the current official ClickHouse entrypoint without copying its root/chown behavior.

#### 2. Native architecture CI qualification

**Implementation**

- [x] Change the image job to an explicit native matrix: `ubuntu-24.04` with `linux/amd64` and `ubuntu-24.04-arm` with `linux/arm64`. Build and load one native image per job; do not use QEMU as native-runtime evidence.
- [x] Run the complete smoke suite, Trivy image gate, augmented SPDX generation, blocking Grype gate, and full Grype inventory on each architecture.
- [x] Give image tags, artifacts, SARIF categories, and cache scopes architecture-specific names so parallel jobs cannot overwrite or conflate evidence.
- [x] Keep the release workflow's multi-platform manifest build, then inspect the manifest and prove that it contains the tested `linux/amd64` and `linux/arm64` variants.
- [x] Preserve the protected `image` check as an aggregate job that fails unless both native matrix jobs pass before merge.

**User documentation and exit evidence**

- [x] Update `docs/CI.md` with runner labels, native-versus-emulated boundaries, artifact names, expected architecture checks, and local reproduction commands.
- [x] Retain successful workflow URLs and per-architecture image version, package count, SBOM, vulnerability results, and smoke logs. Record runner architecture from `uname -m` rather than inferring it only from a workflow label. See [qualification evidence](QUALIFICATION.md#native-amd64-and-arm64-ci--2026-09-07).

#### 3. CA-issued connected and disconnected TLS rehearsal

**Automated connected test**

- [x] Add a test that creates an ephemeral root and intermediate CA, issues a leaf certificate with the exact test DNS SAN, and mounts only the leaf key, chain, and public trust bundle into the container.
- [x] Exercise HTTPS and native TLS with clear-text listeners removed. Require success with the correct CA and hostname and failure with an unrelated CA, wrong hostname, clear-text client, unreadable key, and incomplete chain.
- [x] Exercise outbound TLS against both a normally trusted Internet endpoint and a controlled private-CA endpoint, proving the correct CA-bundle behavior for each rather than assuming all ClickHouse integrations share one TLS client configuration.
- [x] Replace the leaf certificate through the documented rotation procedure, restart or roll out the server, verify the new serial/expiry, and prove the retired certificate is no longer served.

**Disconnected rehearsal**

- [x] Add `docs/TLS-REHEARSAL.md` with connected preparation, artifact inventory, SHA-256 recording, controlled transfer, internal image import, internal DNS, offline CSR signing, Secret/read-only mount creation, network isolation, validation, rotation, rollback, and cleanup procedures.
- [x] Automate the isolated server/client phase on an internal network with external egress denied, private-CA service trust, renewal, and rollback on native AMD64 and ARM64.
- [ ] Execute the operator rehearsal inside a representative disconnected security boundary. Preload required images/tools, generate the server key inside the boundary, transfer no CA private key, and operate without public DNS, ACME, OCSP, CRL, or package downloads unless an approved internal mirror is part of the design.

**Exit evidence**

- [ ] Retain sanitized commands, certificate subjects/issuers/SANs/serials/expiry, network-isolation proof, positive and negative connection results, rotation evidence, and confirmation that no generated private key or certificate artifact entered Git.

#### 4. OpenShift qualification and operator procedure

**Procedure documentation**

- [x] Add `docs/OPENSHIFT-TESTING.md` with step-by-step instructions for obtaining a Red Hat Developer Sandbox or using OpenShift Local, installing/logging in with `oc`, selecting a project, verifying quotas, and cleaning up all test resources.
- [x] Provide minimal qualification resources for a digest-pinned image, password Secret, TLS Secret, configuration ConfigMap, RWO PVC, Service, and HTTPS passthrough Route. Keep native TCP behind the Service. Production overlays, topology, and automation belong in `clickhouse-production-stack`.
- [x] Document GHCR public access and private `imagePullSecret` alternatives, restricted SCC expectations, arbitrary UID/group behavior, `runAsNonRoot`, read-only root filesystem, runtime-default seccomp, dropped capabilities, bounded `/tmp`, resource requests/limits, probes, and termination grace periods.
- [x] Include exact commands for inspecting assigned UID/GID, SCC admission, mounts, permissions, events, logs, health, TLS, PVC binding, and image digest. Explain common permission, admission, quota, route, certificate, and storage failures from an operator's perspective.
- [x] Add deterministic fixture-policy tests that reject root, privilege escalation, host namespaces/paths, added capabilities, clear-text service ports, mutable image placeholders in rendered use, or loss of required probes and bounded temporary storage.

**Qualification run**

- [ ] Deploy under the default restricted SCC without requesting `anyuid`, privileged mode, root, host paths, or additional capabilities.
- [ ] Verify first-start initialization, password-file handling, arbitrary-UID operation, HTTPS, native TLS inside the cluster, readiness/liveness/startup behavior, graceful deletion, PVC persistence across pod replacement, and a backup/restore of representative test data.
- [ ] Exercise a non-writable volume failure and confirm the rootless diagnostics from work package 1 identify the operator action required.
- [ ] Record the OpenShift version, cluster type, SCC, storage class/access mode, assigned UID/GID, image digest, manifests, commands, sanitized logs, and results in the release pull request.

**Fallback decision**

- [ ] If no real OpenShift environment can be obtained, run a restricted Kubernetes proxy test and explicitly mark OpenShift as unvalidated and unsupported in the first release. A Kind/K3s test does not satisfy or replace the OpenShift checklist above.

#### 5. Tailored SCAP image-compliance baseline

**Profile discovery and tailoring**

- [x] Build the scanner from the same digest-pinned UBI 9 base, pin OpenSCAP `1.3.14-1.el9_8` and ComplianceAsCode `0.1.82`, verify the release archive, and verify/record the RHEL 9 data-stream SHA-256. Retain the produced scanner image ID for every run; use a manifest digest if the tool image is later published for reuse.
- [x] Add upstream RHEL 9 STIG-profile report-only discovery against an ownership-preserving exported image filesystem; ComplianceAsCode `0.1.82` does not contain a RHEL 9 Standard profile. Treat STIG as an analysis source rather than wholesale adoption, inventory every result, and keep evaluation errors blocking without claiming host or deployment compliance.
- [ ] Create a reviewed XCCDF tailoring profile containing only rules that are applicable to and controlled by this image. Commit a rule-rationale matrix and document every host/platform exclusion.
- [ ] Exclude kernel, boot-loader, partition, mount-layout, systemd, audit, host-networking, sysctl, SELinux-mode, and FIPS-mode controls unless the image later gains direct ownership of one. Do not use automatic remediation.

**Safe CI integration**

- [x] Export the stopped, already-tested image without executing it, mount the archive read-only, and extract as namespaced root into the scanner's disposable tmpfs so numeric ownership evidence is preserved.
- [x] Configure OpenSCAP offline mode directly with `OSCAP_PROBE_ROOT` because UBI AppStream does not ship the `oscap-chroot` wrapper. Run with no Docker/Podman socket, host namespace, workflow secrets, or evaluation-time network; use a read-only scanner root, `no-new-privileges`, drop all capabilities, and add only `CHOWN`, `FOWNER`, `DAC_OVERRIDE`, and `SYS_CHROOT` for metadata preservation, restrictive-file inspection/results output, and offline probes.
- [x] Generate and retain architecture-specific ARF XML, XCCDF XML, HTML, full JSON rule inventory, target/scanner image IDs, architecture, scanner/content versions, data-stream hash, and exit code with the other image-security evidence. Add the tailoring hash when the reviewed tailoring exists.
- [ ] Run report-only on native AMD64 and ARM64 for at least three scheduled or `main` executions. Evaluation errors fail immediately; selected-rule findings become blocking only after the baseline is stable and reviewed.
- [ ] Cross-check one exact image digest with `oscap-podman` on a disposable RHEL 9 host. Reconcile platform/applicability differences before enforcement; do not grant routine hosted CI root or engine access merely to match that command.

**Exit evidence**

- [ ] Retain the discovery report, final tailoring, rule-rationale/exclusion review, three stable two-architecture runs, capability inspection, and `OSCAP_PROBE_ROOT` versus `oscap-podman` comparison.
- [ ] State precisely that the result covers selected image-filesystem controls and is not CIS/STIG certification of the host, OpenShift cluster, or production deployment.

#### 6. Security-control provenance, STIG analysis, and SCTM export

**Source acquisition and analysis**

- [ ] Follow [SECURITY-CONTROLS.md](SECURITY-CONTROLS.md). Pin and hash the current DISA Database SRG, Container Platform SRG, RHEL 9 STIG, and selected active database-product STIGs. Record title, version/release, date, URL, retrieval date, SHA-256, and sunset status in `security/stig-sources.yaml`.
- [ ] Analyze every Database SRG requirement against ClickHouse. Compare active MongoDB, PostgreSQL-distribution, Oracle Database, Oracle MySQL, Microsoft SQL Server, and any other reviewed DISA database STIGs without transferring product-specific commands or treating consensus as applicability.
- [ ] Create `security/stig-analysis.csv` with source IDs, CCI/NIST mappings, objective, threat, applicability, ownership, implementation feasibility, conflicts, residual risk, rationale, and review metadata. Explicitly record that zero product-STIG controls were inherited before this analysis.
- [ ] Require two-person review for every `adopt`, `not-applicable`, `unsupported`, and host/platform exclusion. Open an issue for unresolved or ClickHouse-unsupported requirements; do not silently omit them.

**Implementation and user choice**

- [ ] Classify adopted items as immutable image invariants, configurable ClickHouse controls, deployment controls, or organizational/inherited controls. Implement only the first two in this repository; place reusable deployment controls in `clickhouse-production-stack`.
- [ ] For each safely configurable control, provide reviewed secure and compatibility configuration fragments with exact enable/disable steps, default, restart requirement, prerequisites, operational impact, loss of protection, and verification. Do not provide an off switch for trust-boundary invariants merely for convenience.
- [ ] Add negative tests that prove disabled or weakened profiles are accurately reported as not implementing the associated control. Prevent entrypoint environment variables from silently overriding mounted control configuration.

**SCTM-consumable artifacts and assessment**

- [ ] Publish a schema-valid NIST OSCAL Component Definition as the canonical component artifact and deterministically generate `security/control-matrix.csv` for tabular SCTM import. Include NIST control/statement, CCI/STIG provenance, implementation status, responsibility, configuration, procedure, evidence, residual risk, and expiry.
- [ ] Add `docs/CONTROL-IMPLEMENTATION.md` with per-control justification and complete examine/test/interview procedures based on NIST SP 800-53A. Every claim must identify the exact image digest, configuration profile, architecture, and evidence sensitivity.
- [ ] Pin the OSCAL schema/toolchain, validate identifiers and links in CI, and fail on generated-artifact drift. Obtain cyber/ISSO review that the export is a component input, not a completed system SCTM, SSP, authorization, or STIG certification.

**Exit evidence**

- [ ] Retain the source register, complete comparison, review record, OSCAL validation, deterministic CSV check, control tests on AMD64/ARM64, and a trial import performed by the consuming cyber team.

#### 7. Cryptographic boundary, host support, and architecture review

- [ ] Adopt the current determination in [FIPS.md](FIPS.md): the upstream static ClickHouse artifact is not claimed as FIPS 140-3 validated. Record binary linkage, embedded cryptographic implementation/version, and absence or applicability of a CMVP certificate for every release.
- [ ] Decide whether v1 excludes FIPS-required deployments or introduces a separately built and qualified artifact that exclusively uses an identified validated module in its approved mode and operational environment. Require specialist/assessor review before any FIPS wording.
- [ ] Test permitted TLS versions and cipher/profile behavior on AMD64 and ARM64. Keep TLS 1.0/1.1 outside supported profiles, test TLS 1.2/1.3 and client compatibility, and never equate protocol negotiation with FIPS validation.
- [ ] Qualify the exact [host/runtime support](SUPPORT.md) baseline: supported RHEL 9 minor, kernel, Podman client/server, OCI runtime, SELinux mode, cgroup version, and native architectures. Qualify an exact OpenShift 4 release separately. Label RHEL 8/10 and other OCI platforms as unqualified until their full suite passes.
- [ ] Review every SVG in [ARCHITECTURE.md](ARCHITECTURE.md) against the release configuration and threat model. Add deployment-specific diagrams to `clickhouse-production-stack`; record ports, identities, secrets, trust anchors, storage, ingress/egress, logging, health, and control inheritance.
- [ ] Add CI validation for SVG/XML well-formedness, internal links, accessible title/description elements, prohibited scripts/external resources, and documented diagram-to-configuration consistency checks.

#### 8. Final candidate and signed release

- [ ] Refresh and review the UBI Minimal and Micro manifest-list digests together. Confirm both architectures resolve, rebuild from scratch, and retain the old/new digest and vulnerability comparison.
- [ ] Confirm the selected ClickHouse release/channel and archive checksums, run both native CI jobs, and complete the current unfixed-finding triage with owner, rationale, compensating controls, and review expiry.
- [ ] Inspect each architecture's complete SPDX inventory and embedded license files, then complete the redistribution/trademark review.
- [ ] Rehearse the tag workflow without presenting a failed candidate as a supported release. Verify manifest variants, scans, keyless signature, SPDX attestation, provenance, downloaded evidence, and release assets.
- [ ] Review every README and operator procedure from a clean clone, including rootless storage, TLS, OpenShift, production, backup/restore, upgrade, rollback, and offline transfer instructions.
- [ ] Define the first release's support boundary. Workload-specific capacity numbers remain an operator responsibility unless the project publishes a named reference workload; do not imply universal production sizing.
- [ ] Complete the changelog, obtain second-maintainer review, merge without bypassing checks, create the annotated immutable tag, watch the workflow, verify the published digest on both architectures, and announce the GHCR release with known limitations.

### Image behavior and compatibility

- [ ] Run the complete smoke suite on the final ClickHouse and UBI digests.
- [ ] Run the complete smoke suite with the supported Podman baseline and record both client and server versions; retain the native Docker-based GitHub Actions results as separate runtime evidence.
- [ ] Validate native `linux/amd64` and `linux/arm64` images, not only an emulated multi-platform build.
- [ ] Exercise the image on an OpenShift 4 cluster with an arbitrary UID, restricted security context constraints, a read-only root filesystem, and a persistent volume.
- [ ] Verify first-start initialization, password files, mounted configuration, restart persistence, graceful shutdown, and backup/restore instructions against the release candidate.
- [ ] Document tested resource limits, health-check behavior, TLS configuration boundaries, and supported upgrade paths.
- [ ] Confirm the runtime remains non-root, capability-free, and free of package managers and download clients.

### Supply chain and security

- [ ] Resolve or explicitly triage all dependency-update pull requests before tagging.
- [ ] Obtain clean Trivy and Grype gates for fixed high and critical vulnerabilities on the final image digest.
- [ ] Review scanner disagreements and record any accepted finding in the release notes with its rationale and compensating control.
- [ ] Inspect the Syft SPDX JSON for package completeness and validate that its image source matches the release digest.
- [ ] Verify the BuildKit SBOM and provenance attestations and the keyless Cosign signature against the published digest.
- [ ] Review workflow permissions, immutable action pins, secret-scanning alerts, and CodeQL/Scorecard findings.
- [ ] Test private vulnerability reporting and confirm that `SECURITY.md` names a monitored response path.
- [ ] Complete license, redistribution, trademark, and upstream-notice review for ClickHouse and Red Hat UBI content.
- [ ] Complete an image threat model covering build inputs, CI trust, registry/release publication, runtime identity, storage, ingress/egress TLS, secrets, and the boundary with `clickhouse-production-stack`.
- [ ] Define and exercise a UBI rebuild cadence and response SLA for exploitable critical/high findings, including unfixed findings that later receive a vendor fix.
- [ ] Compare final SBOM and filesystem/package inventories against the reviewed baseline and investigate unexpected additions, removals, setuid/setgid files, or world-writable paths.
- [ ] Exercise password/key/certificate rotation and failure paths while confirming logs and retained CI evidence do not expose secret material.

### Release mechanics and documentation

- [ ] Choose and validate the first tag according to [VERSION.md](VERSION.md).
- [ ] Rehearse the release workflow in a non-production package or with a disposable pre-release tag, then remove test artifacts through the GitHub UI.
- [ ] Confirm the GHCR package is public and its description, source, documentation, and license metadata point to this repository.
- [ ] Confirm release assets include `image.spdx.json`, `image.sigstore.json`, and `image.intoto.jsonl`.
- [ ] Replace the `Unreleased` changelog section with the release version and date, then add a new empty `Unreleased` section.
- [ ] Review the README quick start, operational notes, scanner behavior, artifact verification, and all documentation links from a clean clone.
- [ ] Define the supported ClickHouse channel, packaging revision policy, update cadence, and end-of-support expectations.
- [ ] Require a second maintainer to review the final release pull request even though GitHub does not enforce it yet.

## OpenSSF readiness

- [ ] Register the project for the [OpenSSF Best Practices Badge](https://www.bestpractices.dev/) when the public project metadata is complete.
- [ ] Merge routine work through reviewed pull requests so CI-Tests and Code-Review have genuine repository evidence.
- [ ] Re-run Scorecard after the release and triage every result according to [OPENSSF_SCORECARD.md](OPENSSF_SCORECARD.md).
- [ ] Verify the first release is recognized as signed after the public Scorecard data refreshes.
- [ ] Review whether any meaningful fuzz target now exists; do not add token fuzzing solely for a score.

## Deliberately deferred controls

- **Enforced pull-request approvals:** a second collaborator has been added, but required approvals and Code Owner approval remain disabled at the maintainer's request. The active ruleset requires a pull request, resolved threads, and the `lint` and `image` checks and prevents deletion and force pushes. Revisit approval enforcement after the first release; do not enable it as part of unrelated automation.
- **Two independent approvals:** this requires at least three regularly available maintainers to avoid deadlocking a contributor's own pull request. Reassess when the contributor pool supports it.
- **Fuzzing:** there is currently no credible parser or executable fuzz target owned by this packaging repository.

## First-release runbook

1. Open a release pull request that completes every blocker above and contains the final changelog entry.
2. Record the final CI, CodeQL, and Scorecard workflow URLs in the pull request.
3. Obtain human review from the second collaborator and merge without bypassing checks.
4. Create and push the annotated release tag from the reviewed `main` commit.
5. Watch the release workflow through build, both scanners, signing, and GitHub release creation.
6. Pull the published digest on both architectures, run a query, and verify the signature and attached evidence.
7. Publish release notes that call out known limitations and accepted security findings, if any.

## After the first release

- [ ] Automate a recurring rebuild policy for unchanged ClickHouse versions when UBI security updates arrive.
- [ ] Automate a recurring end-to-end OpenShift test with short-lived credentials after the manual first-release qualification establishes a safe baseline.
- [ ] Evaluate reproducible-build variance across GitHub-hosted runners.
- [ ] Add package-consumer and upgrade tests for each supported ClickHouse update path.
- [ ] Review artifact retention after real usage and adjust only with a documented storage/forensics rationale.
