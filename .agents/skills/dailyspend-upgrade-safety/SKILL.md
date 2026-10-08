---
name: dailyspend-upgrade-safety
description: Review DailySpend version upgrades before App Store Connect upload, TestFlight distribution, or App Store release for migration, iCloud, and backup safety.
---

# DailySpend Upgrade Safety

Protect existing DailySpend records and their recoverability across app, schema, backup-format, SDK, and OS upgrades. Complete an evidence-based review before each release; a successful build or fresh installation does not establish upgrade safety. Treat “no unintended data loss” as a release acceptance criterion, not a guarantee that software or storage can never fail.

## Scope and working context

Use this skill when preparing a DailySpend version, assessing release readiness, or changing persistence or migration behavior intended for an upgrade. Ordinary UI edits do not require the full release audit; flag relevant storage risks as they arise and perform the full audit at release preparation. For a bounded or read-only assessment, finish within the supplied scope, mark unseen surfaces unreviewed, and do not clear a complete release from partial evidence.

Locate the current repository by its `DailySpend` app target, not an assumed absolute checkout path. Read [storage-map.md](references/storage-map.md) to find the data paths, then verify that map against current source and the released baseline. Discover newly added storage, extensions, settings, attachments, encryption keys, or services; the map is not an exhaustive future inventory.

For each version, record the candidate version/build and source revision, supported installed versions, schema and backup versions, CloudKit environment, exact Xcode/Swift/SDK builds, host macOS, deployment targets, and tested device OS builds. Include the planned macOS 27 development environment and iOS/iPadOS 27 runtime while retaining coverage of supported older iOS versions. Check current Apple release notes rather than freezing platform assumptions in this skill.

## Review routes

- For on-device stores, schema evolution, launch recovery, and conversion logic, use the local-store section of [data-safety-review.md](references/data-safety-review.md).
- For iCloud, mixed-version devices, conflicts, and production schema, use its CloudKit section.
- For portable backups, on-phone storage, device backup/transfer, encryption, and export/restore, use its recovery section.
- For Xcode, macOS 27, iOS 27, availability, signing, and SDK behavior changes, use [platform-compatibility.md](references/platform-compatibility.md).
- For test evidence, per-version invariants, and release decisions, use [release-evidence.md](references/release-evidence.md).

A full pre-release review covers all data-safety sections and platform compatibility. Load them by need as the work progresses. Mark a surface not applicable only after verifying that the candidate does not use it; do not skip a storage path solely because its file did not change.

## Essential invariants

Preserve record identities, exact money values, dates, notes, budgets, recurrence state, settings, and accessible recovery copies, subject only to explicit user-authorized edits or deletions. Compare record-level values as well as counts and totals; compensating errors can leave totals unchanged.

Keep store location, bundle identity, CloudKit container, App Group, entitlements, keys, and backup contracts compatible. An intentional change requires a tested transition for existing installations. Prove schema opening and data backfill separately, including interrupted execution, retry, skipped app versions, late cloud arrivals, and mixed-version writers.

A store-opening failure must preserve the original store and provide an actionable recovery path. Do not silently delete or recreate a store, seed an empty replacement, switch to an in-memory store, or discard incompatible data to make launch succeed. Any local-only fallback must be shown to reach the same intended durable store and to recover safely when sync returns.

iCloud synchronization is not an independent recovery history: edits and deletions can propagate. Verify an independent recoverable backup. CSV is not a full DailySpend backup. A backup export success indicator is not proof until a representative file is read, decrypted, restored, and reconciled on an isolated setup.

## Execution boundaries and persistence

Carry the review through source tracing, applicable safe checks, evidence collection, and a concrete release report. Identify missing device, historical-fixture, or account evidence early, and continue independent local work. Do not stop after a checklist or treat missing evidence as a passing result.

Run local tests only after establishing isolated fixtures, temporary stores, test-specific preferences, and disabled production cloud writes. Use disposable records and a dedicated test account for destructive sync, replacement, device-restore, or account-change tests; a spare phone on the user's everyday iCloud account is not isolation. Reading this skill does not authorize accessing private user databases, extracting financial records, uploading an archive, deploying a production schema, resetting cloud data, uninstalling the app, or sending tester messages.

Preserve raw data and inspect copies. Use a framework-supported consistent snapshot for SQLite-backed stores, including required sidecars, external blobs, and metadata; do not copy only a live main database file. Never expose backup passphrases or customer data in reports, fixtures, commits, logs, or external services. If repair is authorized, make focused fixes and rerun affected checks; an audit request alone does not authorize a risky production repair.

## Release outcome

Write a version-specific report following [release-evidence.md](references/release-evidence.md), with code locations, reproducible scenarios, expected invariants, actual evidence, severity, and the next action for each issue. Use `PASS`, `HOLD`, or `BLOCKED` for the specific gate under review. Retest after storage-relevant changes, and tie device evidence to the actual distribution build.

Block release for a demonstrated risk of unintended loss, corruption, unrecoverable store failure, or unsafe conflict handling. Hold the relevant gate for missing essential migration, restore, production-sync, or platform evidence. Upload for narrowly controlled validation can be considered separately when its pre-upload safety checks pass; it does not clear broad TestFlight distribution or public release. State remaining risks and verification limits plainly. Do not claim “data can never be lost.”
