# First-release roadmap

This roadmap is the release gate for the first supported
`clickhouse-server-ubi9` image. Work is organized in small, reviewable packages
whose order follows technical dependencies. Evidence is expected to be
regenerated as the candidate changes; preserving an older artifact must never
delay a necessary implementation or security change.

A checked item requires reviewable evidence in a pull request, workflow run,
release asset, or linked qualification record. A passing job is not sufficient
when the item also requires human analysis, an external environment, or a
support decision.

## Evidence lifecycle

The repository uses three evidence levels:

1. **Development evidence** is produced for pull requests. It proves the
   proposed revision was tested but does not qualify a release.
2. **Integration evidence** is produced from `main`. It detects differences in
   merge context and maintains recurring security visibility.
3. **Release-candidate evidence** is regenerated after the final
   image-affecting change and is bound to the exact candidate commit, image
   digest, architecture, configuration profile, scanner inputs, and relevant
   platform versions. Only this level closes final release gates.

Changing ClickHouse, either UBI digest, image contents, entrypoint behavior,
security configuration, scanner content, tailoring, or a qualification
procedure invalidates the affected release-candidate evidence. Regenerate it
without treating the earlier run as wasted work. Historical results remain
useful for comparison and regression analysis.

Maintain a release evidence ledger in [QUALIFICATION.md](QUALIFICATION.md).
Each retained result must record its workflow or procedure, commit, image
digest where available, architecture, inputs, result, and whether it is
development, integration, or release-candidate evidence.

## Working first-release boundary

These positions keep claims narrower than the available evidence. Package 1
must explicitly approve or revise them before later qualification work is
treated as release evidence.

| Area | Working v1 position |
| --- | --- |
| Architectures | Support native `linux/amd64` and `linux/arm64`. |
| Primary runtime | Support a qualified Podman 5.3-or-newer baseline on an exact documented Red Hat host/runtime combination. |
| Docker | Retain GitHub Actions compatibility evidence; do not imply the same production-support commitment as Podman without separate qualification. |
| OpenShift | Provide restricted-SCC fixtures and procedures. Claim support only if an exact OpenShift release is qualified; otherwise label it preview/unqualified. |
| Disconnected operation | Provide and automate the isolated procedure. Claim representative-boundary qualification only if that external rehearsal occurs. |
| FIPS | Do not claim FIPS 140-3 validation for the upstream static ClickHouse artifact. |
| STIG and SCAP | Do not claim STIG certification. Report only the selected image-filesystem checks and their exact evidence boundary. |
| Security controls | Publish component evidence consumable by a cyber team, not a completed SCTM, SSP, authorization, or assessor decision. |
| Registry | Publish the first release to GHCR. Reconsider Docker Hub after demonstrated consumer demand. |
| Paid services | Do not require Endor Labs, FOSSA, or another paid account for v1. Reconsider only when it adds material coverage. |

## Release packages

Complete packages in order unless a later item is purely preparatory and
cannot affect an earlier decision. Each package should normally be a separate
pull request. Packages 2 through 5 may change the image or configuration, so
the final upstream baseline is intentionally selected in package 6 rather
than at the beginning.

### 1. Release contract, roadmap, and badges

**Scope**

- [x] Reorganize the release roadmap around dependency-ordered work packages
  and make evidence regeneration an explicit part of the process.
- [ ] Review and approve the working v1 boundary above, including the exact
  treatment of Docker, OpenShift, disconnected operation, FIPS, and SCAP.
- [ ] Reconcile [SUPPORT.md](SUPPORT.md), [README.md](../README.md), and all
  operator guides with the approved boundary.
- [ ] Add only evidence-backed badges. Evaluate an OpenSSF Best Practices
  badge, native AMD64/ARM64 qualification, the tested Podman floor, and GHCR
  publication. Do not add Codecov, Go Reference, OCI Distribution
  conformance, FOSSA, compliance, or vulnerability-free badges without an
  applicable implementation and inspectable evidence.
- [ ] Register the project with OpenSSF Best Practices when the required
  project metadata is complete. Display its badge only after a real project
  record exists, and preserve the badge's actual status rather than implying
  certification.
