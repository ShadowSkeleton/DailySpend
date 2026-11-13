# Changelog

Versions as submitted to the App Store. Build numbers are the ones uploaded to
App Store Connect; check there for what is actually live.

## 2.0 (17)

**Snap it. Say it. Split it. See it.** DailySpend 2.0 takes the typing out
of expense tracking. Everything runs on your iPhone.

### New

- **Scan a receipt.** Tap the scan button on Home, or pick a photo. On
  devices with Apple Intelligence, Apple's on-device model reads the store,
  date, items, tax, tip, and total; DailySpend checks the arithmetic and
  fills a New Expense form for you to review. Other devices still read the
  total.
- **Split from a receipt.** Quick Split takes the total and any tip; By Item
  takes every line, tax, and tip. Tap names on an item to choose who shares
  it; "2 × Dumplings" becomes two lines so different people can take each.
- **Quick Add in plain words.** Type "Lunch with Alex 25" or "昨天打车 23 块"
  and the amount, category, date, and any split fill in.
- **Siri, Shortcuts, and Controls.** Log an expense, scan a receipt, or ask
  what you've spent this month. Scan Receipt and Add Expense controls for
  Control Center, the Lock Screen, and the Action button.
- **Insights quick look.** This month against the same days last month, in
  one sentence, with Details for the exact numbers.
- **A one-time tour** of what's new, with a Back Up Now button for people
  who already have data.

### Improved

- New Expense keeps the categories right above the number pad while you type
  an amount (TestFlight feedback on build 16).
- After a scan, DailySpend reminds you that a fresh scan of the whole receipt,
  flat and in good light, usually fixes a misread.
- A "None" tip option and a combined Custom tip (% or fixed); the currency
  symbol beside the amount; a reset icon for starting a new split.
- Tilted photos are straightened; Chinese receipts are read with automatic
  language detection; store and pharmacy receipts get no restaurant tip.
- Chinese text for strings that were English-only.

### Fixed

- Category Limits no longer rounds a saved limit with cents to a whole number.
- The "Add your first expense" button shows its plus icon again.

### Data

No stored data format changed: expenses, budgets, backups, and iCloud records
use the same fields as 1.0. Receipt images and text are never stored or sent
anywhere. Reviews: [quality](docs/releases/2.0-17-QUALITY.md),
[data safety](docs/releases/2.0-17-DATA_SAFETY.md).

## 1.0 (14) — September 2026

- **New wallet branding:** a mint/teal wallet icon and a refreshed About page.
- **More dependable editing:** full-card transaction tap targets and
  coordinated Add/Edit presentation; widget Quick Add waits for an open edit.
- **Clearer transaction rows:** red destructive swipe actions, multiline
  notes, and natural recurring labels.
- **Better split receipts:** shared subtotals expand into each person's item
  amounts with participant names; long names wrap; tall receipts export
  reliably.
- **Polished amount entry:** the currency symbol beside the bill amount, a
  keyboard dismiss action, and decimal-comma input that keeps cents.
- **Widgets and privacy:** exact-cent snapshots, clear empty and stale states,
  and hidden balances when App Lock is on.
- **Safer data handling:** validated backup imports, replacement-restore
  safeguards, CSV formula protection, and rollback of failed recurring saves.
