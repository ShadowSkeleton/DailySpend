# DailySpend 2.0 — manual test plan

Prepared October 25, 2026 for **2.0 (15)** on branch `claude/dailyspend-2.0-receipt-intelligence`. Record the build and revision you actually test.

These are **acceptance criteria, not results**. Mark each ID **Pass / Fail / Blocked / Not applicable**, with device, iOS version, and evidence (a screenshot or a note). A test you could not run is Blocked, not Pass.

**Stop and report** any crash, wrong cents, a split that doesn't add up to the receipt, a saved expense you didn't confirm, or data appearing in the App Store app that came from the test app.

## Setup

1. **Install "DailySpend Test" beside the App Store app** (it has its own bundle ID, empty data, and no iCloud or App Group):

   ```sh
   scripts/device-test/install-on-device.sh <device-udid>
   ```

   Find the UDID with `xcrun devicectl list devices`. The first launch may ask you to trust the developer in **Settings → General → VPN & Device Management**.
2. **Turn on Apple Intelligence** in iPhone Settings and wait for its download to finish.
3. **Copy the test receipts to Photos:** AirDrop the images in [`docs/test-receipts`](test-receipts/) to the phone and choose Save to Photos. Their expected values are in [`docs/test-receipts/README.md`](test-receipts/README.md).
4. Use only fictional or test expenses in DailySpend Test. Leave the App Store app alone.

**What DailySpend Test can't cover:** iCloud sync (it has no iCloud entitlement), widgets showing app data (no App Group), and the upgrade from the 1.0 App Store build. Those need a TestFlight build; see section K.

## A. Isolation and launch — must pass

| ID | What to do | Expected result |
|---|---|---|
| A01 | Find both icons on the Home Screen | "DailySpend" (App Store) and "DailySpend Test" both exist. |
| A02 | Open DailySpend Test | It opens with no expenses and stays open. Settings → iCloud Sync says "iCloud is off in this test build; data stays on this device". |
| A03 | Add a test expense in DailySpend Test, then open the App Store DailySpend | The App Store app shows only your real data. The test expense is not there. |
| A04 | Use your App Store DailySpend widgets (Quick Add, Dashboard) | They still open the App Store app and show your real numbers. |
| A05 | Settings → Receipt Scanning in DailySpend Test | Shows "On · Processed on this device" once Apple Intelligence is ready. |

## B. Scan to expense

