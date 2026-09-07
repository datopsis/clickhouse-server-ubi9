# Endor Labs posture and adoption

Endor Labs is useful here as an independent view of repository posture, GitHub Actions risk, secrets, and the published container. It is not useful to add an unauthenticated or permanently skipped workflow merely to display another check. This repository therefore prepares for Endor Labs and follows the score factors that reflect real quality, but does not add the Endor action until Datopsis has an approved Endor tenant, namespace, data-handling decision, and keyless authorization policy.

## What an Endor score means

Endor Scores evaluate open source packages and their source repositories across security, code quality, activity, and popularity signals. They are not a certification and they are not fully controlled by maintainers. Stars, forks, downloads, outside contributors, project age, and sustained activity must grow organically.

Several legitimate project choices can also affect a score. In particular, Endor lists non-SemVer releases as a possible negative code-quality signal. This project intentionally uses an upstream-derived container version, `v<clickhouse-version>-ubi<ubi-version>-<packaging-revision>`, because it communicates the deployable ClickHouse and UBI inputs. Do not publish misleading SemVer tags, fake releases, empty commits, or artificial activity to optimize a score.

Endor dependency scores primarily help consumers choose third-party packages. This repository has no application package-manager manifest; its main deliverable is a container assembled from ClickHouse archives and UBI packages. Container, GitHub Actions, secrets, and repository-posture analysis are therefore more relevant than a conventional language SCA scan.

## Controls already present

| Endor-relevant signal | Repository evidence |
| --- | --- |
| Tests and consistently passing CI | Runtime smoke suite plus required `lint` and `image` checks on pull requests. |
| Automated maintenance | Dependabot updates GitHub Actions, pre-commit hooks, and hash-locked CI Python tools. Renovate tracks ClickHouse and UBI image inputs. |
| Pinned dependencies | Container bases use digests, ClickHouse uses an exact version and upstream SHA-512 files, Actions and hooks use immutable commit SHAs, and CI Python wheels use hashes. |
| Documentation and operational files | README, contribution guide, security policy, changelog, version policy, CI design, release roadmap, and vulnerability-reporting path. |
| Security analysis | Secret scanning with push protection, CodeQL for Actions, Zizmor, Actionlint, Hadolint, ShellCheck, Trivy, Grype, Syft, and OpenSSF Scorecard. |
| Signed release evidence | The release workflow creates provenance and SBOM attestations, a keyless Cosign signature, and durable release assets. |
| Reviewable development | Protected `main`, pull requests, required CI, CODEOWNERS, and immutable history controls. Required approval remains a deliberate post-first-release decision. |

The controls must exist for users and risk reduction first. A later score increase is supporting evidence, not the acceptance criterion.

## Current integration decision

As of 2026-09-06, no Endor namespace or authorization policy is configured in this repository and no Endor result is available to claim as a baseline. Adding the GitHub Action now would either fail CI, require a long-lived secret, or remain skipped forever. It would also duplicate existing scans without creating an Endor-monitored default-branch baseline.

Do not add `ENDOR_API_CREDENTIALS_KEY` or `ENDOR_API_CREDENTIALS_SECRET` merely to get started. Endor recommends GitHub OIDC keyless authentication for CI. Installing the Endor GitHub App is also an organization-level trust decision because cloud scanning grants the app repository access and sends retained scan metadata to the Endor tenant. Datopsis must review the requested permissions and Endor's data-handling terms before installation.

## Minimal adoption workflow

1. Create or select the Datopsis Endor tenant and namespace. Record the service owner, billing owner, data-retention requirements, and incident contact outside this public repository.
2. Choose one baseline mechanism. Prefer the Endor GitHub App for scheduled RSPM and GitHub Actions monitoring; use a GitHub Actions integration only when CI policy enforcement or container reachability is required. Do not deploy both for identical scans.
3. For an Actions integration, create a keyless authorization policy restricted to this GitHub organization, repository, and intended refs. Pin `endorlabs/github-action`, `endorctl_version`, and `endorctl_checksum`; grant only `contents: read` and `id-token: write`, adding `security-events: write` only for SARIF upload and `pull-requests: write` only if reviewed PR comments are enabled.
4. Run a monitored scan on `main` with `pr: false`. Review every finding and establish policies before making the check required.
5. Add PR scans with `pr: true` and `pr_baseline: main`. Initially warn on new findings. Move a policy to blocking only after the team has confirmed severity, remediation, exceptions, and scanner availability behavior.
6. Enable only distinct coverage. `scan_github_actions` and RSPM complement the existing workflow analysis. Container OS reachability may complement Trivy and Grype after the test image is built. Conventional dependency reachability and SAST should remain off unless the repository gains a supported application language or package manifest.
7. Review Endor results alongside, not instead of, Trivy, Grype, CodeQL, Zizmor, and Scorecard. Record accepted risks with an owner, rationale, compensating control, and expiry.

The initial Endor check should not be a required merge check until a successful `main` baseline and at least one successful PR scan prove the authentication and policy behavior. If the service is unavailable, the documented policy must say whether that is a hard failure; do not silently convert a security gate to `continue-on-error`.

## Sustainable score improvement

- Merge real changes through pull requests and keep CI reliable.
- Sign commits where practical and publish signed, verifiable container releases when the release gates are complete.
- Maintain accurate repository topics, issue/PR labels, issue templates, license metadata, and security documentation.
- Keep dependencies current and resolve or explicitly triage findings.
- Respond to and close issues with clear release linkage.
- Revisit the score after releases and normal project history accumulate; do not expect a new repository's activity or popularity categories to be high.

For each review, capture the Endor project/version, scan time, policy version, finding counts by severity and category, new-versus-baseline findings, ignored findings and expiry, and the reviewer. A green check is insufficient if the scan skipped a category, used the wrong baseline, or ignored findings.

Authoritative references:

- [Endor Scores](https://docs.endorlabs.com/scan/sca/scores)
- [Repository code-quality score factors](https://docs.endorlabs.com/scan/sca/scores/repository-scores/code-quality-score-factors/)
- [Repository activity score factors](https://docs.endorlabs.com/scan/sca/scores/repository-scores/activity-score-factors)
- [Repository popularity score factors](https://docs.endorlabs.com/scan/sca/scores/repository-scores/popularity-score-factors)
- [Scanning with GitHub Actions](https://docs.endorlabs.com/setup-deployment/ci-cd/scan-with-github-actions)
- [GitHub App deployment](https://docs.endorlabs.com/setup-deployment/scm-integrations/github-app)
- [Endor trust and data handling](https://docs.endorlabs.com/trust-compliance)
