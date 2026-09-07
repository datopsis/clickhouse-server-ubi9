# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases use container-version tags documented in `README.md`.

## [Unreleased]

### Added

- Initial Red Hat UBI 9 Micro packaging for ClickHouse Server.
- Hardened non-root runtime, automated tests, vulnerability scanning, SBOM and provenance generation, and keyless release signing.
- Cross-platform line-ending rules and pre-commit checks for repository hygiene, shell scripts, container files, GitHub Actions, and prohibited commit trailers.
- Immutable GitHub Action references, workflow security auditing, configuration scanning, and expanded runtime smoke coverage.
- OpenSSF Scorecard publishing, CodeQL analysis for GitHub Actions, hash-locked CI tooling, CODEOWNERS, and signed GitHub release evidence.
- Syft SPDX SBOM generation and Grype vulnerability gates for CI and release images, with SARIF and release artifacts retained according to their useful lifecycle.
- First-release roadmap, repository badge policy, and contributor-facing CI and artifact documentation.