| ID | What to do | Expected result |
|---|---|---|
| B01 | Home → scan button (next to +) → **Choose from Photos** → `01-restaurant-suggested-tip` | "Reading receipt…" appears with a Cancel button, then New Expense opens with $42.51, Food, Oct 24, note "Harbor Noodle House / Dumplings, Spicy Beef Noodles, Jasmine Tea", and a "Filled from receipt" banner with no warnings. Nothing is saved yet. |
| B02 | Tap Save on B01 | The expense appears on Home. Its row shows only the first line of the note (the store); opening it shows the full note with the items. |
| B02a | Scan `13-photo-hudson-lantern-bistro` from Home, then Save | The banner warns "Dated Apr 26, 2025, so it will be saved in that month." After Save, Home switches to April 2025 and shows the expense. Changing the date to today before saving records it in the current month instead. |
| B03 | Home → scan → **Scan with Camera** → photograph a real or on-screen receipt → Save in the camera | The scan tip appears the first time. The form fills in the same way. Cancelling the camera returns to Home with nothing filled in. |
| B04 | Start a scan, then tap **Cancel** while it's reading | The overlay closes and nothing opens or is filled in. |
| B05 | Scan `12-not-a-receipt` | Alert: "No total was found on this receipt. You can enter the amount manually." Nothing is saved. |
| B06 | New Expense → **Scan Receipt** inside the form → `05-cafe-tip` | Amount $12.90, Food, note "Blue Door Coffee / Latte, Croissant". A note you already typed yourself is not replaced. |
| B07 | Scan `03-grocery-long-coupons` and change its category to Food before saving. Scan it again. | The second scan picks Food: it reuses your last choice for that store. |
| B08 | Scan each receipt `01`–`11` from Home | The amount and category match the table in the test-receipts README. `06`, `07`, and `08` show a currency warning on a USD phone; the others show none. |
| B09 | Turn off Apple Intelligence in Settings, then scan `01` | Only the total is read ($42.51), and the banner says "Only the total was read." Turn it back on afterwards. |
| B10 | Scan 3–5 of your own real receipts (long grocery, restaurant, café, a foreign or crumpled one) | Note any wrong total, store, category, or date with a screenshot (hide card numbers). Amounts must never be silently wrong: if the parts don't add up, the banner should say so. |
| B11 | Scan a pharmacy, grocery, or ride receipt (`04`, `03`, `09`) and a restaurant one | Each gets its own category (Health, Grocery, Transport, Food), not Food for everything. |
| B12 | Phone language Chinese, region United States. Then region China. | US region: amounts in $ and USD, Chinese text and dates. China region: amounts in ¥ and CNY. Scanning `06` shows the CNY warning only on the US-region phone. |
| B13 | Scan `16-restaurant-tip-after-tax` from Home, both from Photos and by pointing the camera at it on a screen | $44.10 with all 3 dishes and no warnings. The tip guide's totals ($50.72, $52.04, $52.92) and tips ($6.62, $7.94, $8.82) are never used as the amount or tip. If the numbers truly don't add up, the warning shows the sum, such as "Subtotal $40.00 + tax $4.10 = $44.10, but the total reads …". |
| B14 | Scan `01` (or any receipt whose numbers add up) | The banner says **Amounts check out** with a green seal and "Subtotal, tax, and tip add up to the total printed on the receipt." A small line at the bottom says the receipt was read on this device by Apple Intelligence and AI can make mistakes. |
| B15 | Scan `14` or `15` (their printed lines don't add up) | The banner says **Check 1 thing before saving** with an orange outline, and the warning starts with what to check, then why ("Check the items. They add up to …"). Reading takes a little longer: a receipt that doesn't check out gets a second, careful read. |

## C. Quick Split

| ID | What to do | Expected result |
|---|---|---|
| C01 | Split Bill → Quick Split → **Scan Receipt** → `01` | Total bill $42.51 and the banner appears. The receipt leaves the tip line blank, so no tip is chosen: Tip shows "Not chosen" with a prompt, and the share shows $21.26 with a "Before tip" badge. The tip buttons become the receipt's own guide: **None, 18% $7.02, 20% $7.80, Custom**, with "From the receipt's tip guide" below. Tap 18%: the tip is $7.02. |
| C01a | Scan `16-restaurant-tip-after-tax`, from Photos and with the camera | Total bill $44.10, never $50.72, $52.04, or $52.92. The buttons are **None, 15% $6.62, 18% $7.94, 20% $8.82, Custom** (this restaurant figures tips after tax). 18% gives $7.94 and each of 2 pays $26.02. There is no before/after-tax menu. |
| C02 | Scan `02-restaurant-tip-charged` | Total bill $52.26 and the tip switches to **Custom → $** 9.00. With 2 people each pays $30.63. |
| C03 | Scan `03-grocery-long-coupons` | Total $78.02 and the tip switches to **None**. |
| C04 | Record My Share after `03` | New Expense opens with your share, the receipt's category and date, and a note starting with the store name. |
| C05 | Reset (circular-arrow button, top right) → Clear Form | Total, tip, and the banner reset. |
| C06 | Watch the screen while a receipt is being read | A receipt floats on a teal halo while a scan line sweeps down it, lines light up as it passes, and sparkles twinkle. The status steps through "Reading receipt…", "Finding the items…", "Spotting the total…", "Checking the math…". Cancel still works. With Reduce Motion on, the picture stands still. |

C01–C05 and C01a are also covered by the UI test `testQuickSplitScansRealReceipts`, which reads the real receipt images with the on-device model.

## D. By Item (simplified flow)

| ID | What to do | Expected result |
|---|---|---|
| D01 | Open By Item | Cards in this order: Scan a receipt, People (Me + Add), Items, Tax & Tip, Each Person Pays, Share Receipt. Same look as 1.0. |
| D02 | People → **Add** → type "Alex" → Save. Tap the Alex chip → **Rename**, then **Remove**. | Alex appears, can be renamed, and can be removed. "Me" can't be removed when alone. Saving an empty name gives "Person 2". |
| D03 | Type an item "Pizza" and price 20 with 2 people, then tap anywhere else (don't tap +) | Pizza is added, shared by everyone: "$20.00 · Everyone · $10.00 each". The keyboard's **Next Item** adds it and stays ready for the next one. Only the people chips are highlighted; there's no highlighted "Everyone" chip. Tap **Clear**: no one is selected and the caption turns orange, "Choose who shares this". Tap Alex: "$20.00 · Alex only". Tap **Select All** to share it again. |
| D03a | Type an item and price, then tap Share Receipt or Record before leaving the row | The typed item is included. |
| D04 | With items shared by everyone, add a third person | The new person joins every item shared by everyone. Personal items stay personal. |
| D05 | Scan `10-group-dinner-service-charge` into an empty list | 8 lines (Pad Thai × 2, Thai Iced Tea × 3), Tax $6.57, Tip Custom $13.32, Grand Total $93.89. |
| D06 | With 4 people, give each person different items from D05, then expand each person under **Each Person Pays** | Each card lists their items, shared items show "Shared by N", and Tax & tip is allocated. **The four totals add up to exactly $93.89.** |
| D07 | Scan `04-pharmacy-unit-price` while items already exist | A dialog asks **Replace Items** or **Add to Items**. Replace swaps the list; Add keeps both and adds the taxes together. |
| D08 | Scan `07-chinese-supermarket` | 6 lines (鸡蛋 10枚 and 大米 5kg stay one line each; 牛奶 × 2), a note that the 5.00 discount was spread, tip None, Grand Total 83.15. |
| D09 | Record as Expense for one person | New Expense opens with that person's exact total, the receipt date, and a note with the store, split summary, and their items. |
| D10 | Share Receipt in both modes, with and without a scan | The image is a paper slip on a soft teal background: the store and date at the top, a large headline (Quick Split: "Each pays" or "My share"; By Item: "Total"), then in By Item one card per person with a colored initial, their items, who shared each item, and their tax and tip. Subtotal, tax, tip, and Total sit at the bottom, with "Split with DailySpend" below. It's always light, even in dark mode. |

## E. Tips

| ID | What to do | Expected result |
|---|---|---|
| E01 | Look at the tip grid in both modes | Two rows of three: None, 10%, 15% / 18%, 20%, Custom. |
| E02 | Tap **Custom**, switch between % and $, and type values | The tip amount updates. Negative or empty values show a warning and block settling. |
| E03 | Change iPhone Region to China (any language), then open a new split | The tip choices are folded away behind an **Add Tip** button in both modes, and the person totals say "Tax" rather than "Tax & tip". Tap Add Tip to tip anyway. Scanning `06` (a hotpot service charge) shows no tip prompt. Restore your region afterwards. |
| E04 | US region, Chinese language | Tips show and default to 15%, as for any US-region phone. |
| E05 | Type a bill by hand (no scan) and choose 18% | The usual buttons (None, 10%, 15%, 18%, 20%, Custom). After a scan with tax, a line under them says "Figured on $39.00 before tax"; nothing to choose. |

## F. Polish and regressions

| ID | What to do | Expected result |
|---|---|---|
| F01 | New Expense amount field | The $ sits right beside the number. Prefilled amounts show cents (12.50, not 12.5). The keyboard dismiss button works. |
| F02 | Home with no expenses | "Add your first expense" shows its + icon and centered text. |
| F03 | Insights → Monthly Change | The line "Compared with the same days last month" is visible. The trend line never dips below zero between days. |
| F04 | Settings → Budget | Budget Amount and the alert threshold show the currency symbol. The Receipt Scanning section is below Data Management. |
| F05 | Settings → Category Limits → set Food to 180.50 → close → reopen | It still shows 180.50; 1.0 rounded it to 180. |
| F06 | Delete an expense (swipe and Edit → Delete) | The same "Delete This Expense?" wording in both places. The Delete button at the bottom of Edit Expense is red. |
| F06a | Add an expense with a long, multi-line note; look at Home, Insights → day detail, and the category list | Every row stays one line tall, showing only the note's first line. Opening the expense shows the complete note. |
| F07 | Switch iPhone language to Chinese and repeat B01 and D01 | All new text is in Chinese, the layout doesn't clip, and the default person is "我". |
| F08 | Dark mode; largest text size (Settings → Accessibility) | The banner, chips, and tip grid stay readable and tappable. Chips wrap to new rows. |
| F09 | Regression: add, edit, and delete expenses; a recurring expense; a budget; App Lock on and off; an encrypted backup and restore **inside DailySpend Test only** | Everything behaves as in 1.0. |

## G. Quick add in plain words (Phase 1)

Open New Expense (the + on Home). The **Quick Add** card is at the top. Type, or tap the keyboard's microphone to dictate, then press Return or the arrow.

| ID | What to type | Expected result |
|---|---|---|
| G00 | First time only: open New Expense | The card says **Quick Add**, explains "Type or say what you spent in your own words, and the form below fills itself in.", and shows "Try:" examples. The placeholder "e.g. Lunch 36, split 3" fits. Tap an example: the form fills in. Next time, only the title and field show. |
| G01 | `lunch with Alex 36, split 3` | The amount ($12.00) and date fill **instantly**. A pulsing "Choosing the best category…" line shows briefly, then Food is chosen. Below the field: "Filled in: $12.00 (your share of 3) · Food". If you tap a category yourself while it's choosing, yours is kept. Note: a short title ("Lunch with Alex"), your words, then "Total $36.00 · split 3". Nothing is saved until you tap Save. |
| G02 | `coffee 4.50 yesterday` | $4.50, Food, yesterday's date. |
| G03 | `Uber 23.40 last Friday` | $23.40, Transport, last Friday. |
| G04 | `dinner with 2 friends 90` | $30.00 (3 people). |
| G05 | `dinner 100 split 3 ways` | $33.34: the extra cent goes to you, so the three shares add up to $100.00. |
| G06 | `coffee 4.5 and bagel 3` | $7.50, with an orange line: "Found 2 amounts and added them up to $7.50. Check the amount." |
| G07 | `lunch with Alex` | No amount filled; orange "No amount found…"; the amount field is ready to type. |
| G08 | `dinner 60 AA` | $60.00, with "How many people? Add the number, like “split 3”." |
| G09 | `昨天打车 23 块` | ¥/$23.00, Transport, yesterday. |
| G10 | `和小王吃火锅 300，3个人AA`, then `三百块 火锅 三个人` | 100.00 each, Food, both times. Chinese numerals are read when a unit follows them (三百块, 三个人). |
| G11 | `上周五 电影 ¥80` | 80.00, Entertainment, last week's Friday. |
| G12 | `farmers market 12` | $12.00, no date change. ("market" isn't March.) |
| G16 | Dictate (keyboard microphone) "coffee four fifty", "parking fifty cents", "lunch twenty five dollars", "奶茶四块五" | 4.50, 0.50, 25.00, 4.50. "4:50" from dictation also reads as 4.50; "dinner at 7:30 45" is 45.00. |
| G13 | Type your own note first, then use quick add | Your note is kept; only the amount, category, and date change. |
| G14 | Turn off Apple Intelligence, then try G01–G03 | Amounts, dates, and splits still fill. The category comes from familiar words, and the "Category chosen… by Apple Intelligence" line doesn't appear. |
| G17 | `Lunch at KFC 25`, save, then check Home and Insights | The note's first line is a short title, like a scanned receipt's store name: "KFC" with Apple Intelligence, or "Lunch at KFC" without. Home and Insights show only that line; the amount is never cut off. |
| G18 | `dinner with my friends from work at the new ramen place downtown 80` | The title is a few words ("Dinner with my friends", or the place's name with Apple Intelligence), never a store you didn't mention. Your full words are on the next line of the note. |
| G15 | Dark mode and largest text size | The field, the arrow, and the summary lines stay readable and don't overlap. |

## H. Siri, Shortcuts, Spotlight, Control Center (Phase 2)

Siri knows the test build as **Daily Spend Test** (say it as three words). The App Store build answers to "Daily Spend".

**Before the first try:**
- After installing, open DailySpend Test once, then wait a minute while iOS registers its phrases.
- In iOS 27, per-app Siri options are under **Settings → Siri → App Access → DailySpend Test** (not on the app's own Settings page). There's no switch there that blocks app actions.
- If Siri still says it can't help, run the same action from the Shortcuts app (Library → Apps → DailySpend Test) or from Spotlight. If it works there, the phrase wasn't heard as expected; try the exact wording below.

The test build opens its own `dailyspendtest://` links, so its widgets and Control Center controls open the test app, never the App Store app.

| ID | What to do | Expected result |
|---|---|---|
| H01 | "Hey Siri, log an expense in Daily Spend Test" | Siri asks "What was it for?" (say "coffee"), then "How much was it?" (say "four fifty" or "four dollars and fifty cents"). It asks "Save 'coffee': $4.50, Food?" Say yes: "Saved 'Coffee', $4.50." On Home the note says "Coffee", the same short style as other expenses. |
| H02 | Same, answering "lunch with Alex split 3" and "thirty six dollars" | Siri asks "Save 'lunch with Alex split 3': your share, $12.00 of $36.00 split 3 ways, Food?" If the words in quotes are wrong (Siri can mishear, e.g. "Launch with Application"), say no and try again. Say no: nothing is saved. |
| H03 | Same, answering "coffee yesterday" and "four fifty" | Saved with yesterday's date. |
| H04 | "Hey Siri, how much have I spent this month in Daily Spend Test" | It says this month's total, and what's left of the budget (or how much over) if a budget is on. The total matches Home. |
| H05 | "Hey Siri, scan a receipt with Daily Spend Test" | The app opens and the scanner starts. With App Lock on, it opens after you unlock. |
| H06 | Lock the iPhone, then try H01 and H04 | Siri asks you to unlock first. |
| H07 | Shortcuts app → search DailySpend | Log an Expense, Scan a Receipt, and Spending This Month appear and run the same way. Spotlight shows them when you type "DailySpend". |
| H08 | Control Center → + → Add a Control → **DailySpend Test** (remove any DailySpend Test controls added before this build first) | Scan Receipt and Add Expense are offered. Each opens the right screen, waiting for App Lock. |
| H09 | Settings → Action button → Controls → Scan Receipt | Pressing the Action button opens the scanner. |
| H10 | Chinese phone language: "嘿 Siri，在 DailySpend Test 里记一笔" → "咖啡 十八块" | Siri reads back 18.00, Food, and saves on yes. |

## I. Insights: quick look on top, details below (Phase 3)

Insights reads top to bottom. **Quick look:** one card for this month, on both the Trends and Activity tabs, read as a sentence. **Details:** one tap under it. **Explore:** below the Trends/Activity switch, the period buttons sit right on the graph.

"This time last month" means the 1st of last month **through the same day**, counting whole days. All of today counts, whatever time an expense was saved.

| ID | What to do | Expected result |
|---|---|---|
| I01 | Open Insights with expenses this month and last month | "[Month] So Far" with a ?, then a big **"$219 more"** in red or **"$3,219 less"** in green (whole dollars), "than this time last month", and two lines: "You've spent $2,161" / "Shopping is down $3,595". No amount wraps onto a line of its own. The category always matches the direction of the big number. |
| I02 | Tap **Details** | Sentences written by the app with exact cents, each amount next to what it belongs to: "You've spent $2,160.98 in October so far, 60% less than the same days of September ($5,380.00). Shopping fell the most, down $3,595.00." (plus the budget, if on). With Apple Intelligence, one more sentence **with no numbers**, e.g. "Most of the drop came from Shopping.", and the note "The last sentence was written on this device by Apple Intelligence…". That sentence never names a category you didn't spend on and never says up where the facts say down. Then three tiles: so far, the same days last month, the change. |
| I03 | Tap the ? | Explains: the 1st of this month through today against the 1st of last month through the same day, whole days, and that expenses dated later this month count once that day comes. |
| I04 | Add an expense for **later this month** (e.g. rent on the 31st) | Home's month total includes it. The quick look doesn't yet, and Details says "Plus $X dated later this month, counted once that day comes". Home = "You've spent" + that amount. |
| I05 | Late in the evening, check an expense saved last month on the same day at night | It's counted in "this time last month" all day today (whole days). |
| I06 | On the 1st–3rd of a month, or when last month's same days were tiny (e.g. $5) | The big number and line still show the amount; the Change tile shows the amount (e.g. "+$195.00") instead of a huge percentage. |
| I07 | Someone who started tracking partway through last month (e.g. on the 20th) | No comparison yet: big total in the app's color, "spent so far", "N expenses · most on …", and "After your first full month, you'll see how each month compares here." Same for 3M/6M/Year until the records cover the earlier period. |
| I08 | First-time user: fresh install, add 1–3 expenses this month only | "$25", "spent so far", "1 expense · most on Food", and the first-month note. No ?, no red/green. |
| I09 | Switch to **Activity** | The same quick-look card stays on top. |
| I10 | Trends → **Last Month**, **3M**, **6M**, **Year**, **All**, and calendar months | The buttons sit directly above the Spending Trend graph. Its top-right shows that period's total and, in red or green, how much more or less than the period before (All: total only). The top card stays on this month. |
| I11 | Turn off Apple Intelligence | Details shows only the app's sentences and no AI note. The quick look is always written by the app, so it's unchanged. |
| I12 | Expenses in earlier months but none yet this month (e.g. on the 1st) | "$0" and "No spending yet this month". With no expenses at all: no card. |
| I13 | Chinese phone language | "[月份]至今", "少花 ¥3,219" / "多花", "与上月同期相比", "已花 ¥2,161" / "购物少了 ¥3,595", "详情", Chinese summary with "至今". |
| I14 | Largest text size and dark mode | The big number shrinks to fit on one line; nothing overlaps. |
| I15 | Ranking and Activity day detail, with a long note | One line of the note, cut with "…"; the amount always shows in full. An expense named with its amount ("Shop at Apple 1200") is called "Shop at Apple" in the summary. |

## J. One-time 2.0 tour

| ID | What to do | Expected result |
|---|---|---|
| J01 | Update over 1.0 that has expenses (no app delete) and open 2.0 | After App Lock (if on), a full-screen tour opens on "Your N expenses are all here" with **Back Up Now** and **Not Now**. N matches Home. |
| J02 | J01 → Back Up Now → passphrase (12+ characters, twice) → save to Files | Files opens after the passphrase sheet closes. After saving: "Backup saved", the green tick, and **Continue**. The file restores in Settings with Safe Merge. |
| J03 | J01 → Back Up Now → Cancel the passphrase, or close Files without saving | Back on the backup page with no error; Back Up Now still offered. |
| J04 | Swipe or Continue through all pages | Scan, Split, Quick Add, Siri & Controls, Insights; each picture animates once you land on its page; the last button says **Get Started**. |
| J05 | Skip on any page, or Get Started | The tour closes and never opens on its own again, including after an app update to 2.0.x. |
| J06 | Quit DailySpend during the tour, then reopen | The tour shows again from the start. |
| J07 | Fresh install (new user, no iCloud data) | "Spending, made clear" welcome page instead of the backup page; no "NEW IN 2.0" badges. |
| J08 | Open the app the first time from Siri, a widget's Add, or a Control Center control | That task opens first; the tour waits until the app is next opened normally. |
| J09 | Settings → **What's New in DailySpend 2.0** | The five feature pages only, ending in **Done**. |
| J10 | Chinese phone language, dark mode, largest text size, Reduce Motion | Chinese text throughout; pictures readable in dark mode; at the largest sizes pictures are hidden and text scrolls; with Reduce Motion the pictures don't move. |
| J11 | VoiceOver | Each page reads its title, text, and note; "Page 2 of 6"; Skip, Continue, Back Up Now, and Not Now are buttons; pictures are skipped. |
| J12 | A device without Apple Intelligence | The Split page adds "This device reads the total. Scanning each item needs Apple Intelligence." |
| J13 | iPhone Duo closed, then open, then turned upright | Each tour page fits without text under the page dots; buttons stay phone-width. Home, New Expense, Split Bill, Insights, and Settings stay usable in every pose (bars move to the side rail on iOS 27.1). |

## K. Needs a TestFlight build (later)

Do these only with a TestFlight build of 2.0, after an encrypted backup of your real data:

| ID | What to do | Expected result |
|---|---|---|
| K01 | Install the 2.0 TestFlight build **over** the 1.0 App Store app (don't delete) | All existing expenses, budgets, recurring entries, and settings are unchanged. The tour opens on the backup page (J01). |
| K05 | Reinstall 1.0 from the App Store over the beta, then the beta again | Records unchanged both times; the tour doesn't repeat. |
| K02 | Scan a receipt and save; check a second device on the same iCloud account | The expense syncs. No duplicates. |
| K03 | Widgets after saving a scanned expense | The Dashboard totals include it after iOS refreshes. |
| K04 | Run the `dailyspend-quality` and `dailyspend-upgrade-safety` reviews for 2.0 (16) | Reports are written under `docs/releases/` with separate upload and release decisions. |
