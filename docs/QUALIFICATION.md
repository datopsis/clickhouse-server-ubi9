# Release qualification evidence

This file records durable links and concise results for first-release gates. Downloadable GitHub Actions artifacts expire according to [CI retention policy](CI.md#artifacts-and-retention); the workflow and job logs remain the review record after artifact expiry. Results apply only to the identified commit, image inputs, scanner databases, architecture, and runtime.

## Native AMD64 and ARM64 CI — 2026-09-07

- Pull request: [#5](https://github.com/datopsis/clickhouse-ubi/pull/5)
- Head commit: `2e2b07045990c31acbab32c59f53e2979efbedd5`
- Pull-request merge commit tested by CI: `523ae3754ef8aa81bd8a3f765ec2591dcb8f2182`
- Workflow: [CI run 34125673268](https://github.com/datopsis/clickhouse-ubi/actions/runs/34125673268)
- Aggregate `image` gate: passed after both native jobs completed.

| Evidence | AMD64 | ARM64 |
| --- | --- | --- |
| Native job | [image (amd64)](https://github.com/datopsis/clickhouse-ubi/actions/runs/34125673268/job/101753657567) | [image (arm64)](https://github.com/datopsis/clickhouse-ubi/actions/runs/34125673268/job/101753657581) |
| Runner architecture | `x86_64` | `aarch64` |
| Loaded image architecture | `amd64` | `arm64` |
| ClickHouse smoke result | 26.8.2.7 passed | 26.8.2.7 passed |
| Trivy image inventory | Red Hat 9.8, 32 packages | Red Hat 9.8, 32 packages |
| Trivy fixed High/Critical gate | 0 findings | 0 findings |
| Augmented SPDX/Grype inventory | 37 packages | 37 packages |
| Blocking Grype result | Passed; all 24 matches were excluded by the fixed High/Critical gate | Passed; all 24 matches were excluded by the fixed High/Critical gate |
| Full Grype inventory | Retained; 24 unfixed matches require release triage | Retained; 24 unfixed matches require release triage |
| Security artifact | [AMD64 artifact 10020245728](https://github.com/datopsis/clickhouse-ubi/actions/runs/34125673268/artifacts/10020245728) | [ARM64 artifact 10020200009](https://github.com/datopsis/clickhouse-ubi/actions/runs/34125673268/artifacts/10020200009) |

This is successful architecture and fixed-vulnerability-gate evidence, not acceptance of the 24 unfixed Grype matches. Those findings remain subject to the documented release triage, ownership, compensating-control, and expiry process.

## Podman runtime — 2026-09-07

The complete smoke suite passed locally for ClickHouse 26.8.2.7 using Podman client 5.3.2 on Windows AMD64 and Podman server 5.3.1 on Linux AMD64 in Podman Machine. This establishes the current Podman 5.3 support baseline. It does not replace native Linux ARM64 Podman evidence or target-platform OpenShift qualification.
