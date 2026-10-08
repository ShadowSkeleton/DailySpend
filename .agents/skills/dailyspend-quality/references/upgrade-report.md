# Version upgrade report requirements

Use verified candidate values and evidence. Adjust detail to requested scope; this outline is not a claim of completed checks.

## Candidate and changes

Record date, version/build, revision/worktree changes, archive identity if available, actual distributed baselines and verification source, comparison range, and scope. Include exact Xcode/Swift/SDK/host macOS, deployment targets, tested device/runtime matrix, and unavailable planned environments.

| Feature/change | Previous behavior | Candidate behavior and reason | Existing-user impact/action | Evidence |
|---|---|---|---|---|

Include added/fixed/removed behavior and internal changes with upgrade consequences. Explain prerequisites and supported/skipped-version paths. Provide a separate user-facing release-note draft; do not portray implementation details as new features.

## Feature coverage and results

| Feature | Expected behavior / edge cases | Test file/names or manual scenario | Type/environment | Actual result/evidence | Gap / next action |
|---|---|---|---|---|---|

Use `passed`, `failed`, `not run`, or `not applicable` with reasons. Include commands/configuration, passed/failed/skipped counts, result bundles/logs, and fixture isolation. Identify hardware/service checks unit tests cannot establish and distinguish historical/reused evidence from current results.

## Upgrade safety and compatibility

Link the candidate's `DATA_SAFETY.md` report. Summarize migration/storage contracts, historical store/backup fixture provenance, independent recovery proof, signed multi-device/mixed-version checks, supported OS/toolchain evidence, and non-storage upgrade risks. Do not duplicate the full safety report or infer safety from fresh installs.

## Changed UI/UX

Record changed journeys and screenshot provenance; link before/after captures where available. Each finding includes severity, observed/inferred status, evidence/steps, user impact, suggested fix, and retest result. Record runtime/baseline limitations or the evidence for a not-applicable decision.

## Findings and decisions

| Finding | Severity / evidence type | Affected users/versions | Impact and recovery | Fix or exact missing evidence | Status |
|---|---|---|---|---|---|

| Gate | PASS / HOLD / BLOCKED | Supporting evidence | Outstanding requirements |
|---|---|---|---|
| Upload / restricted validation | | | |
| Broad TestFlight / public release | | | |

Apply existing data-safety gate definitions and identify other material defects preventing release. Provide tested recovery steps; do not assume an old binary reverses schema changes. End with prioritized next actions, specific manual/device needs, release recommendation, and review limits. Keep the report free of private records and credentials.
