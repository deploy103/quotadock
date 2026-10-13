# Contributing to QuotaDock

Thanks for helping make quota visibility reliable and honest. This is a source
preview; small, well-tested changes are easiest to review.

## Before coding

Read [README](README.md), [the snapshot contract](docs/contract.md), and
[SECURITY](SECURITY.md). Search existing issues first. Open an issue for changes
to the wire format, provider semantics, pairing, or platform requirements.
Use demo/synthetic data for reports. Be respectful, specific, and constructive.

## Local checks

- Node.js 22: `npm test` from the repository root. No npm runtime dependencies
  or install step are required for the bridge.
- Skill resources: `python3 .agents/skills/checking-codexbar-usage/scripts/test_codexbar.py`.
- Apple: Mac, Xcode 16+, XcodeGen. Generate from `apple/project.yml`; build and
  test its actual schemes in an iOS 17+ simulator. Device signing stays local.
- Verify dashboard/demo labels and stale/unknown/error states; a screenshot
  must use demo data, not an account or pairing token.

## Pull requests

Describe the problem, scope, user-visible effect, and exact checks performed.
Add regression tests at public boundaries. Preserve null versus zero, remaining
versus used percentages, and provider-specific window semantics. Do not add
credentials, raw provider output, signing files, or generated build products.

Keep CI least-privileged and pin third-party actions to full commit SHAs.
Workflow changes must not run untrusted pull-request code with secrets. This
repository intentionally does **not** use CodeRabbit.

## Agent skills and imported code

Skills live under `.agents/skills/`; no global installation is needed. Name and
directory must match and use gerund names. Review every imported script before
execution, preserve resource layout, and record exact revision/license in
THIRD_PARTY_NOTICES.md. Do not silently update pinned upstream resources.
Read-only inspection must not become credential repair or deployment automation.

By submitting a contribution, you agree it may be distributed under the project's
MIT license. Third-party contributions must retain their original notices.
