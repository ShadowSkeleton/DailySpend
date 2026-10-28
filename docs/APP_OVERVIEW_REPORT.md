# DailySpend 1.0 — Codebase Overview Report

Reviewed: October 25, 2026 · Source: `main` @ `9c576f6` plus uncommitted working-tree changes · Reviewer: Claude Code (read-only review; no builds, tests, or device checks were run for this report)

This is an onboarding snapshot of what the app is, how it is built, and what the release-safety agent does. Findings in §8 come from reading the source. None of them were reproduced on a device.

---

## 1. What the app is

**DailySpend** (formerly *LoveLedger*) is a native SwiftUI app for iPhone and iPad. Tagline: *“Private spending. Fair splitting.”*

- **Personal expense tracker:** expenses, categories, recurring entries, budgets, insights, widgets.
- **Bill splitter:** even or itemized splits with tax and tip, exact-cent reconciliation, and a shareable receipt image.
- **Privacy-first:** no accounts, ads, analytics, IAP or tracking. Data is stored on-device and synced through private CloudKit. App Lock is optional, and backups are passphrase-encrypted.
- Bilingual UI (English / Simplified Chinese), chosen by device language through a hand-rolled `L10n` struct.
- No bank connections and no money movement. It only calculates.

| Item | Value |
|---|---|
| Version / build | **1.0 (14)** (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`) |
| Deployment target | iOS/iPadOS 17.0 |
| Toolchain last validated | Xcode 26.6, iOS 26.5 simulator (per README, Sep 10 2026) |
| Swift language mode | 5.0 |
| Targets | `DailySpend` app, `DailySpendWidget` extension, `DailySpendTests`, `DailySpendUITests` |
| Size | ~8.9k lines of Swift (≈7.3k app, ≈0.6k widget, ≈1k tests) |
| Dependencies | None (Apple frameworks only) |

### Legacy identifiers (must never change)

| Purpose | Identifier |
|---|---|
| App bundle | `com.jackson.LoveLedger` |
| Widget extension | `com.jackson.LoveLedger.LoveLedgerWidget` |
| CloudKit container | `iCloud.com.jackson.LoveLedger` |
| App Group | `group.com.jackson.LoveLedger` |
| URL scheme | `dailyspend://` (`home`, `add`) |

---

## 2. Architecture at a glance

```
DailySpendApp (ModelContainer: Expense + CategoryBudget, CloudKit private DB → local fallback)
 ├─ MoneyStoreMigration (one-shot additive Double → cents backfill at launch)
 ├─ RecurrenceHandler (invisible view; generates due recurring children on launch/foreground)
 └─ ContentView (TabView + App Lock + privacy shield + widget sync + notifications + deep links)
     ├─ Tab 0  Home        HomeViews.swift, TransactionViews.swift, CommonComponents.swift
     ├─ Tab 1  Split Bill  SplitBillView / SplitBillEvenlyView / SplitBillBasketView / SplitBillLogic
     ├─ Tab 2  Insights    InsightsViews / InsightsCharts / InsightsAnalysis / InsightsActivity
     └─ Tab 3  Settings    SettingsView.swift (+ About, Privacy policy, Category budgets, Backup/Restore)

DailySpendWidget ── reads WidgetSnapshot (JSON v1) from App Group UserDefaults
```

Key design choices:

- **Exact money math.** `Money` holds `Int64` minor units and computes through `Decimal`. `splitEvenly` and `allocate` use the largest-remainder method, so every split reconciles to the cent.
- **Additive schema evolution.** Every new persisted field is optional or defaulted. There is no `VersionedSchema` or `SchemaMigrationPlan`, so the app relies on SwiftData lightweight migration.
- **Preferences live in `UserDefaults.standard`** (`@AppStorage`), not in SwiftData. This affects what syncs (see §8).

---

## 3. Feature inventory

### 3.1 Expense tracking (Home tab)
- Dashboard header with month total, remaining or over-budget amount, a progress indicator, and month navigation through a custom month/year picker. Future months are blocked.
- Recent-transactions list grouped by date. Full-card tap opens Edit. Red swipe-to-delete. Multiline notes.
- **Add Expense:** amount (locale-aware parsing; decimal comma keeps cents), 9 fixed categories (Food, Grocery, Shopping, Transport, Housing, Entertainment, Health, Utilities, Other), date, note, and repeat frequency (None/Daily/Weekly/Monthly/Yearly). Keyboard dismiss button.
- **Receipt scan** from Add: VisionKit document camera, then on-device `VNRecognizeTextRequest`, then `ReceiptAmountParser`, which picks a likely total using label priority (“total”, etc.). The result is a suggestion only. A one-time scan tip can be dismissed for good (`showScanTip`).
- **Edit / Delete Expense.**
- **CSV export** via ShareLink, with formula-injection protection (`'` prefix for `= + - @`).
- Empty-state first-use path.
- Validation: amounts must be > 0, have at most 2 decimals, and stay ≤ 10¹⁴ minor units.

### 3.2 Recurring expenses
- A *template* expense has `frequency != none` and `isRecurringChild == false`. `RecurrenceHandler` materializes due *children* on launch and on every foreground, then advances `lastProcessedDate`.
- Monthly recurrence anchors to the original date, which avoids drift from Jan 31 to Feb 28.
- Catch-up is capped at 366 occurrences per launch and resumes on the next launch. A failed save rolls back both the children and the cursor.
- Older “(Auto)” note suffixes are hidden in the UI only. The stored notes are never rewritten.

### 3.3 Budgets & reminders (Settings)
- Overall monthly budget with a toggle and amount, plus a low-balance alert threshold.
- Per-category budgets (`CategoryBudget` model, synced).
- Daily budget report: a local notification at a chosen time showing the remaining amount. Wording changes for low balance and for over budget.

### 3.4 Insights tab
- **Trends:** time ranges (This Month / Last Month / This Year / All Time / custom month navigation), spending trend chart (Swift Charts, selectable points), interactive pie chart by category, an analysis card that names month-over-month change and its main driving category, and a category ranking list.
- **Activity:** calendar heat view with per-day totals, day detail sheet, no-spend-day messaging, and VoiceOver labels on calendar cells.

### 3.5 Split Bill tab
- **Quick Split (Evenly):** total, people count, tax, and tip (percent or fixed). Cent-exact per-person shares.
- **By Item (Basket):** add people. Add personal items per person, and shared items that you toggle on for selected participants. Tax and tip are allocated proportionally. Each person's card shows shared-item allocations with participant names.
- **Receipt:** a rendered receipt view (dashed lines, participants, expanded shared subtotals) exported as an image through `ImageRenderer`, with a `UIGraphicsImageRenderer` fallback for very tall receipts, then shared.
- **Record my share:** saves one person's share as an expense with a generated note.
- Split sessions are temporary. They are not a persistent debt ledger.

### 3.6 Widgets
- **Quick Add** (small): deep-links to `dailyspend://add`, which opens New Expense. It waits if an edit sheet is already open.
- **Dashboard** (small and medium): month total, budget, and a 7-day bar chart in cents, with explicit empty and stale (“open app to refresh”) states.
- Data flows through one versioned `WidgetSnapshot` JSON in the App Group. The widget never receives transactions or notes. When App Lock is on, the snapshot carries zeros and `hidesAmounts = true`.
- Publishing is debounced by 1 s on data changes and runs immediately on scene-phase changes.

### 3.7 Privacy & security
- **App Lock:** `LAContext.deviceOwnerAuthentication`, re-required every time the app becomes active. Content is hidden from VoiceOver while locked. If the device has no authentication set up, the user is offered a way to turn App Lock off.
- **Scene privacy shield:** a separate overlay `UIWindow` (`SceneProtectionWindow`) covers everything, including open sheets, in the app switcher.
- `PrivacyInfo.xcprivacy` is present for both the app and the widget.

### 3.8 Data management
- **Encrypted backup:** JSON payload format v3, wrapped in an AES-256-GCM envelope (v1). The key comes from PBKDF2-HMAC-SHA256 with 310k iterations and a 16-byte salt. The passphrase must be at least 12 characters and is never stored.
- **Restore:** decodes v3 ISO-8601, older formatted-date payloads, and legacy array-only v1 payloads (epoch or formatted dates). Legacy recurrence is upgraded safely through `BackupMigration`.
  - *Merge* only adds missing IDs and categories. It never overwrites local records or settings.
  - *Replace* first forces you to save a **safety backup**, then asks for a final confirmation. It is applied in a single save and rolled back on failure. It also restores budget and notification settings.
  - Validation: amount sanity, raw-value/cents consistency, duplicate IDs and categories, a size limit, and format version.
- **iCloud status** row (`CKContainer.accountStatus`), plus an indicator when the app is running on the local-only fallback store.
- About page and in-app privacy policy (bilingual).

### 3.9 Debug-only
- `-seed-demo-data` launch argument seeds demo expenses and budgets into an empty store (`#if DEBUG`).
- `-ui-testing` runs on an in-memory store with CloudKit off.

---

## 4. Persistence & data surfaces

| Surface | Location | Role | Synced? |
|---|---|---|---|
| `Expense`, `CategoryBudget` | SwiftData default store (`default.store`) | **Authoritative** | Yes, CloudKit private DB |
| Overall budget, threshold, notify settings, App Lock flag, scan tip, fallback flag | `UserDefaults.standard` | Authoritative (per device) | **No** |
| Widget snapshot `dailyspend.widget.snapshot.v1` | App Group defaults | Derived cache | No |
| Encrypted / plain JSON backups, CSV | User-chosen Files location | Independent recovery copies (CSV = partial) | Up to the user |
| Split sessions, receipt images | Memory / share sheet | Transient | — |

### Schema history (from git)

| Baseline | `Expense` | `CategoryBudget` |
|---|---|---|
| `build-7` tag (Dec 2025) | id, amount, category, note, date, frequency? | category, amount |
| Build 10 (Jan 2026) | + lastProcessedDate?, isRecurringChild | — |
| 1.0 (14) current | + amountMinorUnits? (Int64) | + amountMinorUnits? |

All changes are additive and optional or defaulted, which suits lightweight migration and CloudKit. Build 10 opened the container with `.modelContainer(for:)`, which infers the CloudKit container from entitlements. 1.0 (14) names `.private("iCloud.com.jackson.LoveLedger")` explicitly. Both should resolve to the same store and container, but the agent should confirm this on a real upgraded device.

---

## 5. Quality infrastructure

- **Tests:** 51 `func test…` total. `MoneyAndSplitTests.swift` covers money parsing and allocation, splits, receipt data, backup validation and encryption, migration, and recurrence. `WidgetSnapshotTests.swift` covers the widget snapshot. `DailySpendUITests.swift` covers navigation, sheets, keyboard dismissal, and demo data. The README records 50 passing in Release (Sep 10, 2026). That is historical evidence, not re-run here.
- **CI** (`.github/workflows/ci.yml`, **untracked**): Debug and Release simulator matrix on `macos-26` / Xcode 26.6. It runs only when the repo is public, uses a pinned checkout action, read-only token, and no secrets. It also runs `scripts/ci/check_repository_safety.py`, which rejects keys, provisioning profiles, databases, and backup files, plus unit tests for the CI helpers.
- **Process docs:** `DEVELOPMENT_WORKFLOW.md`, `DEFINITION_OF_DONE.md`, `PRE_UPLOAD_TEST_PLAN.md`, `APP_STORE_RELEASE_CHECKLIST.md`, `TESTER_DATA_WORKFLOW.md`, `TESTFLIGHT_NOTES.md`, issue and PR templates.
- **Public site:** `docs/index.html`, `docs/privacy/`, `docs/support/` for GitHub Pages.

---

## 6. Your release-safety agent system

There are two layers, both written for Codex. `AGENTS.md` makes them mandatory before any upload or release.

### 6.1 `dailyspend-upgrade-safety` skill (`.agents/skills/dailyspend-upgrade-safety/`)
The data-safety gatekeeper. Its job is to make sure existing users never lose data across app, schema, backup-format, SDK, or OS upgrades.

- **`SKILL.md`** sets out the invariants: preserve record IDs, exact cents, dates, notes, budgets, recurrence state, settings, and recovery copies. Keep the bundle ID, container, App Group, and store location stable. A failed store open must never silently create an empty store.
- **`references/storage-map.md`** is a starting inventory of every data surface and source file, plus the observed contracts (IDs, payload v3, envelope v1, widget key).
- **`references/data-safety-review.md`** lists scenarios in three areas:
  - local-store migration: real old on-disk fixtures, interruption and retry, corruption
  - iCloud with mixed versions: two signed devices, an old client next to a new one, duplicate recurring occurrences, delete/update races, account switching
  - recovery: portable backups, device backup and transfer, encryption edge cases, widget cache, CSV
- **`references/platform-compatibility.md`** covers the Xcode/macOS 27 and iOS 27 matrix while keeping iOS 17 support, plus app-only, OS-only, and combined upgrade orders and archive entitlement checks.
- **`references/release-evidence.md`** defines the report format (`docs/releases/<ver>-<build>-DATA_SAFETY.md`). It uses scenario tables with `passed / failed / not run / n.a.` and gates `PASS / HOLD / BLOCKED`, evaluated separately for **(1) upload / restricted TestFlight** and **(2) broad TestFlight / public release**.

### 6.2 `dailyspend-quality` agent (`.codex/agents/dailyspend-quality.toml` + `.agents/skills/dailyspend-quality/`)
A broader release QA agent that *calls into* the upgrade-safety skill. It covers the feature-to-test matrix, running suites, a screenshot-based UI/UX critique, and a version report at `docs/releases/<ver>-<build>-QUALITY.md`.

### 6.3 Assessment
- **Strengths:** clear separation of evidence types (source, in-memory, on-disk, device, signed cloud), explicit rules against fabricating results, gate definitions that keep “missing evidence” apart from “known defect”, and hard limits (no uploads, schema deploys, or private-data access). The storage map matches the current code accurately.
- **Gaps / status:**
  1. **It has never produced output.** `docs/releases/` does not exist, so 1.0 (14) has no DATA_SAFETY or QUALITY report yet.
  2. **None of it is committed.** `.agents/`, `.codex/`, `AGENTS.md`, `.github/`, `scripts/`, and the new docs are all untracked.
  3. **Resolved: works in both Codex and Claude Code.** `CLAUDE.md` imports `AGENTS.md`. Thin wrappers in `.claude/skills/` and `.claude/agents/` point to the canonical `.agents/` and `.codex/` files, and `scripts/ci/check_agent_config.py`, which runs in CI, fails on drift.
  4. **There are no historical fixtures yet.** The skill requires a real on-disk store from `build-7` and Build 10 and real old backup files, and none exist in the repo. The `build-7` tag and commit `92528d2` are the obvious sources to build them from.

---

## 7. Code-quality notes (non-blocking)

- Dead code: `Friend.swift` (an `@Model` that is not in the container schema, and was not in the Build 10 schema either), `TestScannerView.swift`, and `DailySpendWidgetLiveActivity.swift` (not in the widget bundle). Removing `Friend` is safe for storage, but the skill asks you to confirm against the shipped schema first.
- `fatalError` fires if both the CloudKit and the local store fail to open. There is no recovery UI.
- Several `print` statements in `RecurrenceHandler` ship in Release.
- Localization is hard-coded `isZh ? … : …` instead of a String Catalog, which limits adding languages.
- Mixed Chinese and English comments. A few force-unwraps in `Date` helpers (`startOfMonth`, `getAllDays`).
- `aps-environment = development` in the source entitlements is normal. Xcode re-signs it for distribution, but the skill rightly asks you to verify the archived entitlements.

---

## 8. Source-inferred risks for the agent to verify

None of these were reproduced. Use them as the first inputs to the upgrade-safety review.

| # | Risk | Where | Why it matters | Suggested check |
|---|---|---|---|---|
| R1 | **Duplicate recurring entries across devices.** Each device runs `RecurrenceHandler` independently and mints children with random UUIDs. Two devices that open on the due date before CloudKit converges can each create the same occurrence. | `DailySpendApp.swift` `RecurrenceHandler` | Inflated totals that look like real data | Two signed devices on a test account; or a deterministic child ID (template ID + date) / dedupe pass |
| R2 | **Duplicate `CategoryBudget` per category.** CloudKit has no uniqueness, and lookups use `.first`. | `Expense.swift`, `CategoryBudgetRow`, `BackupRestorer` | Wrong budget shown; replace-restore validation may reject the user's own backup when a category appears twice | Set the same category budget on two offline devices, then sync |
| R3 | **Old client edits leave stale cents.** Build 10 writes only `amount`. If it edits an expense that 1.0 already backfilled, `amountMinorUnits` keeps the old value and wins on read. | `Expense.money` | Silent wrong amounts in mixed-version households | Old build + new build on one account (already listed in the skill) |
| R4 | **The overall budget and reminder settings don't sync.** They are in `UserDefaults`, while category budgets sync. | `ContentView`, `SettingsView` | Different budgets on iPhone and iPad; widget mismatch between devices | Product decision; document or migrate |
| R5 | **Daily notification amount goes stale.** A repeating `UNCalendarNotificationTrigger` with fixed content only refreshes when the app runs. | `NotificationManager.scheduleDailyNotification` | “You have $X remaining” can be days out of date | Device test: schedule, then add expenses on another device without opening the app |
| R6 | **No recovery UI if the store can't open:** `fatalError` instead. | `DailySpendApp.init` | Crash loop with no path for the user | Fault-injection fixture |
| R7 | **Docs contradict each other.** The `TESTER_DATA_WORKFLOW.md` paste-ready text says “1.0 has been approved”, while the README says it is not an approval announcement. | docs | Tester confusion | Confirm the real App Store status before pasting |

---

## 9. Suggested next steps

1. Commit the agent, CI, and docs scaffolding on a branch so it is versioned.
2. Run the `dailyspend-quality` / `dailyspend-upgrade-safety` workflow for **1.0 (14)** and produce the first `docs/releases/1.0-14-*.md` reports. This includes building `build-7` and Build 10 on-disk fixtures from git.
3. Decide on R1–R4. R1 and R3 are the most likely to cause real data confusion for multi-device users.
4. ~~Add `.claude/` wrappers~~ Done: invoke with `/dailyspend-quality` or `/dailyspend-upgrade-safety` in Claude Code, or `$dailyspend-quality` in Codex.
