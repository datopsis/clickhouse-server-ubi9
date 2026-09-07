# Versioning and releases

This project versions the published container image independently from the repository's source history. Git commits identify every repository change; release versions identify container artifacts that the project has intentionally published and supports.

## Release version format

Release tags use:

```text
v<clickhouse-version>-ubi<ubi-version>-<packaging-revision>
```

For example, `v26.8.2.7-ubi9.8-1` means:

- ClickHouse `26.8.2.7`;
- Red Hat UBI `9.8`; and
- Datopsis packaging revision `1` for that ClickHouse and UBI combination.

This is an upstream-derived container version, not Semantic Versioning. ClickHouse's four-part version is preserved so operators can immediately identify the packaged server. The final packaging revision is a positive integer and starts at `1` the first time a ClickHouse and UBI version combination is released.

Release tags are immutable. Never move or reuse a release tag, even when rebuilding nominally identical inputs. Production deployments should pin the published image digest; the human-readable release tag describes the release, while the digest identifies its exact content.

## When the version changes

| Change | Version action | Example |
| --- | --- | --- |
| Upgrade or downgrade ClickHouse | Set the new ClickHouse version. Use packaging revision `1` if that exact ClickHouse and UBI pair has never been released; otherwise use its next unused revision. | `v26.8.2.7-ubi9.8-3` to `v26.9.1.4-ubi9.8-1` |
| Change the named UBI release | Set the new UBI version. Use packaging revision `1` if that exact pair is new; otherwise use its next unused revision. | `v26.8.2.7-ubi9.8-2` to `v26.8.2.7-ubi9.9-1` |
| Refresh a UBI digest within the same named UBI release | Increment the packaging revision. | `v26.8.2.7-ubi9.8-1` to `v26.8.2.7-ubi9.8-2` |
| Change image contents, runtime behavior, configuration, entrypoint logic, build inputs, or release metadata without changing the ClickHouse or named UBI versions | Increment the packaging revision. | `v26.8.2.7-ubi9.8-2` to `v26.8.2.7-ubi9.8-3` |
| Change only documentation, tests, development tooling, issue templates, or analysis workflows without publishing a new image | Do not create or change a container release version. | Record the change in Git and, when notable, under `Unreleased` in the changelog. |

Every newly published image must receive a new release tag. If maintainers decide that a repository-only change justifies republishing the image, increment the packaging revision even if the expected filesystem contents are unchanged. Normally, repository-only changes should wait for the next image-affecting release.

When several version components change together, set the ClickHouse and UBI fields to the new values and use revision `1` only if that exact pair has never been released. The packaging revision is monotonic within one exact ClickHouse and UBI version pair, including after a temporary upgrade or downgrade away from that pair.

## Repository-only changes and non-image releases

A repository change that does not publish a container is tracked by its pull request and Git commit SHA. It is not part of a supported container release merely because it exists on `main`.

This project does **not** create source-only GitHub Releases or tags for documentation, tests, development tooling, issue templates, or analysis workflows. GitHub Releases represent published container images, so creating another kind of release would make the release feed, version comparison, and support status ambiguous. Users who need an unreleased repository file should pin its full commit SHA.

Use the following identifiers:

- a full Git commit SHA for an exact source revision;
- `git describe --tags --always --dirty` for a convenient local description; and
- the `Unreleased` section of `CHANGELOG.md` for notable changes intended for the next container release.

Commits after a release tag do not alter the already-published image or tag. A clean checkout of a tag identifies released source; a later commit identifies unreleased repository state until another release is tagged.

Not every repository-only change needs a changelog entry. Add one when users, operators, contributors, or security reviewers would reasonably want to discover it. Keep the entry under `Unreleased` in the appropriate Keep a Changelog category (`Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, or `Security`). When the next image is released, move all accumulated entries into `## [<release-tag>] - YYYY-MM-DD`, including notable repository-only work. The section describes repository changes since the prior image release; it does not imply that every entry changed the image filesystem.

## Release procedure

1. Update the ClickHouse version, UBI references, and packaging code as needed.
2. Choose the release version using the rules above, convert the changelog's `Unreleased` entries into `## [<release-tag>] - YYYY-MM-DD`, and add a new empty `Unreleased` section.
3. Complete the release gates in [ROADMAP.md](ROADMAP.md), then merge the release change to `main` after CI and review pass.
4. Run `bash scripts/validate-release-tag.sh <release-tag>`, create an annotated tag using that version from the reviewed `main` commit, and push it.
5. Let the tag-triggered release workflow build, scan, sign, and publish the image and GitHub release. Do not create a source-only GitHub release manually.
6. Verify the published digest, signature, provenance, SBOM, image labels, and release assets before announcing support.

The release workflow also creates a `sha-<short-commit>` image tag for traceability. It is supplementary and does not replace the release tag or immutable digest.
