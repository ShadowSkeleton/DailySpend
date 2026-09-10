# DailySpend — owner test plan before App Store Connect

Prepared September 5, 2026. Candidate in this checkout: **1.0 (14)**; record the actual build you test.

These are **acceptance criteria, not a claim that every case already passed**. Earlier automated results are in the [final audit](../audit/final-polish-2026-09-04/REPORT.md). Complete the unchecked hardware tests yourself.

This is a recommended beta-safety plan, not a list of tests Apple individually requires. Prioritize the unproven areas: **P01–P05 (real authentication/window privacy), W01–W09 (installed widgets), B03–B07 (recovery), and R02/R04 (month-end and two-device recurrence)**.

## How to use this list

1. Complete **A: device testing** and **B: archive checks** before uploading.
2. Upload for **your own/internal validation**, then complete **C: TestFlight verification** before inviting the wider tester group. The actual processed TestFlight package cannot be tested before upload. This separation follows [Apple's TestFlight workflow](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).
3. Mark each ID **Pass / Fail / Blocked / Not applicable**, with device, iOS, build, and evidence. A test you could not run is **Blocked**, not Pass. “Not applicable” needs a reason.
4. **Stop for:** crashes, missing/duplicate records, incorrect cents, failed recovery, private content exposed before authentication, inaccessible core actions, blank sheets, or an unusable supported device. Minor cosmetic defects may be disclosed in beta notes only if no data, privacy, accessibility, or task-completion impact exists.

### Safe setup

- Use a spare/test device and test-only financial records. Use a separate test Apple Account for destructive iCloud, replacement-restore, and account-change tests; a spare device signed into your everyday account can still sync deletions to your other devices.
- Before the upgrade test, save an encrypted backup **outside the app**, keep its passphrase separately, and verify the file exists. Prefer verifying it on a spare device before relying on it. CSV and iCloud sync are not substitutes for a recoverable full backup.
- Never uninstall your only copy of the app for a “fresh install” test. Fresh-install and upgrade tests use different test installations.
- Run normal app tests without Xcode UI-test launch flags or demo seeding. Test a device-installable Release configuration from the same source revision you plan to archive, with normal signing/capabilities and the debugger detached.
- Do not change the clock on your everyday device. Use an isolated simulator/test device for date-boundary tests; do not use that result as proof of production cloud synchronization.

### Coverage to record

| Dimension | Required coverage / expected outcome |
| --- | --- |
| Hardware | At least one physical iPhone. Include a compact phone, a larger phone, and an iPad if the uploaded build supports iPad; simulators can supplement hardware. |
| OS | Oldest supported major version (the project currently targets iOS 17), the iOS 26.3 crash-report environment where available, and the newest version used by your testers. Record unavailable coverage explicitly. |
| Install history | Fresh test installation and upgrade over the previous distributed build, without deleting the app. |
| Appearance | Light, dark, largest accessibility text, portrait; landscape and iPad resizing where supported. Widgets: ordinary, dark, tinted, and clear where the OS offers them. |
| Input/accessibility | Touch keyboard, keyboard hide/reopen, VoiceOver; hardware keyboard and iPad pointer if those devices are in the test group. |
| Language/region | English, Chinese, and one decimal-comma region such as German/Germany. Restore the original settings afterward. |
| Connectivity | Online, offline/Airplane Mode, and reconnect; iCloud signed in and unavailable on separate test setups. |

## A. Test on devices before uploading

### A1. Installation, launch, and existing data — must pass

| ID | What to do / edge case | Expected result |
| --- | --- | --- |
| L01 | Fresh-install on the spare test setup, open once, close, and reopen 5 times. | DailySpend opens on the first tap, without a crash, blank window, demo records, or a setup loop. Empty-state Add Expense and Split Bill actions work. Existing cloud records may populate if this test account already has data; that is not a truly empty-data case. |
| L02 | On the old build, record expense counts/totals by month, category budgets, recurring entries, and several distinctive notes. Upgrade **without uninstalling**. | Records, IDs/identity, cents, dates, categories, notes, and recurrence state survive. No duplicate history or reset to an empty database. Unrecorded split drafts are not promised persistent records. |
| L03 | After a successful save, immediately background/terminate and reopen. Also open offline. | The successfully saved record remains exactly once. Offline launch still exposes local data; network trouble does not erase history or trap the app at launch. |
| L04 | With a backed-up, test-only large history, open Home/Insights, change months, scroll, and return from background. | No crash, frozen controls, empty financial summary caused by a render failure, or lost records. Record launch/interaction times and compare with the previous build on the same device; a substantial regression needs investigation. |
| L05 | Repeat the original crash journey: Quick Split → By Item → add/remove people/items → share/cancel → reset → change tabs, 10 times. | No crash, corrupted participant/item state, or accumulating duplicate sheets. Record the time and steps if any crash recurs. |

### A2. Money and record integrity — must pass

Use a **fresh test dataset**, no recurrence, all entries dated in the current month, and a monthly budget of **50.00**. Follow D01–D04 in order. Do not reuse this dataset for other tests until you have recorded its results.

| ID | What to do / edge case | Expected result |
| --- | --- | --- |
| D01 | Add 10.00, 20.25, 0.10, and 0.20, each with a unique note. | Exactly **4 records**, monthly total **30.55**, remaining budget **19.45**. Home, Insights for the same period, and refreshed widgets agree to the cent. |
| D02 | Edit the 20.25 entry to 25.30. | Still **4 records**, total **35.60**, remaining **14.40**. The old amount does not remain as another record. |
| D03 | Delete the 0.10 entry; cancel once, then confirm. | Cancel changes nothing. Confirm leaves **3 records**, total **35.50**, remaining **14.50**. Relaunch preserves that state. |
| D04 | Move the 25.30 entry into the previous month, then switch monthly views. | Current month becomes **10.20**; previous month gains **25.30**. All-time record count stays **3**. Insights and refreshed widgets use the correct period. |
| D05 | In Add/Edit and split item/total fields, try blank, 0, negative input, 12.345, letters, repeated decimal separators, and an amount above 1,000,000,000,000. | Invalid positive-expense values cannot be saved/settled as valid money; the app stays usable and does not silently save zero, truncate junk into a number, or overflow. Clear feedback or a disabled action is acceptable. A zero **budget** is a separate case below. |
| D06 | Save a valid 0.01 expense and a long but valid amount; edit and relaunch. | Exactly the entered cents persist. No lost decimal digits, exponent/garbled display, or covering of Save/Cancel. |
| D07 | In Quick Split with German/Germany region, enter `12,50` and `1.234,56`; with US region, paste `1,234.56`. | Values mean **12.50**, **1234.56**, and **1234.56** respectively. A malformed US `12,50` must not silently become 1250. Repeat localized entry in normal expense fields. |
| D08 | Use a long note containing commas, quotes, line breaks, emoji, and Chinese. Save, edit, reopen, and export. | Text is preserved; the list may abbreviate it, but editing shows the full note. Layout remains usable. Export does not split one record into extra columns. |
| D09 | Tap Save twice quickly; separately open Edit, change values, and cancel. | One deliberate save creates one record. Cancel leaves the original stored record unchanged. An in-progress operation must not lead to duplicate commits. |
| D10 | Change a record's category. Set total/category budgets; toggle budget off/on. Test 0, exactly spent, and overspent. | Category totals move rather than duplicate. Budget toggling changes budget presentation, not recorded spending. Zero budget causes no division error. For budget 50 and spending 55.25, overspending is clearly **5.25**, not a misleading positive “remaining” balance. |
| D11 | Add a future-dated expense; view its month, current month, and the last-seven-days trend. | It appears only in the appropriate monthly period. Future days do not appear in the trailing seven-day chart. An explicitly future-dated entry within the current month may count in that month's total; this must not be mistaken for “spent through today.” |

### A3. Split bills — must pass

Turn off tips for the base examples by selecting **Custom % = 0**. Do not use an invalid zero-valued fixed-tip field to mean “no tip.”

| ID | What to do / edge case | Expected result |
| --- | --- | --- |
| S01 | Quick Split 10.00 among 3 people, no tip. | One share is **3.34** and two are **3.33**; sum **10.00**. The app explains the uneven cent instead of claiming everyone pays an identical amount that does not reconcile. |
| S02 | Split 0.01 among 3 people; separately reduce the participant count to 1 and tap minus again. | Shares sum to exactly **0.01**; zero-cent shares do not become fake positive expenses. People never becomes 0 or negative; minimum-count control is disabled. |
| S03 | Split 10.00 among 3 with 15% tip; then use a fixed 2.00 tip. | First total **11.50**, allocated **3.84 + 3.83 + 3.83**. Fixed-tip total **12.00**, **4.00 each**. Changing tip mode does not add both tips. |
| S04 | By Item: two people share a 10.00 item; set tax 1.00 and Custom % = 0. | Grand total **11.00**, **5.50 each**. No item/tax is counted twice. |
| S05 | Assign a shared item to nobody; remove a participant involved in shared items; use duplicate display names. | An unassigned shared item blocks settlement with actionable guidance. Removed people leave no orphan allocations. People are distinguished by identity, not accidentally merged because their names match. |
| S06 | Add/edit/delete personal and shared items; change tax/tip repeatedly; try negative/invalid values. | Participant totals always sum to the displayed grand total in cents. Invalid money blocks completion; it never becomes a silently accepted adjustment. |
| S07 | Share/cancel a receipt; use Record My Share, cancel once, then save once. | Receipt matches the displayed split and is not blank. Sharing/cancelling alone creates no expense. Recording creates exactly the chosen share once, not the whole bill or every person's share. |
| S08 | Enter a long total, open the keyboard, hide it, and rotate/resize where supported. | The currency symbol stays immediately beside the number. No symbol at the opposite card edge, overlapping digits, clipped controls, or off-screen primary action. |

### A4. Keyboard, gestures, and first-tap windows — must pass

Repeat these in **Add Expense, Edit Expense, Quick Split, By Item, budget fields, and backup passphrase sheets**, wherever the relevant input/action exists.

| ID | What to do / edge case | Expected result |
| --- | --- | --- |
| U01 | Tap a numeric field, enter a value, tap the keyboard-dismiss button **once**, then tap the field again. Repeat 5 times. | Keyboard opens, hides on one tap, and reopens on the next field tap. Typed value remains correct. No need to double-tap, switch tabs, or reopen the sheet. |
| U02 | Scroll while the keyboard is open; move between numeric, note, percentage, and passphrase fields. | Focus follows the selected field. Interactive dismissal works on scrolling forms that support it. No stuck keyboard, hidden input, duplicated dismissal toolbar, or Save button collision. |
| U03 | Immediately cancel a newly opened expense sheet before its autofocus delay finishes; reopen it. | A cancelled sheet does not later raise an orphan keyboard or obscure Home. Reopening focuses the live form normally. |
| U04 | Open About, Add/Edit, receipt share, encrypted export, and restore. Dismiss and repeat 5 times, including after backgrounding. | Each opens on the **first deliberate tap**. No blank panel, stale previous content, duplicate panel, or requirement to tap twice. Loading is distinguishable from a missing window. |
| U05 | Use Back and left-edge back-swipe on pushed pages; swipe down a dismissible sheet; cancel a dirty form; switch tabs. | Native navigation behaves predictably. Cancel/dismiss never saves an unwanted transaction. No gesture bypasses replacement-restore confirmation. Explicitly cancelled/dismissed drafts need not survive; backgrounding or unlocking an open sheet must not silently discard its fields. |
| U06 | On iPad, open share/export panels, rotate, resize, and use keyboard/pointer. | Popovers have an anchor and remain visible; no presentation crash. Tab navigation adapts, content reflows, and dismiss/confirm actions remain reachable. No portrait lock is a failure if that orientation is intentionally unsupported. |
| U07 | Use the largest accessibility text size, long content, VoiceOver, Increase Contrast, and Reduce Motion. | No overlapping/clipped required content; scrolling reaches every action. VoiceOver names controls and amounts meaningfully, focus order is usable, and focus returns after dismissal/unlock. Color alone is not required to understand overspending. |
| U08 | Repeat Home/Split/Insights/Settings/About in English and Chinese, light and dark modes. | No raw localization keys, unreadable text, mixed-up numbers, broken layouts, or old display branding. Currency/region formatting is consistent; changing region must not perform an unexplained numerical currency conversion. |

### A5. App Lock and privacy — must pass on physical hardware

| ID | What to do / edge case | Expected result |
| --- | --- | --- |
| P01 | Enable App Lock, background, and reopen. Authenticate successfully with the available device method. Repeat 5 times. | Financial content stays protected until authentication. Success removes the shield once; tabs, text fields, touch, and VoiceOver work afterward. No persistent blank/untouchable window or repeated successful-authentication loop. |
| P02 | Cancel/fail authentication, then retry. Test the OS-provided passcode fallback. | No financial content or edit action is exposed while authentication is incomplete. Cancellation leaves a usable locked/retry state. Do not remove the device passcode from your everyday phone for this test. |
| P03 | Leave an Add/Edit sheet containing a distinctive private note open. Background, inspect the app switcher, reopen, and unlock. Repeat with share/export and Files import panels. | App-owned financial content is shielded in the thumbnail and while locked, including accessibility. After successful unlock, the open draft remains usable with its fields intact. No stranded shield or invisible sheet steals touches. |
| P04 | Tap the Quick Add widget while DailySpend is locked. | Authentication comes first. No expense form or Home actions are accessible before success. After success, New Expense opens once. |
| P05 | Enable App Lock with widgets installed; later disable it deliberately while unlocked. | After iOS refreshes the widget, it shows a hidden-amounts state, with no totals or trend values. Disabling restores current data after refresh. Already rendered widget snapshots may persist temporarily; remove widgets for immediate privacy. |
| P06 | On a spare device with no usable device authentication, attempt to enable App Lock. | Clear “unavailable” feedback; the setting does not pretend protection is active or permanently strand the person. |
| P07 | Enable reminders and inspect a notification while locked under iOS “Show Previews: When Unlocked.” | Notification previews obey the OS setting. **App Lock is not a promise to erase existing notifications or override “Always” previews.** If a budget preview is unacceptable, change preview settings or disable reminders before testing with private values. |

### A6. Widgets — high-priority manual coverage still outstanding

Test **Quick Add (small)** and **Dashboard (small and medium)**. Dashboard small may show remaining/overspent budget; medium shows monthly spending. They need not show the same headline number when budgeting is enabled.

| ID | What to do / edge case | Expected result |
| --- | --- | --- |
| W01 | Add each widget from the gallery; use a first-install setup that has not opened DailySpend. | Gallery says DailySpend and uses sample preview data, not private balances. An installed dashboard without a valid app snapshot gives an open/load instruction rather than misleading sample spending. Opening the app populates real test data after refresh. |
| W02 | Use a separate dataset totaling **94.94** with budget **650.00**. | Small dashboard says remaining **555.06**; medium monthly total **94.94** and budget remainder **555.06**. Cents remain visible; currency symbols sit beside their numbers. |
| W03 | Edit amount/date, delete a record, change/disable budget, immediately background, then reopen. | After a timeline refresh, widget values agree with the app and the correct month. No mixed old/new budget and spending, even when editing an existing record rather than adding one. |
| W04 | Try no expenses, budget off, budget 0, exact budget, overspending, and very large values. | Meaningful empty/zero states; no divide-by-zero, NaN, negative progress width, overlapping text, or a negative balance ambiguously labeled “remaining.” Large amounts stay understandable. |
| W05 | Leave the app unopened across midnight and a month boundary. Then reopen it. | When the scheduled widget entry/update is rendered, stale data asks for refresh; it does not relabel last month's spending as this month. After opening DailySpend and refreshing, chart days and month totals match current app data. |
| W06 | Inspect all sizes in ordinary, dark, tinted, and clear modes where available; also large text/VoiceOver. | Plus icon remains distinguishable, charts/text are readable, corner margins are safe, and nothing overlaps. Accessible descriptions identify the action/amount/budget state. |
| W07 | Tap Quick Add with the app terminated, backgrounded, and last on Settings/Insights. Tap Dashboard separately. | Quick Add opens exactly one New Expense sheet; Dashboard opens Home without an unwanted Add sheet. Each needs one tap. |
| W08 | Tap Quick Add while an Edit Expense draft is already open; repeat the link twice. | Existing edits are not silently discarded or overwritten. No competing/doubled sheet. The pending Add request is handled once when the edit presentation safely ends. |
| W09 | Put two dashboard instances on the Home Screen, change an expense, and revisit them. | Both converge to the same underlying snapshot after their refreshes. Differences in system refresh timing do not change stored data. |

For W03/W05/W09, note the app-save and widget-update times. There is **no fixed immediate-refresh guarantee**. Reopen the app, wait for a timeline update, and retry; persistent disagreement after a confirmed refresh is a failure. Apple's scheduling caveats are documented in [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/).

### A7. Backup, restore, and CSV — must pass with disposable data

| ID | What to do / edge case | Expected result |
| --- | --- | --- |
| B01 | Back up a known test dataset including several months, category budgets, recurring entries, and settings. Use a passphrase of at least 12 characters; save to Files outside the app. | A non-empty encrypted file is actually saved and can be selected again. Expense notes/records are not readable as plain JSON. Record the fixture's counts, cents, and settings separately. Keep the passphrase private. |
| B02 | Try an 11-character passphrase; separately cancel passphrase entry and cancel the Files exporter. | Short passphrase is rejected. Cancellation changes no data and does not claim a backup was saved or allow destructive replacement on that assumption. |
| B03 | Restore with a wrong passphrase; try a damaged/truncated copy, unrelated JSON, unsupported-version file, and a file larger than 25 MiB. | Clear rejection, no crash, no partial import, and unchanged records/settings. Use copies/test fixtures only; keep the original backup intact. |
| B04 | Safe Merge the same current-format backup twice into an overlapping dataset. Change one local record before merging. | Missing records are added once. Matching local records, their local edits, and current settings are preserved. Second import adds no duplicates. |
| B05 | Choose Replace; cancel before saving the safety backup, then separately cancel the final replacement confirmation. | Neither cancellation deletes/replaces anything. A saved safety backup and explicit final confirmation are required before replacement. |
| B06 | On the disposable setup, complete Replace from the known backup. Reopen afterward. | Expense count, IDs/identity, dates, notes, exact cents, category budgets, and backed-up budget/reminder settings match the source. No records from the replaced dataset remain unless also in the backup. App Lock, OS permissions, and iCloud login are not expected to be restored from this backup. |
| B07 | Restore the safety backup created before B06. | The pre-replacement test dataset is recoverable. If you cannot recover it, stop distribution even if export displayed “success.” |
| B08 | Import a genuine older unencrypted JSON backup if you support existing users with that format; inspect recurring entries after relaunch. | Supported legacy data imports without destructive surprises or an explosion of historical recurring duplicates. Missing old-format settings are not fabricated. If no legacy fixture is available, record this coverage as Blocked. |
| B09 | Simulate unavailable/cloud-only Files access or a failed export/import on a spare setup. | A useful error/cancel state appears; no false success and no data mutation from an incomplete import. Do not deliberately fill your everyday device's storage. |
| B10 | Export the current month's CSV. Include a note with comma, quote, line break, emoji, and the harmless formula text `=1+1`. Open in a text editor and Numbers/Excel. | Four columns remain Date/Category/Amount/Note; one data row per selected-month expense, even with quoted newlines. Amounts keep cents; dates are unambiguous. Formula-like text stays text rather than evaluating to 2. A protective leading apostrophe is acceptable. CSV contains no unrelated months. |

### A8. Recurrence, scanning, notifications, and cloud — must pass for the beta's supported features

| ID | What to do / edge case | Expected result |
| --- | --- | --- |
| R01 | Create daily/weekly/monthly test recurring entries with known due dates. Reopen several times after an occurrence becomes due. | Each due occurrence is created exactly once, with the correct cents/category/date. Generated children do not create more children. Reopening does not duplicate already processed occurrences. |
| R02 | On the isolated date-test setup, use a monthly entry anchored on January 31; advance past February and March. Also test a daylight-saving transition and a future-starting recurrence. | Month-end recurrence must not stop after February: for a January-31 anchor, expect February's last valid day and March 31. No duplicated/skipped daily occurrence around DST. Future-starting entries do not generate children early. A different intended month-end policy must be explicitly decided and documented, not treated as a pass by accident. |
| R03 | Restore recurrence history, then reopen twice. For a test fixture with years of overdue daily entries, reopen repeatedly. | No repeated already-processed occurrences. Large catch-up remains responsive and continues safely across launches; current implementation batches at most 366 generated occurrences per launch, so immediate full catch-up is not required. |
| R04 | On two test devices sharing the same test iCloud account, let the same recurrence become due; reconnect if either was offline. | Final history contains one occurrence per intended schedule, not one per device. Any duplicate must be investigated before wider distribution. |
| C01 | Camera: allow permission, deny it on a separate test setup, cancel capture, and scan a blurry/non-receipt image. | No crash or blank trap. Denial/cancel leaves manual entry available. Recognition failure is understandable and does not automatically save an invented amount. |
| C02 | Scan a receipt with subtotal 89.00, tax 7.34, total 96.34. Scan another with total 1,199.00 and grand total 1,224.50. | Suggested amount is **96.34** and **1224.50** respectively. User can review/correct the amount before saving. Camera capture stops when dismissed. |
| N01 | Allow reminders, schedule shortly ahead with a budget state that meets the reminder condition, then change time and disable reminders. Also test denied permission. | One applicable reminder at the configured time; changing time does not leave duplicates, and disabling cancels future scheduled reminders. Denied permission does not prevent normal use or produce repeated permission prompts. |
| I01 | With two test devices in the **same CloudKit environment/account**, create, edit, move month/category, then delete a uniquely named test expense. | Both eventually agree on one record, exact cents, and its final state; deletion does not resurrect. “iCloud available” alone is not proof of sync—verify actual records. |
| I02 | Create different records offline on both devices, reconnect, and reopen. | Both records eventually appear on both devices once; no loss or duplicates. Local records remain usable while offline. |
| I03 | Edit the same record on both devices while offline; reconnect and inspect. | Both converge to a single consistent record without corruption. Do not assume both conflicting edits can survive or that a specific device always wins; document the observed conflict behavior and any surprising lost edit. |
| I04 | On a separate test setup, use unavailable/signed-out iCloud or restricted network. Reopen and inspect status. | Local data is preserved and usable. Status does not falsely assert completed sync. Returning connectivity/account availability allows sync to resume; there is no permanent blank launch. |

## B. Archive and App Store Connect pre-upload checks

These are preparation checks, not authorization for an automatic upload or production schema change.

| ID | What to check | Expected result |
| --- | --- | --- |
| A01 | Inspect app icon/name, About, widget gallery, and support information. | Display name **DailySpend** throughout. About shows the actual version/build, **Jackson Feng**, and **jacksonfeng0130@yahoo.com**. No placeholder content. Support email opens a draft without automatically sending it. |
| A02 | Archive the tested source in Release. Verify main app and widget versions/builds. | Archive succeeds, widget is embedded, and version/build numbers match. Use an unused higher build number if 14 was already uploaded. No test runner, demo-seeding behavior, or debug launch flags in the distributed app. |
| A03 | Validate the archive in Xcode Organizer; review signing, entitlements, privacy manifests, and extension validation. | No unresolved validation errors. Correct app/extension profiles and private CloudKit/App Group entitlements; distribution APS value comes from the correct signing configuration. Do not rename stable identifiers merely to remove the old internal name. |
| A04 | Confirm stable identifiers: app `com.jackson.LoveLedger`, CloudKit `iCloud.com.jackson.LoveLedger`, App Group `group.com.jackson.LoveLedger`; preserve installed widget kinds. | This build updates the existing app and can reach existing stores/widgets, rather than installing as an unrelated app. Internal identifiers are not user-facing branding. |
| A05 | Review CloudKit Production schema against the tested model/schema. | Necessary record types/fields/indexes are deployed before production-backed testing. Development schema success is not production proof. Schema deployment copies schema, not your development records. See [Apple's deployment guidance](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema). |
| A06 | Open public support/privacy URLs on a device that is not your Mac; review privacy and encryption answers. | Public HTTPS pages load without sign-in; a `file://` page does not count. Privacy text matches the binary. Resolve export-compliance questions for the encrypted-backup feature rather than guessing a “no encryption” answer. See [Apple's export-compliance guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance). |
| A07 | Keep the exact archive, source revision/change snapshot, test record, and tester notes. | You can identify and reproduce the tested build. Any code fix after testing requires a new build and rerunning the affected cases plus core smoke tests. |

**Pre-upload decision:** all applicable A-device tests and B-archive checks are Pass, or any narrow non-critical beta limitation is explicitly documented. Do not proceed with known data-loss, recovery, authentication, money, or launch failures. A blocked safety-critical test means not ready for wider distribution.

## C. After upload — test yourself before inviting the wider group

App Store Connect processes the uploaded build before it becomes selectable; upload, tester distribution, and public App Store release are separate steps. See [Apple's upload-build guidance](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

| ID | What to do | Expected result |
| --- | --- | --- |
| T01 | Check processing, compliance, and the actual selected build in App Store Connect. | Correct DailySpend version/build is processed and eligible for your intended testing route; no unresolved processing/compliance error. |
| T02 | Install that build through TestFlight on your own/internal test devices: one fresh test install and one upgrade from the prior distributed version. | Same app identity, preserved upgrade history, correct About version/build, no launch crash. A local Xcode install is not a substitute for this check. |
| T03 | Repeat L03, D01–D04, S01/S04, U01/U04, P01–P05, W02/W07, and B01/B03/B06/B07 using disposable data. | All expected results still hold in the actual distributed package, not only in simulator or development signing. |
| T04 | Repeat I01/I02/R04 on two TestFlight devices using the same test account and Production environment. | Real production-backed create/edit/delete/offline/recurrence behavior is correct. Both devices converge without data loss or recurring duplicates. |
| T05 | Attach [What to Test](TESTFLIGHT_NOTES.md), support contact, and any accepted cosmetic limitations; review who receives the build. | Testers get the intended build and useful instructions. Do not add the wider group until the internal checks pass; external testing may also require Apple's beta review. |

## Record failures consistently

Use one entry per failure:

```text
Test ID:
Result: Pass / Fail / Blocked / Not applicable
DailySpend version/build:
Device and iOS version:
Install path: fresh / upgraded / TestFlight
Language/region; appearance/text size:
iCloud account/environment and online/offline state (no credentials):
Exact steps and test values:
Expected result:
Actual result:
Frequency: __ failures / __ attempts
Time of failure; screenshot/video/crash-log reference:
Retest build and result:
```

Hide private financial information before sharing evidence. Never attach a real backup together with its passphrase.

### Final sign-off

- [ ] Required cases have recorded results; none were assumed to pass from source inspection.
- [ ] No open crash, data-loss/duplication, incorrect-money, recovery, or privacy defect.
- [ ] Keyboard, first-tap sheets, all shipped widget sizes/appearances, and supported-device core tasks work.
- [ ] The exact TestFlight package passed the post-upload internal checks.
- [ ] Tester notes describe the actual build and any accepted non-critical limitations.

Owner: ____________________  Build: ____________________  Date: ____________________
