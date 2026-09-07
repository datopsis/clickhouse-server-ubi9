## Summary

Describe the user-facing or operational outcome and why the change is needed.

## Validation

- [ ] I ran the relevant local checks from `docs/CI.md`.
- [ ] I reviewed CI logs, warnings, annotations, skipped steps, and retained security evidence rather than relying only on green status checks.
- [ ] I added or updated tests for behavior changes.
- [ ] I updated user and operator documentation where needed.
- [ ] I added a `CHANGELOG.md` entry when the change is notable to users or security reviewers.
- [ ] I did not weaken an image, workflow, or release control without documenting the threat, rationale, compensating control, owner, and expiry.

## Security and release impact

State whether this changes image contents or runtime behavior. If it does, identify the required packaging-revision action under `docs/VERSION.md`. List accepted scanner findings or write `None`.
