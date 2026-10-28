# Test receipts

Fictional receipt photos for testing DailySpend's receipt scanning by hand. Every store, person, and amount is invented. Regenerate them with:

```sh
swift scripts/test-receipts/make_test_receipts.swift
```

The script computes every total for `01`–`12` and `16`, so the values below always match those images. `13`–`15` are photos of realistic printed receipts; their own line items don't always add up, which makes them good checks for the warnings. `ReceiptIntelligenceTests.testManualTestReceiptsRecordTheirDocumentedTotals` reads this folder and checks the amount each receipt records whenever Apple Intelligence is available.

**Getting them onto an iPhone:** AirDrop the `.jpg` files from Finder and choose **Save to Photos**, then use **Choose from Photos**. To test the camera instead, open an image full-screen on a Mac or iPad and scan the screen.

## Expected results

"Amount" is what a scan from Home or New Expense should fill in. The By Item columns assume a scan into an empty By Item split. Results were checked on the iOS 27.0 simulator on October 25, 2026. The on-device model can phrase names slightly differently on another device, but amounts, the category, and the line count should match.

| File | Amount | Store · Category · Date | Warnings in the banner | By Item after scanning |
|---|---|---|---|---|
| `01-restaurant-suggested-tip` | $42.51 | Harbor Noodle House · Food · Oct 24 | None (the suggested-tip table is ignored) | 4 lines: Dumplings × 2 at $9.00, Spicy Beef Noodles, Jasmine Tea · Tax $3.51 · tip keeps your choice |
| `02-restaurant-tip-charged` | $61.26 | Osteria Lume · Food · Oct 23 | None | 3 lines · Tax $4.26 · Tip **Custom $9.00** · Grand total $61.26 |
| `03-grocery-long-coupons` | $78.02 | Green Basket Market · Grocery · Oct 22 | Notes: $1.50 discount spread across items; tip set to None | 18 lines (avocado and penne become 2 lines each) · Tax $1.62 · Grand total $78.02 |
| `04-pharmacy-unit-price` | $29.35 | Wellway Pharmacy · Health · Oct 21 | Notes: $2.00 discount spread; tip set to None | 4 lines (cough drops become 2 lines, $3.26 and $3.25 after the discount is spread) · Tax $1.89 · Grand total $29.35 |
| `05-cafe-tip` | $12.90 | Blue Door Coffee · Food · Oct 22 | None | 2 lines · Tax $0.90 · Tip Custom $2.00 · Grand total $12.90 |
| `06-chinese-hotpot-service` | 222.20 | 蜀香火锅 · Food · Oct 20 | "This receipt may be in CNY" on a non-CNY phone | 4 lines (肥牛 × 2) · the 服务费 service charge appears as Tax 20.20 · Grand total 222.20 with tip None |
| `07-chinese-supermarket` | 83.15 | 惠民超市 · Grocery · Oct 19 | CNY warning; notes: 5.00 discount spread; tip None | 6 lines: 鸡蛋 10枚 and 大米 5kg stay single lines, 牛奶 × 2 · Grand total 83.15 |
| `08-euro-cafe-vat-included` | 12.00 | Café Lumière · Food · Oct 24 | "This receipt may be in EUR" on a non-EUR phone | 3 lines at the printed prices (2.50, 4.20, 5.30) · no tax added, because VAT is already included |
| `09-ride-fee-tip` | $23.18 | Metro Ride · Transport · Oct 19 | None | 2 lines (fare and booking fee) · Tip Custom $1.93 · Grand total $23.18 |
| `10-group-dinner-service-charge` | $93.89 | Lucky Thai Kitchen · Food · Oct 25 | None | 8 lines: Pad Thai × 2 at $14.00, Thai Iced Tea × 3 at $4.50, Green Curry, Spring Rolls, Mango Sticky Rice · Tax $6.57 · Tip Custom $13.32 (the service charge) · Grand total $93.89 |
| `11-faded-deli` | $22.29 | Corner Deli · Food · Oct 18 | None | 3 lines · Tax $1.79 |
| `12-not-a-receipt` | — | — | Alert: "No total was found on this receipt. You can enter the amount manually." | Nothing is filled in |
| `16-restaurant-tip-after-tax` | $44.10 | Saffron Table · Food · Oct 24 | None | 3 lines · Tax $4.10 · tip **Not chosen**. Its tip guide is figured on the total after tax; the tip buttons are its own 15% $6.62, 18% $7.94, and 20% $8.82. The guide's totals ($50.72, $52.04, $52.92) must never become the amount. |
| `13-photo-hudson-lantern-bistro` | $262.39 | Hudson Lantern Bistro · Food · **Apr 26, 2025** | "Dated Apr 26, 2025, so it will be saved in that month." After Save, Home jumps to April 2025. | 11 lines at their printed prices (add-ons such as "- no onions" are not separate items) · Tax $21.39 · tip keeps your choice |
| `14-photo-east-village-noodle-house` | $120.69 | East Village Noodle House · Food · **Apr 26, 2024** | Same past-date warning. In By Item: "$0.55 didn't match any item and is listed as Other items" (the printed lines are $0.55 under the subtotal). | 15 lines (14 items + Other items $0.55) |
| `15-photo-brooklyn-harbor-grill` | $199.25 | Brooklyn Harbor Grill · Food · **Apr 27, 2024** | Same past-date warning. In By Item: "Items added up to $2.00 more than the subtotal, so prices were adjusted proportionally." | 11 items |

