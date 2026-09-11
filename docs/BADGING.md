# Repository badges

Badges are compact links to evidence, not security claims. The README uses only badges that are maintained by GitHub, OpenSSF, Shields.io, or a factual static project label. A badge must link to the page where a contributor can inspect the underlying result.

## Badge inventory

| Badge | Evidence and destination | Maintenance |
| --- | --- | --- |
| CI | Status of `.github/workflows/ci.yml` on `main`; links to its workflow runs. | GitHub updates it after each run. |
| CodeQL | Status of `.github/workflows/codeql.yml` on `main`; links to its workflow runs. | GitHub updates it after each run. |
| OpenSSF Scorecard | Public Scorecard result for this repository; links to the detailed viewer. | The weekly/push workflow publishes results; the public cache may lag. |
| Latest release | Highest semantic GitHub release; links to the releases page. | It reports no release until the first tag workflow succeeds. |
| License | Repository-detected license; links to `LICENSE`. | GitHub/Shields derives it from repository content. |
| UBI 9 | Factual base-family label; links to Red Hat's UBI documentation. | Update manually only if the runtime base family changes. |
| SPDX SBOM | Factual statement that CI produces SPDX JSON; links to `CI.md`. | Keep only while CI and releases produce the documented artifact. |

The CI and CodeQL badges are scoped to `branch=main`; a green badge therefore describes the default branch, not an unmerged pull request. Scanner findings are represented through CI rather than a separate “secure” badge because a vulnerability database and image contents change over time.

## Source markup

The canonical badge markup lives at the top of `README.md`. When changing it:

1. use HTTPS for both the image and destination;
2. link workflow badges to the workflow page, not to a single run;
3. keep repository coordinates explicit as `datopsis/clickhouse-ubi`;
4. URL-encode static badge labels and values;
5. preview links while signed out so badges do not depend on private credentials; and
6. update this inventory in the same pull request.

Do not add download counts, stars, “production ready,” vulnerability-free, compliance, coverage, or passing badges without stable machine-verifiable evidence. Do not expose tokens through custom badge endpoints. An OpenSSF score is a point-in-time measurement and must not be restated as certification.

## Troubleshooting

- A workflow badge can remain stale briefly because of CDN caching. Open the linked workflow before treating it as a current result.
- The release badge will show that no release exists until the tag workflow creates the first GitHub release.
- If the license badge is unknown, confirm that the root `LICENSE` remains recognizable as Apache-2.0.
- If the Scorecard badge is missing or stale, inspect the `OpenSSF Scorecard` workflow and its public publishing step before editing the badge URL.

References:

- [GitHub workflow status badges](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge)
- [OpenSSF Scorecard badge](https://github.com/ossf/scorecard-action#scorecard-badge)
- [Shields.io GitHub badges](https://shields.io/badges)
- [Red Hat Universal Base Images](https://developers.redhat.com/products/rhel/ubi)
