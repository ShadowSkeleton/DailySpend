# DailySpend 2.0 — feature plan (phases 1–3; 4–5 moved to later)

Status: agreed plan, not started. Decisions made on 2026-10-26 are marked **Decided**.

## Ground rules for every phase

- **No database change.** No new SwiftData models or fields. New state lives in `UserDefaults` or the existing App Group (`WidgetSnapshot`), never in the store or the backup format.
- **On device only.** Apple Intelligence (Foundation Models) where available; every feature still works without it, using plain rules.
- **The AI never decides an amount on its own.** Amounts come from the user's words or the receipt, checked by code; the model fills in category, merchant, and wording.
- **Nothing is saved without the person seeing it**, except a Siri entry they confirmed out loud.
- **One phase at a time.** Each phase ends with targeted tests, a `DailySpend Test` build on the iPhone, and new rows in `docs/V2_MANUAL_TEST_PLAN.md`. The next phase starts after you've tried it. The full suite runs once, before the 2.0 PR.
- **Writing records from outside the app (Siri, Shortcuts)** goes through the same save code as New Expense, and is reviewed against the upgrade-safety skill's persistence and iCloud sections before it ships.

Order: 1 → 2 (uses 1's reader) → 3.

**2026-10-26:** 2.0 now covers Phases 1–3. Phases 4 (budget pace alerts) and 5 (quick-add widget) moved to a later release; their plans are kept below unchanged.

---

## Phase 1 — Quick add in plain words

**What you get.** At the top of New Expense, a field: *"Describe it — e.g. lunch with Alex 36, split 3"*. Type or use keyboard dictation (no new permission). The form fills in: amount, category, date, note. You review and tap Save, same as a scan.

**How it works.**
- Code reads the parts that must be exact: amounts (`$4.50`, `4,50 €`, `36块`, `¥36`), dates (`yesterday`, `last Friday`, `昨天`, `周五`), and splits (`split 3`, `3 people`, `AA`).
- The on-device model reads category, merchant, and a short note, using the same category guide as scans.
- The amount must appear in what you typed; otherwise the form doesn't fill an amount and says so.
- A split fills **your share** (for example $36 split 3 = $12.00), with "Total $36.00 · split 3" in the note.
- Without Apple Intelligence: amount, date, and split still fill; the category comes from words you've used before.

**Tests.**
- A table of about 60 phrases in English and Chinese: amounts, dates, splits, refusals (no amount).
- Model-backed category checks on the iOS 27 simulator.
- A UI test: type a phrase, then check the form and that nothing saved until Save.

## Phase 2 — Siri, Shortcuts, Spotlight, Action button, Control Center

**What you get.**
| Ask | Result |
|---|---|
| "Log an expense in DailySpend" / "Log $12 coffee in DailySpend" | **Decided:** Siri reads it back ("$12.00, Food, coffee. Save?") and saves on yes, without opening the app. |
| "Scan a receipt with DailySpend" | Opens the app straight to the scanner; you review as usual. |
| "How much have I spent this month in DailySpend?" | Says the month's total and what's left of the budget. |

- The same actions appear in the Shortcuts app and Spotlight, and on the Action button.
- Control Center gets "Scan Receipt" and "Add Expense" controls (iOS 18 and later).
- Siri phrases work in English and Chinese.

**Safety.**
- With App Lock on, anything that reveals amounts needs the iPhone unlocked.
- A Siri entry is saved with the same code as New Expense, so iCloud sync and widgets update as usual.
- Phrases with no clear amount open the app instead of guessing.

**Tests.**
- Unit tests run each action against a separate in-memory store: saves the right record, refuses with no amount, respects App Lock.
- Voice Siri can't be automated, so a short manual checklist on your phone covers it.

**Data-safety review (done 2026-10-26).**
- No schema change.
- Siri writes through the app's own `ModelContainer`, shared with App Intents through `AppDependencyManager`. It never opens a second container on the store or CloudKit.
- The record is identical to New Expense's: new UUID, exact cents, a category from the fixed list, the person's words as the note, not recurring.
- A failed save rolls back.
- The widget is rebuilt from authoritative data, still honoring App Lock privacy.
- Every action that reads or writes spending requires the device to be unlocked.
- Older app versions read these records unchanged.

## Phase 3 — Spending summary in Insights (started as a monthly recap)

**It adds to Monthly Change; nothing about Monthly Change changes.**
- First, tests lock in today's Monthly Change results.
- Then its calculation moves into a shared, tested function with identical output.
- The recap reads from that same function.

**What you get.** **Decided:** from the 1st of each month, Insights shows a card for the month that just ended, with no notification. For example:

> **October in review** — You spent $1,240, 12% more than September. Food rose the most (+$96), mostly from 3 restaurant nights. Your biggest expense was $180 at Hudson Lantern Bistro. You stayed $60 under budget.

**How it stays correct.**
- Code computes every fact first: totals, change against the previous full month, top categories, biggest expense, budget result, number of expenses.
- The model only writes 2–3 sentences from that fact list.
- Every number in its text must match a computed fact. If any doesn't, or there's no Apple Intelligence, a written-by-code version of the same facts is shown instead.
- The recap is cached per month in `UserDefaults`, so it isn't regenerated each time.
- A "Facts" disclosure lists the numbers, with the usual "AI can make mistakes" note.

**Tests.**
- Characterization tests for today's Monthly Change.
- Fact calculations across month lengths, time zones, empty months, recurring expenses, and refunds.
- The number check, run against the model's real output on the iOS 27 simulator.

**Built 2026-10-27.**
- Monthly Change's calculation now lives in `MonthToDateComparison`, with tests at a fixed date. Its output is unchanged, except that ties between categories always name the same one.
- **Changed 2026-10-28:** Insights reads quick look → details → explore. `InsightsGlanceCard` sits above the Trends/Activity switch and always shows this month as one sentence: "October so far: $3,219 less (green) / $219 more (red) than this time last month", then two app-written lines, "You've spent $2,161" / "Shopping is down $3,595". Details holds three tiles and a short summary: every sentence with a number is written by the app (each amount next to what it belongs to), and Apple Intelligence adds at most one sentence with no numbers, shown only if it names categories from this period and agrees with every up/down in the facts (`RecapText.isSafeInsight`). The period buttons sit on the Spending Trend graph, whose header shows the selected period's total and change.
- **Comparison rules (`SpendingPeriod`, `PeriodRecap`):** whole days (the 1st through today against the 1st of last month through the same day, and a shorter month stops at its last day). There's no comparison unless the records reach into the first half of the earlier period, so starting partway through a month isn't "more than nothing". No percentage in the first 3 days or past +300%; the amount still shows. The named category is always the one that moved the total, and a bigger move the other way is mentioned. Expenses dated later this month aren't counted yet; Details names their amount, so it reconciles with Home. This intentionally differs slightly from 1.0's Monthly Change, which compared to the exact time of day.
- The facts come from `PeriodRecap`, the code-written summary is `RecapText.summary`, and the model's paragraph is shown only when `isFaithful` passes.
- The wording is cached in `UserDefaults`, one entry per period button and per past month, under a versioned signature.

## Later — Phase 4: budget pace alerts (moved out of 2.0)

**What you get.**
- **Home:** a line under the budget card, "On pace for about $1,380 by Oct 31".
- **Daily notification:** **Decided:** on for people who already get the daily budget notification, as one extra line, "On pace to pass your Food budget around the 24th". No new notification type. A Settings toggle turns it off.

**How it works.**
- Pace = spending so far ÷ days so far × days in the month.
- Recurring expenses still to come this month are added exactly rather than extrapolated.
- It stays quiet in the first 5 days of a month and when the projection is within 5% of the budget.
- Each category alerts at most once a week; the last-sent date is kept in `UserDefaults`.
- It covers the overall budget and each category limit.

**Tests.** Projection math for 28–31-day months, the first days, daylight saving, a zero budget, recurring expenses, and the quiet rules. Notification text in both languages.

## Later — Phase 5: quick-add widget (moved out of 2.0)

**What you get.** The existing small Quick Add widget becomes interactive (iOS 17+). It shows your 3 most frequent expenses, such as "$5 Coffee · Food", plus a "+" button.
- **Decided:** tapping one opens New Expense filled in, and you tap Save. A stray tap never creates a record.
- New Lock Screen widgets: a "+" circle, and "Spent today / left this month".

**How it works.**
- The app works out the shortcuts (same name, category, and similar amount, seen at least 3 times) and writes them to the App Group snapshot the widgets already use.
- The widget only reads that snapshot.

**Tests.**
- Unit tests for picking the shortcuts.
- Rendering checks of each widget size in the simulator.
- A UI test that opening a shortcut link fills New Expense and saves nothing on its own.

---

## Later (2.1, needs a database change)

Saving receipt line items or the photo with an expense; tags; a separate currency per expense; who-owes-whom history after a split.

## Later (2.x, before April 2027): designed for iPhone Duo

2.0 is built with the iOS 27.1 SDK, so it already fills the open iPhone Duo
edge to edge; the 2.0 review checked it works there (closed, open, and
turned) without Duo-specific design. Before April 2027, when App Store
submissions need iPhone Duo screenshots:

- Two panes on the open display: the transaction list beside the editor,
  Insights' quick look beside the charts, Split Bill's items beside the shares.
- Keep key controls off the fold (in landscape it runs down the middle), using
  the 27.1 fold-region APIs; react to the hinge where it helps.
- Duo screenshot set (outer 1398 × 2034, inner 2007 × 2853) and the
  "optimized for iPhone Duo" badge.
