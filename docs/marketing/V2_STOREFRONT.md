# DailySpend 2.0 — storefront kit

What to upload where in App Store Connect for 2.0, with the images in
`AppStoreScreenshots/2.0/` (kept out of git, like the 1.0 screenshots).
Copy for the version page (description, keywords, What's New) is in
[V2_MARKETING.md](V2_MARKETING.md). Apple's rules were checked on
October 28, 2026 (sources at the end).

## 1. Files

| Folder | Size | Use |
|---|---|---|
| `iPhone-6.9/en`, `iPhone-6.9/zh` | 1320 × 2868 | iPhone screenshots (App Store Connect scales them for smaller iPhones) |
| `iPad-13/en`, `iPad-13/zh` | 2064 × 2752 | iPad 13-inch screenshots |
| `Creative-Assets/<lang>/header-21x9-3840x1646.png` | 21:9 | Product page header |
| `Creative-Assets/<lang>/search-3x2-3840x2560.png` | 3:2 | Search results |
| `Creative-Assets/<lang>/event-card-16x9-3840x2160.png` | 16:9 | In-App Event card |
| `Creative-Assets/<lang>/event-details-9x16-2160x3840.png` | 9:16 | In-App Event details page |

All are PNG without transparency. Every screen is a real 2.0 (16) screen
captured on a simulator with fictional sample data (no personal data).

If App Store Connect also asks for a smaller iPhone size (it lists the
required slots on the version page), upload the same 6.9-inch set there only
if it accepts it; otherwise tell me the size and I'll export it.

## 2. Product page screenshots (version 2.0)

Upload in this order, English under **English (U.S.)** and Chinese under
**Chinese, Simplified**. The first three also appear in search results.

| # | File | Headline (EN / ZH) |
|---|---|---|
| 1 | `01-scan-receipt.png` | Snap a receipt. It fills itself in. / 拍一下收据，自动填好 |
| 2 | `02-split-by-item.png` | Split by item. Pay just your share. / 按项分账，各付各的 |
| 3 | `03-quick-add.png` | Type it like you'd say it. / 像说话一样记账 |
| 4 | `04-insights.png` | Your month at a glance. / 本月花费，一眼看清 |
| 5 | `05-budget.png` | Budgets you can see. / 预算看得见 |
| 6 | `06-categories.png` | Every category, clearly. / 每个分类，清清楚楚 (dark) |
| 7 | `07-privacy.png` | Yours alone. / 数据只属于你 (dark) |
| — | `08-split-shares.png` | Everyone's share, to the cent. / 每人应付，精确到分 (for the Split custom page) |

The Chinese set shows yuan amounts, which is what a person in mainland
China sees (DailySpend uses the region's currency).

## 3. Header and search results (iOS 27 / iPadOS 27 and later)

1. **Growth & Marketing → Asset Library**: upload `header-21x9…` and
   `search-3x2…` for each language and submit them. They can be reviewed on
   their own, before or with 2.0.
2. On the **2.0** version page, **Product Page Information → Header and
   Search Results → Browse Assets**: pick the approved header and search
   results asset for each language.
3. Click **Preview** to check how the header crops on iPhone, iPad, and in
   Dark Mode. The design keeps everything centred, which is what Apple's
   asset guidance asks for. If the preview cuts off the outer panels, tell
   me and I'll make a narrower version.

Earlier iOS versions keep showing your screenshots, so nothing is lost there.

## 4. Custom product pages

**Growth & Marketing → Custom Product Pages → +** for each page below. Each
page gets its own link to use in posts, ads, or QR codes, and can be found in
search through the keywords you assign. Submit them with the 2.0 version (or
after it); once approved, turn each one to visible.

| Page | Screenshots, in order | Promotional text (EN / ZH) | Keywords (EN / ZH) | Deep link |
|---|---|---|---|---|
| **Receipt Scanner** | 01, 03, 02, 04, 05 | Scan any receipt. It fills itself in, on your iPhone. / 扫描收据，自动填好，全部在 iPhone 上完成。 | receipt, scanner, expense, tracker / 收据, 扫描, 记账 | `dailyspend://scan` |
| **Split with Friends** | 02, 08, 01, 03, 07 | Split dinner by dish, tax and tip included. / 聚餐按项分账，税和小费自动算好。 | bill, splitter, tip, calculator, group, shared / 分账, AA, 小费 | none |
| **Budget Calmly** | 04, 05, 06, 03, 07 | Know how this month is going, in one look. / 这个月花得怎么样，一眼就知道。 | budget, money, finance / 预算, 省钱, 理财 | `dailyspend://home` |

Notes:

- Keywords: App Store Connect lets you pick keywords for a page from your
  app's keyword list; use the ones above that it offers. A page shows up in
  search only after it's approved and visible.
- Deep links open the app on that screen when it's already installed
  (iOS 18 and later); first-time visitors see the page. `dailyspend://scan`
  opens the receipt scanner; the 2.0 tour steps aside for it.
- Use the same screenshots in both languages; the iPad slots take the iPad
  files with the same numbers.

## 5. In-App Event "DailySpend 2.0 is here"

**Growth & Marketing → In-App Events → +**, badge **Major Update**:

| Field | English | Chinese |
|---|---|---|
| Event name (30) | DailySpend 2.0 is here | DailySpend 2.0 全新上线 |
| Short description (50) | Scan receipts, split by item, log in plain words. | 扫描收据、按项分账、一句话记账。 |
| Long description (120) | Snap a receipt and it fills itself in. Split dinner by dish, log in plain words, and see your month at a glance. | 拍一下收据自动填好，聚餐按项分账，一句话就能记账，本月花费一眼看清。全部在你的 iPhone 上完成。 |
| Event card | `event-card-16x9…` | same, `zh` |
| Event details | `event-details-9x16…` | same, `zh` |

Start it on release day and run it for two weeks.

## 6. Product page optimization (after 2.0 is live)

Tests need a version that is **Ready for Distribution**, so start them after
release. Don't release 2.1 during a test if it changes the screenshots being
tested.

1. **First test:** Original (Snap first: 01, 02, 03…) against a treatment
   with Split first (02, 01, 03, 04, 05, 06, 07). Same images, new order.
2. **Later:** a treatment that leads with `08-split-shares.png`, or a new
   first headline ("Expense tracking without the typing.").

Let a test run until App Store Connect reports a confident result, then apply
the winner to the original page.

## 7. Claims check

Every headline matches 2.0 (16): scanning reads amount, store, date, and
category on the device; By Item divides tax and tip; Quick Add fills your
share from a sentence; Siri can log an expense; Insights compares the same
days of last month; backups are encrypted; iCloud sync is optional. Amounts
are sample data.

## How these were made

From `main` (cfd91fc) in a temporary scratch copy, on two dedicated
simulators (iPhone 17 Pro Max and iPad Pro 13-inch, iOS 27.0) with a 9:41
status bar. Only the scratch copy's Debug sample data was changed (English
and Chinese entries without "[Demo]") and its test-only iCloud label showed
the signed-in text a real user sees. Nothing in the app or this repository
was changed to make them.

## Sources

- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications/)
- [Manage your App Store assets](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets/)
- [App Store asset best practices](https://developer.apple.com/app-store/asset-best-practices/)
- [Custom product pages](https://developer.apple.com/app-store/custom-product-pages/)
- [Product page optimization overview](https://developer.apple.com/help/app-store-connect/create-product-page-optimization-tests/overview-of-product-page-optimization/)
