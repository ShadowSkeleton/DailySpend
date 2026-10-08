# DailySpend Storage Map

Observed October 2, 2026. This is a starting map, not proof of release behavior. Refresh it against the candidate and genuine released versions on every audit. Paths below are relative to the app repository.

| Surface | Starting source | What to verify |
|---|---|---|
| Store startup and sync selection | `DailySpend/DailySpendApp.swift` | `ModelContainer`, active schema, actual configuration URL, private CloudKit selection, local fallback, failure handling, and test isolation. |
| Persistent business models | `DailySpend/Expense.swift` | `Expense` and `CategoryBudget`; identity, amount representation, defaults/optionality, categories, notes, dates, and recurrence fields. |
| Legacy money conversion | `DailySpend/MoneyStoreMigration.swift`, `DailySpend/Money.swift` | Additive `Double` to optional `Int64` cents backfill, rounding, idempotence, save/rollback, and late-arriving legacy records. |
| Backup formats and application | `DailySpend/AppModels.swift` | `AppBackup`, payload version, legacy migration, validation, merge/replace, duplicate IDs/categories, and settings handoff. |
| Export/import UI and preferences | `DailySpend/SettingsView.swift`, `DailySpend/ContentView.swift` | Actual exporter completion, external file location, security-scoped reads, file size limits, password handling, replacement safeguards, and preference keys. |
| Encrypted backup envelope | `DailySpend/SecureBackupCodec.swift` | Authenticated encryption and KDF parameters, envelope version, compatible decoding, error handling, and no persisted passphrase. |
| Shared widget cache | `DailySpend/WidgetSnapshot.swift`, `DailySpend/AppUtils.swift`, `DailySpendWidget/DailySpendWidget.swift` | App Group suite, versioned payload, validation, atomic whole-value publishing, compatibility, and lock/privacy state. |
| Recurring expense writer | `RecurrenceHandler` in `DailySpend/DailySpendApp.swift` | Child creation plus cursor updates, commit failures, bounded catch-up, and multiple devices generating the same occurrence. |
| Transaction writers and split recording | `DailySpend/TransactionViews.swift`, split views/logic, `DailySpend/AppUtils.swift` | Save/rollback, cancellation, exact cents, imports, deletion, and record identity. |
| Models outside current schema | `DailySpend/Friend.swift` and future models | A source `@Model` declaration does not prove it is stored. Compare active and previously shipped schemas before declaring data unused or removing it. |
| Receipt/share files and transient drafts | Scanner views, receipt export, split views, future file code | Determine what is durable versus explicitly transient; inventory new attachments and originals. |
| Build/signing identities | `DailySpend.xcodeproj/project.pbxproj`, app/extension entitlements, `DailySpend/Info.plist` | Source and signed archive identities, capabilities, push/background modes, deployment targets, and App Group access. |

## Observed contracts to reverify

- App bundle ID: `com.jackson.LoveLedger`.
- Widget extension ID: `com.jackson.LoveLedger.LoveLedgerWidget`.
- Private CloudKit container: `iCloud.com.jackson.LoveLedger`.
- App Group: `group.com.jackson.LoveLedger`.
- The current explicit container schema includes `Expense` and `CategoryBudget`; no explicit `VersionedSchema` or `SchemaMigrationPlan` is present in the inspected startup path. Do not infer migration correctness from that absence or from comments calling a field additive.
- The startup path tries a CloudKit configuration, then a local-only configuration, and can terminate with `fatalError` if both fail. Verify actual error handling and store URLs; do not assume the two configurations prove recovery.
- `amountMinorUnits` is optional alongside legacy `amount: Double`. Readers prefer cents when present. Older writers changing only `amount` can make paired representations disagree; test mixed-version behavior before deciding how to resolve it.
- Current JSON payload format is 3; the encrypted envelope format is 1. These are separate contracts and both may evolve.
- Standard preferences include budget/reminder settings, `isAppLockEnabled`, `showScanTip`, and `cloudKitStoreFallback`. Discover all keys and domains, including App Groups, before classifying coverage.
- Widget payload key is `dailyspend.widget.snapshot.v1`; legacy scalar keys are removed after a valid snapshot save. This is derived data, not a recoverable expense history.
- Current portable backups contain expenses, category budgets, and selected budget/reminder settings. They do not promise to restore App Lock, iCloud login, OS permissions, or every future preference. Verify scope explicitly.
- Some current tests construct in-memory stores with the current models. They validate helpers and context saves, not an actual old on-disk schema upgrade, signed production sync, or device backup recovery.

## Discovery and existing release evidence

Use `rg` for `@Model`, `ModelContainer`, `ModelConfiguration`, schema/migration types, save/delete/rollback calls, Codable formats, defaults/suites, file access, CloudKit, App Groups, Keychain, and backup exclusion/protection flags. Trace live callers and include new targets or dependencies.

Consult the applicable data sections of `docs/APP_STORE_RELEASE_CHECKLIST.md`, `docs/PRE_UPLOAD_TEST_PLAN.md`, and `docs/TESTER_DATA_WORKFLOW.md`; preserve user edits and avoid unrelated release/marketing work. Read historical shipped schema/code and sanitized fixtures from verified tags, commits, archives, or supplied evidence. A working-tree version number or a development model is not proof of what users have installed.