- [ ] Update [BADGING.md](BADGING.md) with each approved badge's source,
  destination, evidence, owner, and removal condition.

**Exit evidence**

- [ ] A reviewed support/claim matrix contains no ambiguous release blocker,
  and every badge links to current inspectable evidence rather than a general
  quality claim.

### 2. Threat model and authoritative source provenance

**Threat model**

- [ ] Document build-input, CI, registry, runtime identity, storage,
  ingress/egress TLS, secret, logging, scanner, and release-publication threats.
- [ ] Identify trust boundaries and responsibilities for this image,
  `clickhouse-production-stack`, the container runtime/platform, and the
  operating organization.
- [ ] Map existing mitigations and open risks without promoting them to formal
  control implementations before source analysis.

**Source register**

- [ ] Follow [SECURITY-CONTROLS.md](SECURITY-CONTROLS.md) and create
  `security/stig-sources.yaml`.
- [ ] Acquire authoritative copies of the current DISA Database SRG, Container
  Platform SRG, RHEL 9 STIG, and selected active database-product STIGs.
- [ ] Record publisher, title, version/release, release date, URL, retrieval
  date, SHA-256, license/redistribution handling, and current/superseded status.
- [ ] Pin the NIST SP 800-53 Rev. 5, SP 800-53A Rev. 5, and OSCAL schema/tool
  versions used by the project.

**Exit evidence**

- [ ] Security-focused review confirms that sources came from their publishers,
  all hashes reproduce, and no superseded source is silently normative.

### 3. Database security requirement analysis

This package analyzes requirements; it does not implement fixes in the same
pull request.

- [ ] Create `security/stig-analysis.csv` with source IDs, CCI/NIST mappings,
  severity, objective, threat, ClickHouse relevance, disposition, ownership,
  feasibility, conflicts, residual risk, rationale, procedure, evidence, and
  review metadata.
- [ ] Analyze every Database SRG requirement against ClickHouse behavior and
  the image/deployment boundary.
- [ ] Compare active MongoDB, PostgreSQL-distribution, Oracle Database, Oracle
  MySQL, Microsoft SQL Server, and other selected database STIGs as
  implementation references. Never transfer a product-specific command,
  file, or assumption directly to ClickHouse.
- [ ] Classify every item as `adopt`, `deployment-owned`, `inherited`,
  `not-applicable`, `unsupported`, or `needs-research`.
- [ ] Require two-person review for every adoption, exclusion,
  not-applicable, and unsupported decision. Open an issue for unresolved
  requirements rather than omitting them.

**Exit evidence**

- [ ] Every Database SRG requirement is present exactly once, cross-source
  comparisons are traceable, and the review record explicitly begins with
  zero inherited product-STIG controls.

### 4. Security-control implementation and cyber-team artifacts

**Implementation**

- [ ] Classify adopted requirements as immutable image invariants,
  configurable ClickHouse controls, deployment controls, or
  organizational/inherited controls.
- [ ] Implement only image invariants and reusable ClickHouse configuration in
  this repository. Place production topology and platform controls in
  `clickhouse-production-stack`.
- [ ] For each safely configurable control, provide secure and compatibility
  fragments with exact enable/disable steps, default, prerequisites, restart
  behavior, operational impact, loss of protection, and verification.
- [ ] Do not provide an off switch for trust-boundary invariants merely for
  convenience, and do not let entrypoint variables silently override mounted
  control configuration.
- [ ] Add positive and negative AMD64/ARM64 tests that accurately distinguish
  enabled, disabled, weakened, unsupported, and deployment-owned behavior.

**Control artifacts**

- [ ] Publish a schema-valid `security/component-definition.json` NIST OSCAL
  Component Definition as the canonical component artifact.
- [ ] Deterministically generate `security/control-matrix.csv` for SCTM import
  and fail CI when the generated view drifts.
- [ ] Add `docs/CONTROL-IMPLEMENTATION.md` with per-control justification,
  residual risk, and complete examine/test/interview procedures based on NIST
  SP 800-53A.
- [ ] Validate OSCAL identifiers, links, profiles, and schema using a pinned
  toolchain.

