---
name: dailyspend-quality
description: Test DailySpend features, review version upgrade and release readiness, critique changed UI/UX, and write detailed upgrade reports. Use for full QA or release preparation, and affected checks during development.
---

# DailySpend Quality and Upgrade Review

Deliver feature test coverage/results, upgrade safety decisions, UI/UX critique when journeys change, and a detailed version upgrade report. This workflow supports the `dailyspend-quality` project agent and direct invocation by the primary agent.

## Establish the review scope

Read repository instructions and inspect current source and worktree changes without overwriting user edits. Discover version/build, scheme, tests, source revision, deployment targets, and archive identity when available. Establish the baseline from the actual previous distributed build and release artifacts; the previous commit or README candidate number alone is insufficient. Record an unknown baseline and its missing evidence rather than inventing one.

Full QA and release preparation cover the whole feature inventory and all four deliverables. Ordinary development covers affected behavior/regressions, changed UI/UX, and upgrade implications; it does not require a full release audit for cosmetic edits. Creating this agent/skill is not a completed app audit.

Use `README.md`, `docs/PRE_UPLOAD_TEST_PLAN.md`, `docs/APP_STORE_RELEASE_CHECKLIST.md`, `docs/TESTER_DATA_WORKFLOW.md`, `design-qa.md`, and relevant earlier audits as starting sources. Verify them against current code. Historical test counts are not current execution results.

## Feature testing

Build a feature-to-test matrix from current source and journeys. Starting areas: expense creation/edit/deletion; money parsing and exact cents; categories/budgets; recurrence; Home/Insights and date boundaries; quick/item splits, tax/tips and reconciliation; receipt rendering/export and recording a share; scanning; reminders; widgets/deep links; App Lock/scene privacy; backup encryption/import/merge/replacement; CSV; local persistence/migrations and iCloud. Add newly discovered features; explain inapplicable entries.

Map each feature to expected behavior, existing test files/names, gaps, result, and evidence. Use unit tests for deterministic logic, integration tests for durable store/backup behavior, UI tests for interactions, and physical-device/account checks for hardware and signed services. Do not imply that unit tests prove every feature or that a coverage percentage proves correctness.

For requests to implement tests, full QA, or release preparation, add meaningful missing automated coverage within authorized development scope. Cover relevant ordinary/boundary/invalid/cancel/failure/retry cases and assert observable outcomes rather than mirroring implementation. Use deterministic clock/calendar/locale inputs where needed. Cosmetic edits alone need no new unit tests. Review-only requests preserve the requested read-only scope and report gaps.

Before execution, verify isolated temporary stores, test-specific preferences, disposable records, and disabled production cloud writes. UI tests currently use `-ui-testing`; inspect its isolation before relying on it. Consult the upgrade-safety skill before adding persistence/migration fixtures. In-memory tests are separate from on-disk historical upgrades.

Discover installed Xcode and simulator destinations; use the shared `DailySpend` scheme and `DailySpendTests`/`DailySpendUITests` unless changed. Follow current README Debug/Release test conventions, including reasons for configuration-specific skips. Exercise Debug-only behavior in Debug. Release preparation runs applicable full Release automated suites plus configuration-specific checks. Record commands, configuration, exact toolchain/runtime, result artifacts, passed/failed/skipped counts, and unavailable checks. Proposed commands are not executed evidence. After fixes rerun affected checks; broaden when failures or new changes justify it.

## Upgrade and release review

Consult [dailyspend-upgrade-safety](../dailyspend-upgrade-safety/SKILL.md) early for persistence, migration, iCloud, backup/restore, or storage-identity changes. Before App Store Connect upload, TestFlight distribution, or App Store release, complete its full applicable review and version/build-specific data-safety report. It owns storage invariants, evidence requirements, and separate data release gates; do not replace them with weaker duplicate criteria.

Also check non-migration upgrade issues: launch/crash regressions; OS availability/deployment targets; Xcode/Swift/SDK changes; signed entitlements and app/extension identity; permissions/privacy declarations; widget/deep-link compatibility; localization/accessibility; performance on representative data; export formats; and documentation matching shipped behavior. Include planned Xcode/macOS 27 and iOS/iPadOS 27 alongside supported older OS coverage. Verify current Apple documentation and actual tools for platform claims; mark unavailable environments untested.

Record separate `PASS`, `HOLD`, or `BLOCKED` decisions for upload/restricted validation and broad TestFlight/public release. Apply the existing safety skill's exact definitions to data findings. For other material correctness/privacy/accessibility/compatibility issues, demonstrated defects block the affected gate and essential missing evidence holds it. A successful build alone cannot clear a gate; passing data checks does not override other material defects.

Continue independent local checks and authorized fixes when device/account/history evidence is missing, documenting exact gaps. Preserve existing records and independent recovery copies. Never uninstall an existing installation to prove an upgrade. This workflow grants no authority to upload, distribute, deploy production schemas, access private records, or run destructive live-account tests. A release verdict is separate from authorization to distribute.

## UI/UX critique for updates

Identify changed screens and affected journeys from the candidate diff. Capture and inspect actual screenshots before visual claims; compare with baseline captures when available. Use native simulator/device tools or relevant screenshot artifacts. Record build, device/runtime, appearance, text size, and reproduction steps. If Product Design audit is available and applicable, follow its screenshot-first method; the workflow must also work without that plugin.

Review relevant navigation/task completion, hierarchy/clarity, amount entry/keyboard dismissal, tap targets, validation/cancel/error states, empty/loading states, destructive actions/recovery, privacy, VoiceOver labels/focus, Dynamic Type, contrast, localization/long content, dark mode, and iPhone/iPad layouts. Verify interactions where possible; screenshots alone cannot prove accessibility or behavior. Respect established intentional design choices.

Give each finding severity, screenshot or reproduction evidence, affected journey, user impact, and a concrete suggested fix. Separate reproduced interaction defects, observed visual issues, source-inferred concerns, and subjective suggestions. Missing runtime access or baseline captures remain explicit limitations. If no UI/UX changed, record comparison evidence and mark this section not applicable.

## Detailed version report

Follow [upgrade-report.md](references/upgrade-report.md). Write `docs/releases/<version>-<build>-QUALITY.md` with verified values and links to data-safety, test, and screenshot evidence. Preserve previous candidate evidence; distinguish later revisions/review dates instead of overwriting unrelated reports. For bounded development without a fixed candidate, use a dated filename and identify unknown version/baseline values.

Explain what changed and why, before/after behavior, existing-user impact/actions, migrated/preserved contracts, compatibility, known issues, and tested recovery. Provide user-facing release-note drafts and engineering detail. Distinguish checks executed now, reused evidence with revision/scope, proposed checks, and checks not run.

Finish with prioritized defects, exact missing evidence/next actions, separate gate decisions, and verification limits. Finish available work/report when a gate cannot pass. Never claim all features tested, all upgrades safe, or release ready without supporting evidence.
