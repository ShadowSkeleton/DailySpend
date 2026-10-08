# DailySpend definition of done

These criteria apply to both human and agent work. Scale the checks to the change; explain any not-applicable item. Missing evidence is not a passing result.

## Done for merge

- The issue or PR states the problem, scope, and observable acceptance criteria; the implementation meets them.
- The final diff is reviewed for correctness, regressions, privacy, and unintended changes. Workflow and build-script edits receive explicit owner review before execution.
- Relevant automated coverage exists. A reproduced bug receives a meaningful regression test where automation can establish the behavior. Cosmetic edits alone need no new unit test.
- Required Debug and Release simulator checks pass on the final revision. Configuration-specific skips and unavailable checks are disclosed; a skipped private-repository workflow is not tested evidence.
- Changed UI/UX is checked on affected journeys with synthetic-data screenshots and relevant accessibility, keyboard, locale, appearance, and layout checks. Unavailable device checks are recorded.
- Persistence, migration, iCloud, backup/restore, or storage-identity changes consult `.agents/skills/dailyspend-upgrade-safety/SKILL.md` early and include appropriate isolated tests and an upgrade-impact explanation.
- No private records, real receipts, exported databases/backups, passwords, tokens, signing keys, or provisioning profiles enter source control, issues, PR attachments, or CI logs.
- Documentation describes changed behavior, compatibility, and material limitations. Any performance-sensitive change has representative synthetic-data evidence.
- Unresolved material defects prevent merge. Follow-up work has a concrete issue; it is not used to defer known data-loss or privacy defects.

## Done for release

Merge-ready does not mean release-ready. Before App Store Connect upload, restricted validation, broad TestFlight distribution, or public release:

- Use the DailySpend quality workflow and complete the applicable full data-safety review.
- Record candidate version/build, revision/archive identity, actual distributed baselines, platform coverage, test results, and independent recovery evidence in version-specific reports.
- Keep upload/restricted-validation and broad-distribution/public-release gates separate. Essential missing evidence is `HOLD`; a demonstrated material defect is `BLOCKED`.
- Complete required signed physical-device, historical on-disk upgrade, backup/recovery, and multi-device/mixed-version checks for the specific gate. Simulator CI does not establish these claims.
- Retain supported older OS coverage and record planned Xcode/macOS 27 and iOS/iPadOS 27 checks, including unavailable environments.
- Distribution is separately authorized. Passing CI never automatically uploads an app or deploys a CloudKit schema.
