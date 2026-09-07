# Continuous integration and release automation

This repository treats the built image as the primary deliverable. CI therefore checks repository quality, builds and exercises the container, inventories its contents, and applies two independent vulnerability scanners before release.

## Workflow map

| Workflow | Triggers | Purpose |
| --- | --- | --- |
| `CI` | Pull requests, pushes to `main`, weekly schedule, manual dispatch | Lint, workflow audit, configuration scan, image build, smoke tests, Trivy scan, Syft SBOM, and Grype scan. |
| `CodeQL` | Workflow changes, weekly schedule, manual dispatch | Static analysis of GitHub Actions with the security-extended query suite. |
| `OpenSSF Scorecard` | Pushes to `main`, ruleset changes, weekly schedule, manual dispatch | Supply-chain posture analysis, SARIF upload, and public Scorecard publication. |
| `Release image` | Tags matching `v*` | Multi-architecture publish, digest scans, evidence generation, keyless signing, and GitHub release creation. |

Workflow-level permissions default to read-only. Write scopes are applied only to jobs that publish code-scanning results, packages, attestations, signatures, or releases. Third-party actions are pinned to full commit SHAs and tracked by Dependabot.

## Image security pipeline

The image job runs these controls in order:

1. **Trivy configuration scan** checks the `Containerfile`, Compose configuration, and repository infrastructure configuration for high and critical misconfigurations.
2. **Build and smoke tests** exercise startup, authentication, initialization, persistence, shutdown, read-only operation, dropped capabilities, and arbitrary UIDs.
3. **Trivy image scan** blocks fixed high and critical operating-system or application vulnerabilities.
4. **Syft inventory** generates `clickhouse-server-ubi9.spdx.json` in SPDX JSON format from the tested image.
5. **Grype SBOM scan** scans that exact SPDX document and blocks fixed high and critical vulnerabilities.
6. **Artifact and SARIF publication** retains the inventory and result for investigation and publishes non-PR Grype results to GitHub code scanning.

Trivy and Grype deliberately overlap. They use different databases and matching logic, so a clean result from one does not replace the other. Both gates ignore vulnerabilities without an upstream fix; unfixed findings still require periodic review before release. Scanner disagreements should be investigated against the vendor advisory and documented if accepted.

## Artifacts and retention

| Artifact | Location | Retention or lifecycle | Purpose |
| --- | --- | --- | --- |
| `clickhouse-server-ubi9.spdx.json` | CI artifact `image-security-<commit>` | 14 days | Package inventory for the exact tested image. |
| `grype.sarif` | Same CI artifact and GitHub code scanning on non-PR runs | 14 days for the downloadable artifact | Machine-readable findings and review evidence. |
| `image.spdx.json` | Tag-run artifact and GitHub release asset | 30-day Actions copy; release asset retained with the release | Downloadable inventory for the published digest. |
| Release `grype.sarif` | Tag-run artifact and GitHub code scanning | 30 days for the downloadable artifact | Point-in-time scan evidence; not attached to the release because vulnerability data ages rapidly. |
| BuildKit SBOM and provenance | OCI registry attestations; downloaded together as `image.intoto.jsonl` | Lifetime of the package/release | Registry-native inventory and build provenance. |
| `image.sigstore.json` | GitHub release asset | Lifetime of the release | Offline verification bundle for the keyless image signature. |
| Scorecard SARIF | Scorecard workflow artifact and code scanning | 5 days for the workflow artifact | Supply-chain control findings. |

Upload steps use `always()` so useful evidence survives a vulnerability gate failure. A failed gate still prevents signing and release creation. Never place credentials, mounted secrets, or environment dumps in an uploaded artifact.

## Reproducing checks locally

Run the same repository checks and build first:

```console
pre-commit run --all-files --show-diff-on-failure
docker build --file Containerfile --tag clickhouse-server-ubi9:test .
IMAGE=clickhouse-server-ubi9:test bash tests/smoke.sh
```

With Trivy, Syft 1.51.1, and Grype 0.118.0 installed from their official release instructions:

```console
trivy config --severity HIGH,CRITICAL --exit-code 1 .
trivy image --ignore-unfixed --severity HIGH,CRITICAL --exit-code 1 \
  clickhouse-server-ubi9:test
syft clickhouse-server-ubi9:test --output spdx-json=clickhouse-server-ubi9.spdx.json
grype sbom:clickhouse-server-ubi9.spdx.json \
  --only-fixed --fail-on high --output table
```

The vulnerability databases are time-dependent, so a local result can differ from an earlier workflow. Record the database update time and scanner version when investigating a discrepancy. Do not commit generated SBOM or SARIF files; CI and releases are their authoritative storage locations.

## Contributor expectations

- Run pre-commit and the smoke suite before opening a pull request that affects the image or entrypoint.
- Inspect annotations and downloadable SARIF instead of rerunning a failed job until it happens to pass.
- For a true positive, update the affected base image, package, or ClickHouse version and rerun both scanners.
- For a suspected false positive, verify the package version and Red Hat/ClickHouse advisory, then open a narrowly scoped issue. Suppressions require a documented expiry and maintainer review; no blanket ignore file is currently accepted.
- Update the explicit Syft and Grype engine versions together with their action references when reviewing dependency updates.
- Never merge a scanner bypass solely to meet a release date.

## Release behavior

The release workflow builds and pushes a multi-architecture manifest before scanners run because both architectures must be addressed by the immutable registry digest. If a post-push scan fails, the workflow does not sign or create a GitHub release, but the registry may contain the non-release tag and digest. Maintainers must investigate and remove or clearly quarantine such failed candidates through the GHCR interface.

After both scans pass, the workflow signs the digest through GitHub OIDC, downloads its attestations, and creates a GitHub release containing the SPDX SBOM, Sigstore bundle, and in-toto evidence. Follow the final checklist in [ROADMAP.md](ROADMAP.md) for the first release.

Authoritative references:

- [Anchore SBOM Action](https://github.com/anchore/sbom-action)
- [Anchore Scan Action](https://github.com/anchore/scan-action)
- [Syft documentation](https://github.com/anchore/syft/wiki)
- [Grype documentation](https://github.com/anchore/grype)
- [Trivy documentation](https://trivy.dev/latest/docs/)
- [GitHub artifact storage](https://docs.github.com/en/actions/using-workflows/storing-workflow-data-as-artifacts)
- [Uploading SARIF to GitHub](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/uploading-a-sarif-file-to-github)
- [BuildKit attestations](https://docs.docker.com/build/metadata/attestations/)
- [Cosign container signing](https://docs.sigstore.dev/cosign/signing/signing_with_containers/)
