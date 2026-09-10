# DailySpend App Store release checklist

Use this for the signed distribution build. It does not replace a real-device
TestFlight pass.

For step-by-step scenarios, edge cases, exact expected results, and separate pre-upload/post-upload gates, use [PRE_UPLOAD_TEST_PLAN.md](PRE_UPLOAD_TEST_PLAN.md).

## Protect current testers before updating

- Ask testers to keep a current encrypted backup and its passphrase separately, and to confirm iCloud
  sync is healthy before installing the release candidate.
- The money update is additive: it only fills a new optional cents field and
  leaves every existing stored `Double` amount unchanged. If the backfill is
  interrupted, DailySpend continues reading the original amount.
- Test an upgrade over an existing TestFlight build on a real device. Confirm
  past expenses, category budgets, recurring templates, and recorded split shares
  are still present. Unrecorded split drafts/receipts are not persistent data.

## Final owner acceptance checklist — updated September 10, 2026

Check these on the exact signed TestFlight build, not only in Xcode. Current source version: 1.0 (14). If build 14 was already uploaded, use an unused higher build number before archiving.

- [ ] Back up before upgrading; do not uninstall. Compare expense count, exact totals, category budgets, and recurring entries before/after the update.
- [ ] Confirm the app, About page, widget gallery, Home Screen, and tester message all say **DailySpend**. About should show Jackson Feng, the support email, and the installed version/build.
- [ ] Keep the existing app bundle ID, private iCloud container, App Group, and widget kinds unchanged. Their legacy internal identifiers preserve access to installed data and widgets; they are not display names.
- [ ] Create, edit, delete, and relaunch with sample expenses. Check cents, dates, monthly totals, budgets, and recurring entries for duplicates. Repeat offline and after reconnecting.
- [ ] Test Quick Split and By Item with $0.01, uneven shares, custom/fixed tips, long amounts, and invalid input. Confirm the currency symbol stays next to the amount and split totals reconcile.
- [ ] On every numeric input, dismiss the keyboard, tap the field to reopen it, scroll interactively, and use an external keyboard if available. Check that Save/Cancel/Record remain reachable.
- [ ] Open About, Add/Edit Expense, receipt sharing, backup export, and restore with one tap. Try again after dismissing, switching tabs, and backgrounding. No blank or duplicate sheet should appear.
- [ ] Check a compact iPhone and an iPad, portrait/landscape, light/dark appearance, the largest accessibility text size, VoiceOver, Increase Contrast, and Reduce Motion. Check English, Chinese, and a decimal-comma region.
- [ ] Add Quick Add and dashboard small/medium widgets. Check standard, dark, tinted, and clear appearances; no missing plus symbol, overlap, clipped amounts, or inaccessible labels.
- [ ] Compare widget amounts **including cents** with the current month in Home. Edit amount/date, delete a record, change budget, background, and reopen. Allow iOS time to refresh.
- [ ] Test widgets with no data, budget off, zero budget, overspending, a very large amount, midnight/month rollover, and an app that has not opened that day. Old data must show a refresh prompt, not a misleading “This Month” amount.
- [ ] Tap Quick Add with the app terminated, in the background, and last on Settings/Insights. New Expense must open once. Dashboard must open Home. Existing edit drafts should not be silently discarded.
- [ ] Enable App Lock. Check Face ID/Touch ID/passcode success, cancellation, and retry. Repeat with an expense sheet, share panel, and Files picker open. Inspect the app-switcher thumbnail and VoiceOver: no financial content should escape the shield.
- [ ] With App Lock enabled, confirm widgets hide amounts after refresh and widget links wait for authentication. iOS can retain a prior rendered widget temporarily; remove it for immediate privacy. Disabling App Lock should restore the current widget snapshot after refresh.
- [ ] Create an encrypted backup and save it outside the app. On a spare device, verify correct-passphrase restore, wrong-passphrase rejection without changes, duplicate-safe merge, and cancel/confirm replacement after saving the required safety backup. Compare counts and cents afterward.
- [ ] Check CSV export separately. CSV is readable, unencrypted, and not a full settings/recurrence backup. iCloud sync is not an independent recovery history: deletions can sync too.
- [ ] Complete the signed two-device iCloud, camera, notifications, archive, and metadata checks below before distributing broadly.

Copy-ready tester message: [TESTFLIGHT_NOTES.md](TESTFLIGHT_NOTES.md).

Widget refresh/privacy timing follows [Apple's WidgetKit timeline guidance](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/); a reload request is not a guarantee of an immediate screen update.

## Required real-device tests

- Sign in to iCloud, create an expense on one device, and verify it arrives on
  a second device using the private CloudKit database.
- Test receipt scanning after accepting the camera permission.
- Turn on App Lock, background the app, return to it, and verify both the
  app-switcher shield and device-authentication flow.
- Create an encrypted backup, restore it with the right passphrase, and make
  sure a wrong passphrase does not import anything.
- Exercise replacement restore: save the required safety backup, then cancel
  and complete the final confirmation separately.

## Apple signing and services

- Archive with the distribution signing profile for `com.jackson.LoveLedger`.
- Confirm the archive’s entitlements use the production APS environment and
  include `iCloud.com.jackson.LoveLedger` plus
  `group.com.jackson.LoveLedger`. Let Xcode and the distribution provisioning
  profile provide the production APS value; do not hand-edit it for release.
- In CloudKit Dashboard, deploy the tested development schema to Production
  before the App Store build can create production records.

## App Store Connect metadata

- App name: `DailySpend`.
- Support email: `jacksonfeng0130@yahoo.com`.
- Publish the static policy in this repository using `docs/README.md`, then
  add the public HTTPS `/privacy/` URL to both App Store Connect and the app’s
  support materials.
- Complete App Privacy from the actual shipped build. With the current code,
  no data is sent to the developer, ads, analytics, or third parties; confirm
  this remains true before selecting “Data Not Collected.”
- Upload final iPhone screenshots and ensure they use DailySpend branding
  consistently.
- Use the new mint/teal wallet icon in the selected build and store materials. Provide final iPad screenshots too; the app supports iPad.
- Confirm the final store title (recommended: `DailySpend - Smart Split`) and subtitle (`Expense Tracker & Budgets`) in App Store Connect. Keep the Home Screen name `DailySpend`.

## Submission gate

- Build and test a Release archive, not only a simulator Debug build.
- Keep a copy of the exact archive and the matching privacy-policy version.
- Do not submit until the signed CloudKit, camera, backup/restore, and App
  Lock checks above have passed on a physical device.
