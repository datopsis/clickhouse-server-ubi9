# Contributing

Contributions are welcome through GitHub pull requests.

Before submitting a change:

1. Keep runtime additions minimal and explain why each package is required.
2. Pin base images by digest and ClickHouse by its complete release version.
3. Install the hooks with `pre-commit install --install-hooks` and run `pre-commit run --all-files`.
4. Build the image and run `bash tests/smoke.sh`.
5. Document behavior or compatibility changes in `README.md` and notable changes in `CHANGELOG.md`.

Do not weaken the non-root default, checksum verification, vulnerability gate, read-only-root compatibility, dropped-capability baseline, or release signing without an explicit security rationale.

Use Conventional Commit-style subjects where practical, such as `feat:`, `fix:`, `docs:`, `test:`, `build:`, or `chore:`.

Do not add AI attribution or co-author trailers to commits. In particular, `Co-Authored-By: Claude ...` is prohibited and rejected by the commit-message hook.
