# First-release roadmap

This roadmap is the release gate for the first supported image. A checked item must have reviewable evidence in a pull request, successful workflow run, release asset, or linked issue. Items marked **deferred** are deliberate non-blockers and must not silently become release requirements.

## Release blockers

### Image behavior and compatibility

- [ ] Run the complete smoke suite on the final ClickHouse and UBI digests.
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

### Release mechanics and documentation

- [ ] Choose the first tag using `v<clickhouse-version>-ubi<ubi-version>-<packaging-revision>`.
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

- **Enforced pull-request reviews:** a second collaborator has been added, but required reviews, Code Owner approval, and two-approval enforcement remain disabled at the maintainer's request. The active ruleset must continue to prevent deletion and force pushes. Revisit this after the first release; do not enable it as part of unrelated automation.
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
- [ ] Add an end-to-end OpenShift test when a safe test cluster and short-lived credentials are available.
- [ ] Evaluate reproducible-build variance across GitHub-hosted runners.
- [ ] Add package-consumer and upgrade tests for each supported ClickHouse update path.
- [ ] Review artifact retention after real usage and adjust only with a documented storage/forensics rationale.

