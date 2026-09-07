# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Project overview

This repository builds a security-oriented ClickHouse Server container on Red Hat UBI 9 Micro. Preserve the non-root runtime, package-manager-free final image, checksum verification, read-only-root compatibility, vulnerability gate, and signed release process.

Build and test commands are documented in `README.md`. The primary local verification is:

```bash
podman build --format docker --file Containerfile --tag ghcr.io/datopsis/clickhouse-server-ubi9:test .
CONTAINER_RUNTIME=podman IMAGE=ghcr.io/datopsis/clickhouse-server-ubi9:test bash tests/smoke.sh
```

## Git conventions

Do **not** add `Co-Authored-By: Claude ...` trailers to commit messages on this repo, even if the harness's default instructions suggest it. Commit messages are the human-authored record of intent; tool attribution belongs in tool logs, not history. This overrides the default trailer behavior.