**Exit evidence**

- [ ] The consuming cyber team confirms that the artifacts are usable component
  inputs and not a completed system SCTM, SSP, authorization, STIG
  certification, or acceptance of residual risk.

### 5. Cryptographic boundary, runtime support, and architecture review

**Cryptography**

- [ ] Adopt the determination in [FIPS.md](FIPS.md): the upstream static
  ClickHouse artifact is not claimed as FIPS 140-3 validated.
- [ ] Record binary linkage, embedded cryptographic implementation/version,
  and the absence or applicability of a CMVP certificate for the selected
  ClickHouse build.
- [ ] Test supported TLS 1.2/1.3 protocols and cipher behavior on AMD64 and
  ARM64. Keep TLS 1.0/1.1 outside supported profiles and never equate protocol
  negotiation with FIPS validation.

**Support and diagrams**

- [ ] Qualify and record the exact RHEL release, kernel, Podman client/server,
  OCI runtime, SELinux state, cgroup version, and native architecture baseline.
- [ ] Define the supported ClickHouse channel, image update cadence,
  vulnerability-response target, upgrade expectations, and end-of-support
  policy. Keep these commitments consistent in `SUPPORT.md` and release notes.
- [ ] Repeat the documented comparison with the matching official ClickHouse
  image, including entrypoint behavior, ports, environment variables,
  configured storage discovery, packages, scripts, layers, compressed and
  unpacked size, and the consequences of starting non-root.
- [ ] Review every SVG in [ARCHITECTURE.md](ARCHITECTURE.md) against the current
  image and approved release boundary.
- [ ] Keep deployment-specific topology in `clickhouse-production-stack` while
  retaining image-specific ports, identities, storage, trust, and control
  boundaries here.
- [ ] Add CI checks for SVG/XML well-formedness, internal links, accessible
  title/description elements, prohibited scripts/external resources, and
  documented diagram-to-configuration consistency.

**Exit evidence**

- [ ] A reviewer can determine exactly which cryptographic module, host/runtime
  versions, architectures, and deployment claims are supported or excluded.

### 6. Final upstream baseline, vulnerabilities, and licensing

Perform this after packages 2 through 5 because their decisions may change
the image.

- [ ] Select the final ClickHouse stable release/channel and review its release
  notes and published SHA-512 files.
- [ ] Select current compatible UBI Minimal and UBI Micro manifest-list
  digests together and confirm both resolve for AMD64 and ARM64.
- [ ] Rebuild both architectures from scratch and compare image size, layers,
  packages, SBOMs, permissions, and scanner results with the prior baseline.
  Explicitly investigate unexpected additions/removals, setuid/setgid files,
  and world-writable paths.
- [ ] Define and exercise the UBI-triggered rebuild process and its response
  target so a base-image security update can be released without waiting for a
  new ClickHouse version.
- [ ] Triage every Trivy/Grype finding using
  [VULNERABILITY-MANAGEMENT.md](VULNERABILITY-MANAGEMENT.md). Record advisory,
  affected component, architecture, fix availability, reachability,
  compensating control, owner, decision, and review expiry.
- [ ] Resolve or explicitly triage dependency-update pull requests and scanner
  disagreements.
