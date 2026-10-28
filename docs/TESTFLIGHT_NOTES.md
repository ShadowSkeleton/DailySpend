# DailySpend — TestFlight notes

## Version 2.0 (16) — not yet uploaded

Paste after the release quality and data-safety reviews, and confirm the uploaded build number in App Store Connect. Tester backup messages and the Beta App Description are in `docs/TESTER_DATA_WORKFLOW.md` → "Version 2.0 TestFlight cycle".

> **Back up before installing:** Settings → Data Management → Create Encrypted Backup, saved outside the app. Install over your current app; never delete it.
>
> DailySpend 2.0 does a lot more on your device. A short tour shows each new feature the first time you open it (Settings → What's New shows it again).
>
> - **Scan a receipt:** tap the scan button on Home, next to +. Check the amount, store, date, and category before saving.
> - **Split from a receipt:** in Split Bill, scan into Quick Split (total and tip) or By Item (every line, tax, and tip), and tap names on each item.
> - **Quick Add:** tap + and type "Lunch with Alex 25" or "Uber 18 yesterday".
> - **Siri and Controls:** "Log an expense in DailySpend", "Scan a receipt with DailySpend", "How much have I spent this month in DailySpend". Add the Scan Receipt or Add Expense control to Control Center, the Lock Screen, or the Action button.
> - **Insights:** a quick look at this month against the same days last month, with Details for the numbers.
>
> Please try receipts in different languages and layouts, Quick Add sentences in your own words, and Insights early and late in a month. Tell us when a total, item, category, or summary is wrong, and hide personal details in screenshots.
>
> Scanning items and some summaries need Apple Intelligence (iOS 26 or later on a supported device, turned on in Settings). Other devices still read the total and use everything else.

> **安装前请先备份：**“设置”→“数据管理”→“创建加密备份”，并把文件保存到 App 之外。直接覆盖安装，不要删除原 App。
>
> DailySpend 2.0 在你的设备上能做更多事。第一次打开时会有简短介绍（之后可在“设置”→“DailySpend 2.0 新功能”再次查看）。
>
> - **扫描收据：**点首页 + 旁边的扫描按钮，保存前确认金额、商家、日期和分类。
> - **用收据分账：**在“分账”里扫描到“快速分账”（总额和小费）或“按项分账”（每一项、税和小费），在每一项上点选分摊的人。
> - **一句话记账：**点 +，输入“和 Alex 吃午饭 25”或“昨天打车 23 块”。
> - **Siri 和控制：**“在DailySpend里记一笔”“用DailySpend扫描收据”“我这个月在DailySpend花了多少”。可以把“扫描收据”或“记一笔”加到控制中心、锁定屏幕或操作按钮。
> - **统计速览：**本月与上月同期对比，点“详情”查看具体数字。
>
> 欢迎用不同语言和格式的收据、你自己的说法来试一句话记账，并在月初和月末看看统计速览。发现总额、项目、分类或总结有误时请告诉我们，截图时请遮挡个人信息。
>
> 按项扫描和部分总结需要 Apple 智能（iOS 26 或更高版本、受支持的设备，并在“设置”中开启）。其他设备仍可识别总额，其他功能照常使用。

---

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
