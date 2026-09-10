# DailySpend — TestFlight notes

Final testing candidate, updated September 10, 2026: version 1.0, build 14 in this checkout. Confirm the actual uploaded build number in App Store Connect; this document does not establish that a build was uploaded or approved.

## Copy-ready “What to Test”

Thanks for testing the latest DailySpend update!

This update focuses on stability, clearer layouts, and keeping your financial data safe:

- New mint/teal wallet app icon and matching branding in the refreshed About page.
- Red swipe-to-delete actions, full-card transaction tap targets, and coordinated Add/Edit presentation.
- Natural recurring labels and expanded transaction notes without repeated equal-share wording.
- Shared receipts now show each person's allocated item amounts and actual participant names, with wrapping for long names and improved tall-image exports.
- Refined Quick Split amount layout: the currency symbol now sits directly beside the number.
- Improved split-bill stability and exact-cent calculations, including decimal-comma input.
- Updated Home Screen widgets with cents, clearer budget labels, better contrast, and honest refresh/empty states.
- Improved widget navigation: Quick Add opens New Expense, and the dashboard opens Home.
- Stronger App Lock protection for open sheets and widget balances.
- Improved backup validation, safer CSV exports, and updated About DailySpend information.

Please try these first:

1. Upgrade without deleting the app. Check your existing expenses, totals, budgets, and recurring entries.
2. Enter and edit expenses, dismiss and reopen the numeric keyboard, and try Quick Split and By Item. Check that every cent is accounted for.
3. Add Quick Add and both dashboard widget sizes. Check their amounts against Home; edit or delete an expense and check again. Tap them after closing the app and while another tab was last selected.
4. Open About, expense sheets, and share/backup panels with a single tap. Look for blank panels, overlap, clipped text, or a need to tap twice.
5. Enable App Lock, leave an expense sheet open, then background and reopen DailySpend. Confirm financial content stays hidden until authentication. Widgets should hide balances after iOS refreshes them.
6. Create an encrypted backup and test restore on a spare/test device. Never use your only copy of important data for a replacement-restore test.

Widget refresh timing is controlled by iOS. Open DailySpend to refresh older data. If you need an existing widget hidden immediately after enabling App Lock, remove the widget while iOS processes the refresh.

Please send issues through TestFlight feedback. Include your device, iOS version, build number, exact steps, expected result, and a screenshot or screen recording with personal financial information hidden. For crashes, note the approximate time. Contact: jacksonfeng0130@yahoo.com.
