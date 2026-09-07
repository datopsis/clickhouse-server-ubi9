# Contributing

Contributions are welcome through GitHub pull requests.

Before submitting a change:

1. Keep runtime additions minimal and explain why each package is required.
2. Pin base images by digest and ClickHouse by its complete release version.
3. Build the image and run `bash tests/smoke.sh`.
4. Run ShellCheck on shell scripts and Hadolint on `Containerfile`.
5. Document behavior or compatibility changes in `README.md`.

Do not weaken the non-root default, checksum verification, vulnerability gate, read-only-root compatibility, dropped-capability baseline, or release signing without an explicit security rationale.

Use Conventional Commit-style subjects where practical, such as `feat:`, `fix:`, `docs:`, `test:`, `build:`, or `chore:`.
