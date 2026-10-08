# Data-Safety Review

Use these scenarios to find concrete failures and establish recoverability. Tailor implementation details to the actual candidate, but cover every durable surface in a full release audit. Test isolated data; never induce faults in a user's only store or in an account that syncs to real devices.

## Local stores and migrations

Establish the oldest supported installed baseline, latest shipped baseline, and any intermediate schema/format transition. Include users skipping releases and a first launch after a long absence. If no release history can be verified, record the limitation; do not manufacture an “old” fixture with the new model and claim upgrade coverage.

Inspect schema diffs for entity/property renames, deletions, type changes, enum/raw-value changes, defaults, optionality, uniqueness, relationships/inverses/delete rules, transforms, version hashes, and custom migration stages. Separately review conversion/backfill logic executed after a store opens. Assess all stores and configurations, including a future move into an App Group. Preserve identifiers and ownership metadata.

Create representative fixtures with the actual old schema/build in a disposable location, close it safely, preserve a consistent original, and open a copy with the candidate. Include empty, typical, large, partially migrated, duplicate-identity, unexpected-category, Unicode-note, nil-recurring-state, historic zero-value, precision-edge, and legacy-invalid records. Use a documented policy for invalid legacy values; never silently drop them or call arbitrary rounding “lossless.”

Compare every relevant record before/after: stable identity, exact monetary expectation, raw legacy fields retained for recovery, category, original note, timestamp, recurrence frequency, template/child role, processed cursor, and budget values. For changed representations, record the intended mapping and acceptable precision rather than comparing only the displayed sum. Check orphaned relationships and attachments if present.

Test persistence after close/reopen and process restart. Test migration retry, interruption before/during/after commit, low disk/write failure, unreadable or corrupted copies, large histories, and foreground reentry. Verify checkpoints are committed only with their corresponding records, and a retry cannot double-apply conversion or reinsert recurring entries. Where fault injection is unavailable, state which path is only source-reviewed.

Trace open failures: missing entitlements, unavailable protected data, transient cloud/account errors, incompatible schema, wrong URL, and corruption require distinguishable outcomes. Check for force unwraps, `try!`, `fatalError`, swallowed save/fetch errors, silent “empty” results, destructive fallback, and accidental fixture/demo seeding. A locked or unavailable store must not appear as a verified empty dataset. Recovery must preserve the original and avoid damaging it through repeated retries.

Inspect all mutation paths and actor/context ownership. A durable-store save and a later UserDefaults update are separate operations; test a crash between them and define reconciliation. Check update versus delete behavior, rollback after partial mutations, background termination, and multiple processes or extensions where applicable.

For raw store snapshots, coordinate with the owning framework and close/checkpoint as required. Preserve SQLite WAL/SHM where required, external binary storage, persistent-history and CloudKit metadata. A copied main SQLite file or an integrity check alone does not prove semantic migration or sync correctness. Never issue raw SQL repairs to a live SwiftData-managed store as routine cleanup.

## iCloud and mixed-version conflicts

Trace source and signed archive to the same intended private container/environment. Inspect production record types, fields, and indexes against the candidate and shipped models. Keep deployment additive; do not remove or rename existing production fields/types or reset production data. Creating a different container can strand existing records and requires a separately tested transition.

Review CloudKit-compatible modeling with current Apple guidance: uniqueness and relationship assumptions differ from purely local stores. Check how record identity, deletion, duplicate categories, optional fields, new raw enum values, and older clients are handled. Schema deployment and record migration are distinct; development records are not copied into production by deploying schema.

Use two signed physical test devices with a dedicated test account, and record actual record convergence, not merely `CKAccountStatus.available`. Cover:

- Create/edit/delete with current builds, delayed sync, and concurrent edits of the same expense or budget.
- Old app on one device and candidate on another, including older iOS alongside iOS 27. Old clients may remain installed indefinitely; do not assume every device upgrades together.
- Offline edits, pending writes before app upgrade, reconnection, late records, and an additive backfill encountering legacy data after startup.
- Legacy `Double` and new cents disagreement after an older client edit. Preserve valid user edits and report ambiguous conflicts; do not silently prefer a stale representation.
- Duplicate UUIDs/categories and two devices materializing the same recurring occurrence. Inspect deterministic occurrence identity or deduplication evidence rather than assuming random UUIDs prevent semantic duplicates.
- Delete versus update races, tombstones, old backups reintroducing previously deleted records, and prevention of unexplained resurrection.
- Sign-out/sign-in, account switching, iCloud disabled/restricted, network or quota failures, and first unlock. Keep accounts isolated and document what remains local versus cloud-owned.
- Local fallback followed by cloud recovery; verify the intended same durable store, preserved unsynced changes, no split histories, and no duplicated reimport.
- Fresh install/reinstall or device transfer on a disposable setup, followed by cloud redownload and recurrence processing. Do not treat an empty account, eventual delay, or failed fetch as permission to clear local records.
- Replacement restore with remote edits or offline devices, since local deletes can later propagate. Test a recovery copy independent of that sync domain.

