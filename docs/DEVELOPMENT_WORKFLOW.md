# DailySpend development workflow

This setup uses GitHub's standard hosted runners for a public repository, GitHub issue/PR templates, Xcode, and Python's standard library. No paid service, custom CI secret, Apple account, or third-party telemetry is required.

## Everyday steps

| Step | What you do | Why |
|---|---|---|
| 1. Define | Open a bug or feature issue; write acceptance criteria using fictional examples. | Agree on the expected result before coding. |
| 2. Branch | Create a short-lived `codex/<topic>` branch from current `main`. | Keep each change separate and reviewable. |
| 3. Implement | Make focused changes and add meaningful relevant tests. | Verify behavior and prevent repeated bugs. |
| 4. Check | Run the safety check and simulator tests locally. | Catch problems before sharing code. |
| 5. Review | Open a PR; fill in tests, screenshots, and upgrade/privacy impact. | Make the change understandable and inspectable. |
| 6. CI | GitHub runs Debug and Release checks for the proposed merge. | Verify the change automatically on a clean machine. |
| 7. Merge | Review the final diff and satisfy the definition of done and required checks. | Keep `main` usable. |
| 8. Release | Run separate quality and data-safety reviews on the actual release candidate. | Protect existing users and verify the signed build. |

See [Definition of Done](DEFINITION_OF_DONE.md), [pre-upload test plan](PRE_UPLOAD_TEST_PLAN.md), and [release checklist](APP_STORE_RELEASE_CHECKLIST.md).

## CI behavior and cost boundary

`.github/workflows/ci.yml` runs on PRs targeting `main`, pushes to `main`, and manual dispatch. There are no path filters that could leave a required PR check pending. New runs cancel older runs for the same PR/ref. Each Debug/Release job has a 40-minute limit.

The baseline is the standard `macos-26` runner with Xcode 26.6 and the newest installed available iOS 26 simulator runtime. The script rejects unexpected Xcode versions and records exact Xcode/build/runtime versions. Hosted images can change; this is an explicit Xcode selection, not a frozen image. Future toolchain changes require a reviewed workflow change.

Standard GitHub-hosted Actions compute is free for public repositories. Larger runners are paid and are not used. Every job is guarded by `repository.private == false`; if the repository becomes private, hosted tests are skipped. Skipped checks are not acceptance evidence even if GitHub displays a successful workflow. Run the local commands instead until a separately reviewed free solution exists. Never make a private repository public just to obtain free CI. See [GitHub billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) and [runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

## Data and credential boundaries

- Use only disposable synthetic records. CI uses a newly created simulator with no Apple-account sign-in; current automated test paths use in-memory stores without CloudKit and suppress shared widget writes.
- Signing is disabled; no provisioning update/download flags are used. CI never uploads to App Store Connect, distributes TestFlight builds, or deploys a cloud schema.
- The workflow requests only `contents: read`, pins the official checkout action to a verified full commit SHA, and sets `persist-credentials: false`. It uses `pull_request`, never privileged PR triggers, and never substitutes issue/PR text into shell commands.
- There are no artifact uploads, external reporting services, or build caches. Raw `.xcresult` bundles and screenshots stay on the ephemeral runner; only counts and environment information enter the summary. Build/test output still appears in public Actions logs, so fixtures and error messages must not contain private data.
- `check_repository_safety.py` rejects common secret signatures and credential/database/backup file types without printing matched contents. It is a bounded check, not proof that every secret or personal detail can be detected; it does not scan Git history. Review files and attachments before publishing.
- Never run untrusted PR code on your personal Mac or a self-hosted runner. Hosted runners isolate it from your personal files, but their outbound networking is not blocked. A changed test/build script can transmit anything accessible to its job; owner review and keeping secrets/data out of CI remain essential.

The public repository was verified on October 8, 2026. Security choices follow [GitHub's secure-use guidance](https://docs.github.com/en/actions/reference/security/secure-use).

## Local commands

Run from the repository root. No packages are installed by these commands. The runner creates and deletes only its own new simulator; it never erases or deletes an existing device. Test results and DerivedData remain in the requested output directory for local inspection.

```bash
python3 scripts/ci/check_repository_safety.py
python3 scripts/ci/run_tests.py --configuration Debug --xcode-version 26.6 --ios-major 26 --output-dir /private/tmp/dailyspend-ci
python3 scripts/ci/run_tests.py --configuration Release --xcode-version 26.6 --ios-major 26 --output-dir /private/tmp/dailyspend-ci
```

If using another installed Xcode, explicitly supply its actual version after reviewing compatibility. For the owner's currently installed Xcode 27.0 with iOS 26 runtimes, substitute `--xcode-version 27.0 --ios-major 26`. The script downloads no runtimes. An iOS 26 simulator test under Xcode 27 does not establish iOS 27 runtime coverage.

Release excludes only `testDebugDemoDataMakesDashboardAndInsightsTestable`, which exercises a Debug-only feature; Debug runs it. `ENABLE_TESTABILITY=YES` is a test-command override, not a shipping setting. CI covers the existing automated tests, not every hardware feature, historical upgrade path, or production service.

## Activate and enforce on GitHub

The files take effect after they are committed and pushed. Issue forms are discovered from the default branch. First get a successful workflow run, then configure required checks; do not require a check name that has never run.

1. In **Settings → Actions → General**, allow the official `actions/checkout` action; use read-only workflow permissions and leave workflow PR creation/approval disabled. Require approval for all outside contributors before running their fork PR workflows. Do not add signing or Apple-account secrets to this CI.
2. In **Settings → Branches**, add protection for `main`: require a PR, require `Simulator tests (Debug)` and `Simulator tests (Release)`, require branches up to date and conversations resolved, and block force pushes/deletion. Require a second person's approval only when an actual second reviewer is available; the solo owner still reviews the final diff. Apply protections to administrators if you want owner merges enforced too.
3. Review workflow/build-script changes yourself before approving their execution. Maintain the full-SHA action pin through reviewed updates; do not enable automatic dependency merges.
4. In **Settings → Security**, enable private vulnerability reporting when available. Public issues are for fictional reproduction examples; vulnerabilities and sensitive reports use private reporting. Do not ask reporters for real financial records or backup passphrases.

Account/repository policy may restrict these settings. The local templates do not enable remote protections by themselves. See [protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches).

## If sensitive material is exposed

Stop publishing it, restrict/remove affected logs or attachments, revoke/rotate exposed credentials, and assess repository history and downstream copies. Deleting a current file alone does not remove prior commits or copies. Record the incident privately without repeating the secret or user data.