- [ ] Inspect both SPDX inventories and embedded license/notice files; complete
  [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and the ClickHouse/Red Hat
  redistribution and trademark review.
- [ ] Confirm the runtime remains non-root, capability-free,
  package-manager-free, downloader-free, and read-only-root compatible.
- [ ] Review workflow permissions, immutable action references, secret
  scanning, CodeQL, and Scorecard results for the exact candidate. Confirm the
  `SECURITY.md` contact is monitored and test the private vulnerability-report
  path without creating a real vulnerability report.

**Exit evidence**

- [ ] The release pull request identifies the final upstream versions/digests,
  before/after evidence, accepted risks, license review, and reason no newer
  reviewed input is being selected.

### 7. Exact release-candidate qualification

All tests in this package target one immutable candidate commit and image
digest. Any subsequent image-affecting change returns the project to package 6
and regenerates affected evidence.

**Native and runtime behavior**

- [x] CI has native AMD64 and ARM64 build/test jobs and a protected aggregate
  gate. Existing results are development/integration evidence until rerun for
  the final candidate.
- [x] Rootless storage behavior, configuration-derived primary/additional
  paths, arbitrary UIDs, initialization, persistence, negative permissions,
  read-only roots, and capability-free operation have automated tests and
  user procedures.
- [ ] Retain final-candidate successful and intentional-failure logs for every
  identity, storage, initialization, shutdown, and recovery case.
- [ ] Run the complete suite with the approved Podman host/runtime baseline and
  separately retain native Docker-based GitHub Actions evidence.

**TLS and disconnected behavior**

- [x] Native CI generates an ephemeral CA chain and tests HTTPS/native TLS,
  hostname and trust failures, clear-text rejection, key/chain permissions,
  outbound public/private trust, rotation, rollback, and network isolation.
- [x] [TLS-REHEARSAL.md](TLS-REHEARSAL.md) documents connected and disconnected
  operator procedures without committing generated key material.
- [ ] Retain final-candidate sanitized subjects, issuers, SANs, serials,
  expiries, isolation proof, positive/negative results, rotation, rollback,
  and confirmation that no secret entered Git or public evidence.
- [ ] If a representative disconnected boundary is available, execute the
  operator rehearsal there. Otherwise record the limitation required by the
  working support boundary.

**OpenShift decision gate**

- [x] Restricted-SCC fixtures, policy tests, arbitrary-UID guidance, TLS/PVC
  resources, diagnostics, and cleanup procedures exist in
  [OPENSHIFT-TESTING.md](OPENSHIFT-TESTING.md).
- [ ] If an OpenShift environment is available, qualify an exact release under
  the default restricted SCC without root, `anyuid`, host paths, added
  capabilities, or privileged mode. Exercise initialization, TLS, probes,
  graceful deletion, PVC persistence, backup/restore, and failure diagnostics.
- [ ] If OpenShift is unavailable, run the restricted Kubernetes proxy test and
  explicitly mark OpenShift preview/unqualified. A proxy test must not be
  described as OpenShift qualification.

**SCAP stabilization**

- [x] The pinned OpenSCAP/ComplianceAsCode tool, isolated exported-filesystem
  scan, 36-rule tailored profile, rule rationale, hashes, complete evidence,
  and operational-error gate are implemented on both architectures.
- [ ] Evaluate the exact final candidate at least three independent times on
  native AMD64 and ARM64 using `main`, schedule, or intentional manual
  dispatch. Record image/profile/content hashes and require identical selected
  rule inventories; do not manufacture source changes merely to trigger runs.
- [ ] Cross-check the exact digest with `oscap-podman` on a disposable RHEL 9
  host. If unavailable, keep selected findings report-only and record that
  enforcement qualification remains incomplete.
- [ ] After the comparison and three stable runs, decide in a reviewed pull
  request whether selected-rule failures become release-blocking.

**Production procedure review**

- [ ] Execute [PRODUCTION.md](PRODUCTION.md) against the candidate, including
  resource bounds, storage, health, graceful shutdown, backup/restore,
  upgrade, rollback, and recovery.
- [ ] Review the README and every operator procedure from a clean clone and
  validate all internal links and commands.

**Exit evidence**

- [ ] [QUALIFICATION.md](QUALIFICATION.md) identifies the exact candidate and
  contains every result, external limitation, support consequence, and retained
  artifact needed for the release decision.

### 8. Release rehearsal and signed publication

**Rehearsal**

- [ ] Choose the first tag using [VERSION.md](VERSION.md) and validate it with
  `scripts/validate-release-tag.sh`.
- [ ] Exercise the release workflow with a disposable non-production package or
  explicitly marked prerelease path. Do not present a failed rehearsal as a
  supported release.
- [ ] Verify manifest variants, vulnerability gates, keyless signature, SPDX
  attestation, provenance, downloaded verification, and expected release
  assets. Remove disposable artifacts through the approved GitHub process.
- [ ] Confirm the GHCR package will be public and its description, source,
  documentation, and license metadata are correct.

**Publication**

- [ ] Convert `Unreleased` in [CHANGELOG.md](../CHANGELOG.md) into the selected
  version/date and add a new empty `Unreleased` section.
- [ ] Open the final release pull request containing the evidence ledger,
  support boundary, known limitations, accepted security findings, and final
  changelog.
- [ ] Obtain second-maintainer review and merge without bypassing protected
  checks.
- [ ] Create and push the annotated immutable tag from the reviewed `main`
  commit.
- [ ] Watch the workflow through publication, scanning, signing, attestation,
  and GitHub Release creation.
- [ ] Pull the published digest on both architectures, run a query, and verify
  the signature, provenance, SBOM, manifest, labels, and release assets.
- [ ] Refresh OpenSSF Scorecard after publication and confirm it recognizes the
  signed release and associated supply-chain metadata; record any lag or
  remaining finding without delaying verification of the release itself.
- [ ] Publish release notes that state the support boundary, external
  limitations, and accepted findings without unsupported security claims.

**Exit evidence**

- [ ] The public GHCR digest, GitHub Release, signature bundle,
  `image.spdx.json`, and `image.intoto.jsonl` all identify the same reviewed
  release.

## External-environment decisions

Lack of an external environment must produce a documented support decision,
not an implied pass and not an indefinite hidden blocker.

| Environment | Preferred evidence | Release fallback |
| --- | --- | --- |
| OpenShift | Exact-version restricted-SCC qualification | Restricted Kubernetes proxy plus explicit OpenShift preview/unqualified status |
| Disconnected security boundary | Full operator rehearsal inside the boundary | Automated isolation evidence plus explicit absence of representative-boundary qualification |
| Disposable RHEL 9 SCAP host | `OSCAP_PROBE_ROOT` versus `oscap-podman` comparison for one digest | Keep tailored SCAP report-only and document incomplete enforcement qualification |
| Cyber-team tooling | Trial import of OSCAL and CSV | Publish schema-valid artifacts but record trial import as pending; do not claim SCTM integration |

## Existing foundation

The following capabilities are implemented and remain subject to final-candidate
reruns rather than reimplementation:

- non-root UID `101:0` and arbitrary-UID operation without an entrypoint root
  phase or volume `chown`;
- configuration-derived primary and additional storage paths with actionable
  permission failures;
- read-only-root, dropped-capability, initialization, authentication,
  persistence, and graceful-shutdown smoke coverage;
- native AMD64 and ARM64 CI with architecture-specific images, caches, SBOMs,
  vulnerability evidence, and aggregate branch protection;
- connected/disconnected TLS automation and complete operator procedures;
- OpenShift restricted-SCC fixtures, policy tests, and operator instructions;
- isolated tailored SCAP evaluation with 36 currently passing image-owned
  rules and documented exclusions;
- Trivy, Syft, Grype, CodeQL, Zizmor, OpenSSF Scorecard, checksum verification,
  immutable action references, BuildKit provenance, and keyless release signing;
- Podman-first user documentation, third-party license boundaries, official
  ClickHouse image comparison, and release versioning rules.

## Deliberately deferred after v1

- Docker Hub publication unless real consumers require it.
- Paid security services unless they add distinct, actionable coverage.
- Required approving-review enforcement until the regularly available
  maintainer pool can satisfy it without deadlocking pull requests. The final
  release still requires an actual second-maintainer review.
- Fuzzing until the repository owns a credible parser or executable fuzz
  target.
- Recurring OpenShift automation until a manual qualification establishes a
  safe credential and cleanup model.
- Reproducible-build variance analysis across hosted runners.

## After the first release

- [ ] Automate rebuild proposals when UBI security updates arrive without a
  ClickHouse version change.
- [ ] Add recurring OpenShift qualification with short-lived credentials after
  the manual baseline exists.
- [ ] Add consumer and upgrade tests for each supported ClickHouse update path.
- [ ] Review evidence-retention periods using actual release and incident
  response experience.
- [ ] Re-run OpenSSF Scorecard and Best Practices review and address findings
  based on security value rather than badge appearance alone.