Preserve both sides of an unresolved conflict or use an evidenced reconciliation strategy that protects confirmed user intent. Do not invent a last-write timestamp or trust wall-clock ordering without a supported record contract. Measure convergence over documented observations; a timeout is missing evidence, not necessarily proof of permanent loss.

Signed production-backed evidence is required for public release. Simulator and development-environment success cannot prove App Store entitlements or production schema behavior.

## Recovery, backups, and all other storage

Classify each surface as authoritative, derived, or intentionally transient. Record location, owner/account, format, key/protection requirements, backup inclusion, cleanup rules, and recovery procedure. Include Application Support, Documents, App Groups, defaults, Keychain if present, Files/iCloud Drive/document providers, attachments, share/export files, and newly added storage. An unavailable file provider is not an empty file.

Review on-phone protection and system backup eligibility: actual directories, `isExcludedFromBackup` flags, file protection and locked-device availability, encryption keys, and restore behavior. Do not store irreplaceable records solely in caches or temporary paths. An App Lock UI does not itself establish encryption of the database or safe widget/log/export exposure.

Distinguish three mechanisms: CloudKit sync, encrypted portable DailySpend backup, and iOS/device backup or transfer. Each has different scope. Check iCloud device backup, Finder/device backup where supported, and device-to-device transfer using disposable data and actual supported OS combinations. Record which app files and settings are included, missing, or reconstructed, and test the first launch after restore before and after cloud reconnection. Do not claim a device backup was validated by a JSON import test.

For portable backups, cover every supported historical payload and encryption-envelope version. Exercise ISO timestamps, old formatted/epoch dates, locale/time-zone/DST differences, Unicode, recurring templates/children/cursors, selected settings, and exact cents. New/unsupported versions must fail clearly without mutations; retain old decoders for supported backups. Unknown fields should not cause unintended loss when a newer contract is introduced.

Verify authenticated decryption, correct and incorrect passphrases, tampered/truncated files, invalid IDs or amounts, duplicate incoming and existing identities/categories, contradictory raw/cents values, invalid dates, excessive sizes/counts, and bounded KDF/resource costs. Test passphrase Unicode and compatible derivation when changing crypto code. Avoid storing passphrases, plaintext recovery copies, or sensitive debug logs. Define what recovery is possible without a forgotten passphrase; do not imply the developer can decrypt it.

Export a known dataset to an external file, verify it can be read, decrypt it, restore on an isolated setup, reopen, and reconcile record-level values and covered settings. Check cancellation and file-provider errors, both before export and during write. An in-memory encoded buffer is not a saved backup. For destructive replacement, verify the safety backup actually covers the pre-replacement state, is recoverable, and is not already stale due to concurrent local/cloud writes.

Merge must preserve current records/settings according to its documented contract, add missing identities once, and be idempotent where stable IDs exist. Legacy backups without IDs need an explicit duplicate-risk policy; do not promise repeated-import deduplication merely because modern imports deduplicate. Replacement must require an independently saved safety backup plus intentional confirmation, handle concurrent writers, and avoid a partial database/preferences commit. Restore failure, cancellation, or invalid input must leave durable data intact or recover to the documented snapshot.

Rebuild derived widget caches from authoritative data. Check backward/forward payload handling, stale renders, old keys, App Group identity, whole-snapshot publishing, app/widget version mismatch, and privacy when App Lock is enabled. Cache cleanup must not reach authoritative records or independent backups. Record expected OS widget-refresh limitations without treating stale display as lost database data.

CSV and receipt images are useful exports but not full recovery artifacts. Check spreadsheet formula exposure, temporary plaintext files, security-scoped access, share permissions, and cleanup only after the authoritative record/recoverable backup remains intact.

## Official technical sources

- [SwiftData synchronization and CloudKit model restrictions](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).
- [Core Data model evolution with CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit).
- [Production schema deployment](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
- [File-system locations and backup exclusion](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively).

Verify current guidance for the exact API and platform before using it to clear a release. If official guidance does not establish a behavior, use appropriate device evidence or record the uncertainty.
