# Release Evidence and Decisions

Create a report for the actual candidate, preferably `docs/releases/<version>-<build>-DATA_SAFETY.md` using real version/build values. If the repository has a release-report convention, follow it. Keep reports free of private records and credentials. Do not overwrite a previous release's evidence.

## Report contents

Include the candidate revision/archive identity, app and build numbers, actual released baselines, schema/backup/envelope contracts, signed container/group/environment, and toolchain/OS/device matrix. Inventory all data surfaces and identify authoritative, derived, transient, and backed-up data.

For each migration/conflict/recovery scenario, record:

| Scenario and baseline | Expected invariant | Method/environment | Actual evidence | Status and next action |
|---|---|---|---|---|

Use `passed`, `failed`, `not run`, or `not applicable` for scenario status. Include meaningful code locations, fixture origin, test command/result artifact, record-level comparison, device evidence, and source citations as appropriate. Source inspection, in-memory tests, disk migration, device restore, and signed cloud tests are separate evidence types. Do not list commands as executed when they were merely proposed.

For findings, state severity, triggering sequence, affected versions/data, cause supported by evidence, recoverability, remedy, and verification needed. Distinguish a reproduced defect, a source-proven unsafe sequence, a plausible risk, and missing evidence. Explain why an excluded case is inapplicable. For an explicitly bounded assessment, complete the report from available artifacts, mark other surfaces unreviewed, and restrict the decision to that scope; do not expand it into an unrequested live release operation.

## Safety gates

`BLOCKED`: a demonstrated or concretely evidenced path to unintended deletion, irreversible rewrite, stranded records/keys, corruption, unsafe conflict handling, partial destructive restore, or store-opening failure without safe preservation/recovery. Do not upload a build with known critical data defects to existing testers. Source review can establish this gate when it proves a reachable sequence and its unsafe outcome; identify the triggering conditions and affected data rather than claiming that every launch fails. A crash call alone, without tracing its reachable failure/recovery path, does not establish database corruption. Conditional concurrency or compatibility concerns whose occurrence or outcome is unresolved should hold the relevant safety claim pending the specified test, rather than being presented as reproduced loss.

`HOLD`: an essential claim lacks evidence, such as actual historical on-disk migration, independent backup round-trip, necessary production schema inspection, signed multi-device convergence, or a supported iOS runtime. Continue safe analysis/tests and name the exact missing resource or user/device action. Unavailable fixtures are not a passing result.

`PASS`: applicable checks for the stated gate passed with recorded evidence, no unresolved material data-safety finding remains, and recovery was demonstrated for tested paths. Qualify the supported versions, environments, and limits; a PASS is scoped confidence, not an absolute guarantee.

Evaluate these gates separately:

1. **Before App Store Connect upload or restricted TestFlight validation:** Complete source/contract review, genuine disk-upgrade tests, representative backup round-trip, isolated automated checks, applicable local platform checks, and required archive identity checks. No known material data defect may remain. State which production-signed checks require the uploaded build; when those are the only outstanding items, a narrowly controlled test upload may be considered with existing authorization and an isolated test cohort. Record public-release status as HOLD.
2. **Before broad TestFlight distribution or public App Store release:** Verify required production schema and exact distribution-build entitlements, physical-device in-place upgrades, relevant device recovery/transfer, signed multi-device/mixed-version sync, and applicable runtime matrix. Development-only or in-memory evidence does not clear this gate.

An upload authorization does not mean all data gates pass. This skill does not upload or deploy on its own. Existing app data must not be uninstalled to achieve an “upgrade” test.

## Recovery and follow-through

Keep the tested old store/backup fixtures, prior archives, and pre-upgrade reference expectations recoverable and free of user secrets. Define who can reproduce the recovery, how unsynced local edits are retained, and which recovery is independent of cloud deletion. Prefer forward-compatible fixes over pretending an old binary undoes a production schema change.

Retest affected checks after a fix or any candidate revision that changes storage, imports, sync, toolchain, signing, or the executable paths under review. Reuse verified unchanged evidence with its revision/scope stated; do not rerun every unrelated test after each cosmetic edit. Tie final physical-device evidence to the distributed version/build and archive rather than a similarly numbered Debug build.

Complete the report with the current gate decisions, prioritized blockers, missing evidence, concrete recovery steps, and the release recommendation. If manual action is required, ask only for the specific missing input while preserving completed work. Never mark unresolved evidence “safe” merely to finish the review.