A Quick Split scan fills the total before any charged tip (for example $52.26 for `02`) and moves the charged tip into Custom $. Store and pharmacy receipts (`03`, `04`, `07`) set the tip to None. A restaurant bill whose tip line is blank (`01`, `13`–`15`) leaves the tip **Not chosen** on a US or Canada phone, so the payer picks it; when the receipt prints a tip guide, the tip buttons become its own choices with its amounts (`01`: 18% $7.02 and 20% $7.80; `16`: 15% $6.62, 18% $7.94, and 20% $8.82). With no guide, the usual percentages are figured on the bill before tax.

## Making more receipts with an image model

Image models often garble small text and numbers. Check every printed amount on a generated image before using it, and write down its printed total as the expected amount. Real receipts from your own purchases are the best test; hide card numbers and personal details before sharing a photo.

Prompts that tend to work:

1. *Restaurant, angled photo:* "A realistic smartphone photo of a crumpled thermal paper restaurant receipt lying on a wooden table at a slight angle, warm evening light. Clearly legible monospaced print. Header: 'SAKURA RAMEN BAR'. Lines with prices on the right: 'Tonkotsu Ramen 15.50', '2 Gyoza 12.00', 'Matcha Latte 5.25'. Then 'Subtotal 32.75', 'Tax 2.87', 'Total 35.62', and a 'Suggested tip' table below the total. No watermark, no extra text."
2. *Long grocery receipt:* "Top-down photo of a long supermarket receipt held flat by a hand, bright kitchen light. Header 'NORTHSIDE GROCERS'. 15 grocery items with prices on the right, one line '3 @ 0.99 LIMES 2.97', two coupon lines with negative amounts, then SUBTOTAL, TAX, TOTAL, and CASH and CHANGE lines. Crisp, readable print, slight curl at the bottom."
3. *Chinese receipt:* "手机拍摄的超市小票照片，热敏纸，略微倾斜，室内灯光。抬头「家乐生活超市」，五个商品，每行右侧是价格，包括「苹果 1.5kg 12.60」和「酸奶 2 15.80」，然后是「合计」「会员优惠 -3.00」「实付」和「微信支付」。文字清晰可读，没有水印。"
4. *Faded and shadowed:* "Close-up photo of a faded thermal receipt from 'MAPLE STREET PHARMACY' with light gray print and a soft shadow across one corner, three items, a subtotal, sales tax, and total. Slightly out of focus but still readable."
5. *European receipt:* "Photo of a French café receipt on a marble table. Header 'BRASSERIE DU PONT'. Prices use decimal commas and the € sign, e.g. 'Croque monsieur 9,50 €'. Ends with 'TOTAL TTC 23,40 €' and 'dont TVA 10% 2,13 €'. Legible print, natural daylight."
