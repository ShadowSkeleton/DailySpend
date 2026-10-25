import FoundationModels
import UIKit
import XCTest
@testable import DailySpend

@MainActor
final class ReceiptIntelligenceTests: XCTestCase {
    private func cents(_ value: Int64) -> Money { Money(minorUnits: value) }

    // MARK: - Amounts and dates as printed

    func testNumberParserReadsPrintedAmountsIndependentOfLocale() {
        XCTAssertEqual(ReceiptNumberParser.money(from: "12.50"), cents(1250))
        XCTAssertEqual(ReceiptNumberParser.money(from: "$1,234.56"), cents(123_456))
        XCTAssertEqual(ReceiptNumberParser.money(from: "1.234,56 €"), cents(123_456))
        XCTAssertEqual(ReceiptNumberParser.money(from: "12,5"), cents(1250))
        XCTAssertEqual(ReceiptNumberParser.money(from: "¥ 88"), cents(8800))
        XCTAssertEqual(ReceiptNumberParser.money(from: "1,234"), cents(123_400))
        XCTAssertEqual(ReceiptNumberParser.money(from: "-2.00"), cents(-200))
        XCTAssertEqual(ReceiptNumberParser.money(from: "(3.10)"), cents(-310))
        XCTAssertNil(ReceiptNumberParser.money(from: "TOTAL"))
        XCTAssertNil(ReceiptNumberParser.money(from: ""))
        XCTAssertNil(ReceiptNumberParser.money(from: nil))
        XCTAssertNil(ReceiptNumberParser.money(from: "123456789012345.00"))
    }

    func testDateParserAcceptsOnlyRealCalendarDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let date = ReceiptNumberParser.date(from: "2026-02-28", calendar: calendar)
        XCTAssertEqual(date.map { calendar.component(.day, from: $0) }, 28)
        XCTAssertNil(ReceiptNumberParser.date(from: "2026-02-30", calendar: calendar))
        XCTAssertNil(ReceiptNumberParser.date(from: "02/28/2026", calendar: calendar))
        XCTAssertNil(ReceiptNumberParser.date(from: nil, calendar: calendar))
    }

    // MARK: - Recognized text layout

    func testLayoutJoinsNamesAndPricesOnTheSameRow() {
        let lines = [
            ReceiptAmountParser.Line(text: "Dumplings", boundingBox: CGRect(x: 0.05, y: 0.70, width: 0.30, height: 0.03)),
            ReceiptAmountParser.Line(text: "18.00", boundingBox: CGRect(x: 0.80, y: 0.705, width: 0.12, height: 0.03)),
            ReceiptAmountParser.Line(text: "CAFE", boundingBox: CGRect(x: 0.40, y: 0.90, width: 0.20, height: 0.04)),
            ReceiptAmountParser.Line(text: "Total", boundingBox: CGRect(x: 0.05, y: 0.40, width: 0.15, height: 0.03)),
            ReceiptAmountParser.Line(text: "21.06", boundingBox: CGRect(x: 0.80, y: 0.398, width: 0.12, height: 0.03))
        ]
        XCTAssertEqual(ReceiptTextLayout.rows(from: lines), ["CAFE", "Dumplings | 18.00", "Total | 21.06"])
    }

    func testTiltedPhotoRowsAreStraightenedBeforeGrouping() {
        // A 1000 × 800 photo tilted by 0.03 rad: right-hand prices sit about
        // 18 px higher than their names, more than half a 28 px line.
        let size = CGSize(width: 1000, height: 800)
        let tilt: CGFloat = 0.03
        func fragment(_ text: String, x: CGFloat, width: CGFloat, rowCenterY: CGFloat) -> (ReceiptAmountParser.Line, (left: CGPoint, right: CGPoint, height: CGFloat)) {
            let centerX = (x + width / 2) * size.width
            let centerY = rowCenterY + tan(tilt) * (centerX - size.width / 2)
            let box = CGRect(x: x, y: centerY / size.height - 0.0175, width: width, height: 0.035)
            let rise = tan(tilt) * width * size.width / size.height
            return (ReceiptAmountParser.Line(text: text, boundingBox: box),
                    (left: CGPoint(x: box.minX, y: box.minY), right: CGPoint(x: box.maxX, y: box.minY + rise), height: box.height))
        }
        let parts = [
            fragment("Dumplings", x: 0.10, width: 0.30, rowCenterY: 500),
            fragment("18.00", x: 0.80, width: 0.10, rowCenterY: 500),
            fragment("Thank you for dining with us", x: 0.20, width: 0.60, rowCenterY: 300),
            fragment("Total", x: 0.10, width: 0.15, rowCenterY: 440),
            fragment("42.51", x: 0.80, width: 0.10, rowCenterY: 440)
        ]
        let lines = parts.map(\.0)
        XCTAssertEqual(ReceiptTextLayout.rows(from: lines).count, 5, "Without straightening, prices drift onto their own rows")

        let angle = ReceiptSkew.angle(baselines: parts.map(\.1), imageSize: size)
        XCTAssertEqual(angle, tilt, accuracy: 0.002)
        let straightened = ReceiptSkew.straighten(lines, angle: angle, imageSize: size)
        XCTAssertEqual(ReceiptTextLayout.rows(from: straightened), ["Dumplings | 18.00", "Total | 42.51", "Thank you for dining with us"])

        // Short words with flat or noisy baselines don't decide the tilt.
        let noisy = parts.map(\.1) + [(left: CGPoint(x: 0.1, y: 0.2), right: CGPoint(x: 0.16, y: 0.2), height: 0.035)]
        XCTAssertEqual(ReceiptSkew.angle(baselines: noisy, imageSize: size), tilt, accuracy: 0.002)

        XCTAssertEqual(ReceiptSkew.angle(baselines: [], imageSize: size), 0)
        XCTAssertEqual(ReceiptSkew.straighten(lines, angle: 0, imageSize: size), lines)
    }

    func testLongReceiptPromptKeepsTotalsAndDropsFooter() {
        var rows = ["Store", "123 Main St", "Springfield", "Tel 555-0100"]
        rows += (1...120).map { "Item number \($0) | \($0).99" }
        rows += ["Subtotal | 1000.00", "Tax | 80.00", "Total | 1080.00"]
        rows += (1...20).map { "Thank you for shopping line \($0)" }
        let prompt = ReceiptTextLayout.prompt(fromRows: rows, characterBudget: 1_500)
        XCTAssertTrue(prompt.truncated)
        XCTAssertLessThanOrEqual(prompt.text.count, 1_500)
        XCTAssertTrue(prompt.text.hasPrefix("Store"))
        XCTAssertTrue(prompt.text.contains("Total | 1080.00"))
        XCTAssertFalse(prompt.text.contains("Thank you for shopping line 20"))
        XCTAssertFalse(prompt.text.contains("Tel 555-0100"), "Unpriced header rows after the first three go first")

        let short = ReceiptTextLayout.prompt(fromRows: ["Store", "Tea | 4.50"])
        XCTAssertFalse(short.truncated)
        XCTAssertEqual(short.text, "Store\nTea | 4.50")
    }

    // MARK: - Reconciliation

    func testReconcileRemovesSummaryRowsAndTurnsNegativeLinesIntoDiscounts() {
        let draft = ReceiptDraft(
            merchant: "  Corner Market ",
            currencyCode: "usd",
            items: [
                .init(name: "Bananas", quantity: 1, price: cents(299)),
                .init(name: "Subtotal", quantity: 1, price: cents(1299)),
                .init(name: "Coupon", quantity: 1, price: cents(-100)),
                .init(name: "Taxi voucher", quantity: 1, price: cents(1000)),
                .init(name: "SALES TAX", quantity: 1, price: cents(104))
            ],
            category: "Snacks",
            source: .appleIntelligence
        ).reconciled()

        XCTAssertEqual(draft.merchant, "Corner Market")
        XCTAssertEqual(draft.currencyCode, "USD")
        XCTAssertEqual(draft.items.map(\.name), ["Bananas", "Taxi voucher"])
        XCTAssertEqual(draft.discount, cents(100))
        XCTAssertNil(draft.category, "Only DailySpend categories are accepted")
        XCTAssertEqual(draft.total, cents(1199), "Computed from items minus the coupon when no total is printed")
    }

    func testAllCapitalNamesBecomeReadableWithoutTouchingShortCodes() {
        XCTAssertEqual(ReceiptDraft.readableName("HARBOR NOODLE HOUSE"), "Harbor Noodle House")
        XCTAssertEqual(ReceiptDraft.readableName(" TRADER JOE'S "), "Trader Joe's")
        XCTAssertEqual(ReceiptDraft.readableName("CVS PHARMACY"), "CVS Pharmacy")
        XCTAssertEqual(ReceiptDraft.readableName("ADVIL 24CT"), "Advil 24CT")
        XCTAssertEqual(ReceiptDraft.readableName("Blue Bottle Coffee"), "Blue Bottle Coffee")
        XCTAssertEqual(ReceiptDraft.readableName("海底捞火锅"), "海底捞火锅")
        let draft = ReceiptDraft(merchant: "HARBOR NOODLE HOUSE",
                                 items: [.init(name: "SPICY BEEF NOODLES", quantity: 1, price: cents(1650))],
                                 source: .appleIntelligence).reconciled()
        XCTAssertEqual(draft.merchant, "Harbor Noodle House")
        XCTAssertEqual(draft.items.map(\.name), ["Spicy Beef Noodles"])
    }

    func testStoreReceiptsDoNotGetARestaurantTip() {
        let session = SplitSession()
        session.tipSelection = 15
        let pharmacy = ReceiptDraft(items: [.init(name: "Advil", quantity: 1, price: cents(949))],
                                    subtotal: cents(949), tax: cents(81), total: cents(1030),
                                    category: "Health", isTippedService: false, source: .appleIntelligence)
        XCTAssertTrue(pharmacy.expectsNoTip)
        session.apply(pharmacy, replacingItems: true)
        XCTAssertEqual(session.tipSelection, TipPreset.none)
        XCTAssertEqual(Money(session.grandTotal), cents(1030), "The split matches what was paid")

        // A restaurant receipt keeps the person's tip choice for them to decide.
        let restaurant = ReceiptDraft(items: [.init(name: "Noodles", quantity: 1, price: cents(1650))],
                                      subtotal: cents(1650), total: cents(1650),
                                      category: "Food", isTippedService: true, source: .appleIntelligence)
        XCTAssertFalse(restaurant.expectsNoTip)
        session.tipSelection = 18
        session.apply(restaurant, replacingItems: true)
        XCTAssertEqual(session.tipSelection, 18)

        // Total-only reads don't know the kind of store, so nothing changes.
        XCTAssertFalse(ReceiptDraft(total: cents(1000), source: .textRecognition).expectsNoTip)
    }

    func testPrintedSuggestedTipIsNotTreatedAsCharged() {
        let suggested = ReceiptDraft(subtotal: cents(5000), tax: cents(400), tip: cents(1000), total: cents(5400),
                                     source: .appleIntelligence).reconciled()
        XCTAssertNil(suggested.tip)
        XCTAssertEqual(suggested.billBeforeTip, cents(5400))

        let charged = ReceiptDraft(subtotal: cents(5000), tax: cents(400), tip: cents(1000), total: cents(6400),
                                   source: .appleIntelligence).reconciled()
        XCTAssertEqual(charged.tip, cents(1000))
        XCTAssertEqual(charged.amountToRecord, cents(6400))
        XCTAssertEqual(charged.billBeforeTip, cents(5400))
    }

    func testReconcileRejectsImplausibleDates() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let future = ReceiptDraft(date: now.addingTimeInterval(7 * 86_400), source: .appleIntelligence).reconciled(now: now)
        XCTAssertNil(future.date)
        let ancient = ReceiptDraft(date: now.addingTimeInterval(-5 * 365 * 86_400), source: .appleIntelligence).reconciled(now: now)
        XCTAssertNil(ancient.date)
        let yesterday = now.addingTimeInterval(-86_400)
        XCTAssertEqual(ReceiptDraft(date: yesterday, source: .appleIntelligence).reconciled(now: now).date, yesterday)
    }

    func testSplitItemsAlwaysAddUpToTheSubtotal() {
        // A printed discount is spread across items in proportion to price.
        let discounted = ReceiptDraft(
            items: [.init(name: "A", quantity: 1, price: cents(1000)), .init(name: "B", quantity: 1, price: cents(500))],
            subtotal: cents(1350), discount: cents(150), tax: cents(100), total: cents(1450),
            source: .appleIntelligence
        )
        let discountedItems = discounted.itemsForSplit()
        XCTAssertEqual(discountedItems.map(\.price), [cents(900), cents(450)])
        XCTAssertFalse(discounted.issues.contains { if case .itemsAdjusted = $0 { return true } else { return false } },
                       "A printed discount that explains the difference isn't a warning")

        // A missed line becomes a visible "Other items" entry.
        let missing = ReceiptDraft(
            items: [.init(name: "A", quantity: 1, price: cents(1000))],
            subtotal: cents(1234), tax: cents(100), total: cents(1334),
            source: .appleIntelligence
        )
        XCTAssertEqual(missing.itemsForSplit().map(\.price), [cents(1000), cents(234)])
        XCTAssertEqual(missing.itemsForSplit().last?.name, ReceiptDraft.otherItemsName)
        XCTAssertTrue(missing.issues.contains(.itemsAdjusted(by: cents(234))))
    }

    func testQuantitiesExpandIntoUnitsWithExactCents() {
        let draft = ReceiptDraft(items: [.init(name: "Dumplings", quantity: 3, price: cents(1000)),
                                         .init(name: "Napkins", quantity: 40, price: cents(200))],
                                 source: .appleIntelligence)
        let items = draft.itemsForSplit()
        XCTAssertEqual(items.filter { $0.name == "Dumplings" }.map(\.price), [cents(334), cents(333), cents(333)])
        XCTAssertEqual(items.filter { $0.name == "Napkins" }.count, 1)
        XCTAssertEqual(items.reduce(Money.zero) { $0 + $1.price }, cents(1200))
        XCTAssertEqual(draft.itemsForSplit(expandingQuantities: false).count, 2)
    }

    func testSplitTaxIncludesFeesBetweenSubtotalAndTotal() {
        let draft = ReceiptDraft(items: [.init(name: "Pizza", quantity: 1, price: cents(2000))],
                                 subtotal: cents(2000), tax: cents(160), total: cents(2210),
                                 source: .appleIntelligence)
        XCTAssertEqual(draft.taxForSplit, cents(210))
        XCTAssertEqual(draft.issues, [.totalMismatch(calculated: cents(2160), printed: cents(2210))])
    }

    func testIssuesFlagMissingTotalAndForeignCurrency() {
        let draft = ReceiptDraft(currencyCode: "XTS", source: .appleIntelligence)
        XCTAssertEqual(draft.issues, [.totalNotFound, .differentCurrency("XTS")])
    }

    func testCategoryListMatchesExpenseCategories() {
        XCTAssertEqual(ReceiptDraft.categoryNames, Expense.categories.map(\.name))
    }

    func testSuggestedNoteNamesMerchantAndFirstItems() {
        let draft = ReceiptDraft(merchant: "Harbor Noodle House",
                                 items: ["Noodles", "Dumplings", "Tea", "Rice"].map { .init(name: $0, quantity: 1, price: cents(100)) },
                                 source: .appleIntelligence)
        XCTAssertEqual(draft.suggestedNote, L10n.isZh
            ? "Harbor Noodle House\nNoodles, Dumplings, Tea 等 4 项"
            : "Harbor Noodle House\nNoodles, Dumplings, Tea +1 more")
    }

    // MARK: - Recorded model outputs

    // These drafts copy what Apple's on-device model returned for fictional
    // receipts during development (macOS 27 host model, October 2026). They pin
    // down how DailySpend corrects the mistakes it actually makes.

    func testCouponReadAsBothItemAndDiscountIsSubtractedOnce() {
        let draft = ReceiptDraft(
            merchant: "TRADER JOE'S",
            items: [.init(name: "BANANAS", quantity: 1, price: cents(99)),
                    .init(name: "ORGANIC MILK", quantity: 1, price: cents(429)),
                    .init(name: "SOURDOUGH BREAD", quantity: 1, price: cents(399)),
                    .init(name: "COUPON BREAD", quantity: 1, price: cents(-100))],
            subtotal: cents(827), discount: cents(-100), tax: .zero, total: cents(827),
            category: "Food", source: .appleIntelligence
        ).reconciled()
        XCTAssertEqual(draft.discount, cents(100))
        XCTAssertEqual(draft.amountToRecord, cents(827))
        XCTAssertEqual(draft.itemsForSplit().reduce(Money.zero) { $0 + $1.price }, cents(827))
        XCTAssertTrue(draft.issues.isEmpty)
    }

    func testServiceChargeReadAsBothTaxAndTipIsCountedOnce() {
        let draft = ReceiptDraft(
            merchant: "海底捞火锅", currencyCode: "CNY",
            items: [.init(name: "番茄锅底", quantity: 1, price: cents(6800)),
                    .init(name: "肥牛", quantity: 2, price: cents(9600)),
                    .init(name: "虾滑", quantity: 1, price: cents(3800))],
            subtotal: cents(20200), tax: cents(2020), tip: cents(2020), total: cents(22220),
            category: "Food", source: .appleIntelligence
        ).reconciled()
        XCTAssertNil(draft.tip)
        XCTAssertEqual(draft.taxForSplit, cents(2020))
        XCTAssertEqual(draft.amountToRecord, cents(22220))
        XCTAssertFalse(draft.issues.contains { if case .totalMismatch = $0 { return true } else { return false } })
    }

    func testUnitPriceIsReplacedByLineTotalOnlyWhenItMatchesTheSubtotal() {
        let draft = ReceiptDraft(
            merchant: "CVS pharmacy",
            items: [.init(name: "ADVIL 24CT", quantity: 1, price: cents(949)),
                    .init(name: "VITAMIN D3", quantity: 1, price: cents(1299)),
                    .init(name: "COUGH DROPS", quantity: 2, price: cents(349)),
                    .init(name: "EXTRABUCKS REWARD", quantity: 1, price: cents(-200))],
            subtotal: cents(2746), discount: cents(-200), tax: cents(189), total: cents(2935),
            category: "Health", source: .appleIntelligence
        ).reconciled()
        XCTAssertEqual(draft.items.map(\.price), [cents(949), cents(1299), cents(698)])
        XCTAssertFalse(draft.itemsForSplit().contains { $0.name == ReceiptDraft.otherItemsName })
        XCTAssertTrue(draft.issues.isEmpty)

        // A quantity that doesn't explain the gap leaves prices untouched.
        let unrelated = ReceiptDraft(items: [.init(name: "Tea", quantity: 3, price: cents(300))],
                                     subtotal: cents(500), source: .appleIntelligence).reconciled()
        XCTAssertEqual(unrelated.items.map(\.price), [cents(300)])
    }

    func testMislabeledFeesStillRecordTheTotalAndAreFlagged() {
        let draft = ReceiptDraft(
            merchant: "Uber",
            items: [.init(name: "Trip fare", quantity: 1, price: cents(1840))],
            subtotal: cents(1840), discount: cents(285), tax: cents(193), tip: cents(193), total: cents(2318),
            category: "Transport", source: .appleIntelligence
        ).reconciled()
        XCTAssertEqual(draft.amountToRecord, cents(2318))
        XCTAssertEqual(draft.category, "Transport")
        XCTAssertTrue(draft.issues.contains(.totalMismatch(calculated: cents(2226), printed: cents(2318))))
        // A split still adds up to what was paid.
        let splitTotal = draft.itemsForSplit().reduce(Money.zero) { $0 + $1.price } + (draft.taxForSplit ?? .zero) + (draft.tip ?? .zero)
        XCTAssertEqual(splitTotal, cents(2318))
    }

    // MARK: - Splitting a scanned receipt

    func testScannedReceiptSplitReconcilesToThePrintedTotal() {
        let session = SplitSession()
        session.addPerson(name: "Avery")
        session.addPerson(name: "Jordan")
        let draft = ReceiptDraft(
            merchant: "Harbor Noodle House",
            items: [.init(name: "Noodles", quantity: 1, price: cents(1650)),
                    .init(name: "Dumplings", quantity: 2, price: cents(1800)),
                    .init(name: "Tea", quantity: 1, price: cents(450))],
            subtotal: cents(3900), tax: cents(351), tip: cents(700), total: cents(4951),
            source: .appleIntelligence
        )
        session.apply(draft, replacingItems: true)

        XCTAssertEqual(session.items.count, 4, "Two dumplings become two assignable units")
        XCTAssertTrue(session.items.allSatisfy { $0.involvedPersonIDs.count == 3 })
        XCTAssertEqual(session.taxAmount, 3.51)
        XCTAssertEqual(session.tipSelection, TipPreset.fixedAmount)
        XCTAssertEqual(session.customFixedTip, 7)
        XCTAssertEqual(Money(session.grandTotal), cents(4951))

        // Make the noodles Avery's alone; every cent still adds up.
        session.togglePerson(session.people[0].id, inItem: session.items[0].id)
        session.togglePerson(session.people[2].id, inItem: session.items[0].id)
        let paid = session.people.map { Money(session.finalTotal(for: $0)) }.reduce(.zero, +)
        XCTAssertEqual(paid, cents(4951))
        XCTAssertTrue(session.isReadyToSettle)
        XCTAssertTrue(session.generateNote(for: session.people[1]).hasPrefix("Harbor Noodle House\n"))
        XCTAssertEqual(session.makeReceiptData().title, "Harbor Noodle House")

        // Adding a second receipt keeps the first and adds its tax.
        session.apply(ReceiptDraft(items: [.init(name: "Cake", quantity: 1, price: cents(500))],
                                   subtotal: cents(500), tax: cents(45), total: cents(545),
                                   source: .appleIntelligence),
                      replacingItems: false)
        XCTAssertEqual(session.items.count, 5)
        XCTAssertEqual(session.taxAmount, 3.96)
        XCTAssertEqual(session.merchant, "Harbor Noodle House")
    }

    func testPeopleAddedAfterScanningJoinItemsSharedByEveryone() {
        let session = SplitSession()
        session.apply(ReceiptDraft(items: [.init(name: "Pizza", quantity: 1, price: cents(2000))],
                                   source: .appleIntelligence),
                      replacingItems: true)
        session.addItem(name: "Soda", price: 3, assignedTo: [])
        session.addPerson(name: "Avery")
        session.addItem(name: "Salad", price: 9, assignedTo: [session.people[1].id])
        session.addPerson(name: "Jordan")

        XCTAssertEqual(session.peopleIncluded(in: session.items[0]).map(\.name),
                       [SplitSession.defaultFirstPersonName, "Avery", "Jordan"])
        XCTAssertTrue(session.items[1].involvedPersonIDs.isEmpty, "Unassigned items stay unassigned")
        XCTAssertEqual(session.peopleIncluded(in: session.items[2]).map(\.name), ["Avery"], "Personal items stay personal")
    }

    func testEveryoneChipSelectsAndClearsAllPeople() {
        let session = SplitSession()
        session.addPerson(name: "Avery")
        session.addItem(name: "Fries", price: 6, assignedTo: [session.people[1].id])
        XCTAssertFalse(session.isEveryoneIncluded(in: session.items[0]))
        session.toggleEveryone(inItem: session.items[0].id)
        XCTAssertTrue(session.isEveryoneIncluded(in: session.items[0]))
        session.toggleEveryone(inItem: session.items[0].id)
        XCTAssertTrue(session.items[0].involvedPersonIDs.isEmpty)
        XCTAssertFalse(session.isReadyToSettle)
    }

    // MARK: - End to end on this device

    /// Records whether this runtime offers the on-device model, so a run's
    /// evidence says which receipt path the end-to-end test exercised.
    func testRecordsAppleIntelligenceAvailability() {
        var description = "status=\(ReceiptIntelligenceStatus.current)"
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            description += " availability=\(SystemLanguageModel.default.availability)"
            description += " supportsLocale=\(SystemLanguageModel.default.supportsLocale())"
        }
        #endif
        let attachment = XCTAttachment(string: description)
        attachment.name = "Apple Intelligence availability"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Runs the on-device model on recognized rows. Runtimes whose model can't
    /// load are skipped with the reason recorded; a model that does run must
    /// read the receipt correctly.
    func testModelReadsRecognizedReceiptRows() async throws {
        guard #available(iOS 26.0, *), ReceiptIntelligenceStatus.current == .ready else {
            throw XCTSkip("Apple Intelligence isn't available on this runtime")
        }
        let rows = ["HARBOR NOODLE HOUSE", "88 Pier St, Seattle WA", "10/24/2026 | 7:42 PM",
                    "2 | Dumplings | 18.00", "Spicy Beef Noodles | 16.50", "Jasmine Tea | 4.50",
                    "Subtotal | 39.00", "Tax 9% | 3.51", "Total | 42.51",
                    "Suggested Tip: | 18% $7.02 | 20% $7.80", "VISA ****1234 | 42.51"]
        let draft: ReceiptDraft
        do {
            draft = try await ReceiptModelExtractor().extract(rows: rows)
        } catch {
            throw XCTSkip("The on-device model couldn't run here: \(error)")
        }
        let attachment = XCTAttachment(string: "merchant=\(draft.merchant ?? "-") date=\(String(describing: draft.date)) items=\(draft.items.map { "\($0.name) x\($0.quantity) \($0.price.amount)" }) subtotal=\(String(describing: draft.subtotal?.amount)) tax=\(String(describing: draft.tax?.amount)) tip=\(String(describing: draft.tip?.amount)) total=\(String(describing: draft.total?.amount)) category=\(draft.category ?? "-") issues=\(draft.issues)")
        attachment.name = "Model output for recognized rows"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertEqual(draft.amountToRecord, cents(4251))
        XCTAssertEqual(draft.subtotal, cents(3900))
        XCTAssertEqual(draft.tax, cents(351))
        XCTAssertNil(draft.tip, "A suggested tip that wasn't charged is ignored")
        XCTAssertEqual(draft.itemsTotal, cents(3900))
        XCTAssertEqual(draft.category, "Food")
        XCTAssertEqual(draft.isTippedService, true)
        XCTAssertEqual(draft.merchant, "Harbor Noodle House")
    }

    /// Renders a fictional receipt, then runs the real Vision and model path.
    /// Without Apple Intelligence it still has to find the printed total.
    func testReaderReadsARenderedReceipt() async throws {
        let rows: [(String, String)] = [
            ("HARBOR NOODLE HOUSE", ""),
            ("2026-10-24", ""),
            ("Spicy Beef Noodles", "16.50"),
            ("Dumplings", "18.00"),
            ("Jasmine Tea", "4.50"),
            ("Subtotal", "39.00"),
            ("Tax", "3.51"),
            ("Total", "42.51")
        ]
        for tilt in [0, 0.035] as [CGFloat] {
            let page = try XCTUnwrap(Self.renderReceipt(rows, tilt: tilt))
            let recognized = try await ReceiptReader.recognizeText(in: [page])
            let recognizedRows = recognized.flatMap(ReceiptTextLayout.rows(from:))
            XCTAssertTrue(recognizedRows.contains("Dumplings | 18.00"), "Names and prices share a row at tilt \(tilt)")
            let rowsAttachment = XCTAttachment(string: recognizedRows.joined(separator: "\n"))
            rowsAttachment.name = "Recognized rows, tilt \(tilt)"
            rowsAttachment.lifetime = .keepAlways
            add(rowsAttachment)
            let draft = try await ReceiptReader().read([page])
            try checkRenderedReceipt(draft, tilt: tilt)
        }
    }

    /// A Chinese receipt must not be read as Latin characters.
    func testReaderReadsARenderedChineseReceipt() async throws {
        let rows: [(String, String)] = [
            ("海底捞火锅", ""),
            ("番茄锅底", "68.00"),
            ("肥牛", "96.00"),
            ("虾滑", "38.00"),
            ("小计", "202.00"),
            ("服务费", "20.20"),
            ("合计", "222.20")
        ]
        let page = try XCTUnwrap(Self.renderReceipt(rows))
        let recognizedRows = try await ReceiptReader.recognizeText(in: [page]).flatMap(ReceiptTextLayout.rows(from:))
        XCTAssertTrue(recognizedRows.contains("肥牛 | 96.00"), "Recognized: \(recognizedRows)")
        let draft = try await ReceiptReader().read([page])
        XCTAssertEqual(draft.amountToRecord, cents(22220))
        let attachment = XCTAttachment(string: "source=\(draft.source) merchant=\(draft.merchant ?? "-") items=\(draft.items.map { "\($0.name) \($0.price.amount)" }) category=\(draft.category ?? "-") issues=\(draft.issues)")
        attachment.name = "Rendered Chinese receipt result"
        attachment.lifetime = .keepAlways
        add(attachment)
        if draft.source == .appleIntelligence {
            XCTAssertEqual(draft.merchant, "海底捞火锅")
            XCTAssertEqual(draft.itemsTotal, cents(20200))
        }
    }

    private func checkRenderedReceipt(_ draft: ReceiptDraft, tilt: CGFloat) throws {
        XCTAssertEqual(draft.amountToRecord, cents(4251), "tilt \(tilt)")

        let attachment = XCTAttachment(string: "source=\(draft.source) merchant=\(draft.merchant ?? "-") items=\(draft.items.map { "\($0.name) \($0.price.amount)" }) tax=\(draft.tax?.amount ?? 0) category=\(draft.category ?? "-") issues=\(draft.issues)")
        attachment.name = "Rendered receipt result, tilt \(tilt)"
        attachment.lifetime = .keepAlways
        add(attachment)

        if draft.source == .appleIntelligence {
            XCTAssertEqual(draft.itemsTotal, cents(3900), "tilt \(tilt)")
            XCTAssertEqual(draft.tax, cents(351), "tilt \(tilt)")
            XCTAssertEqual(draft.items.count, 3, "tilt \(tilt)")
            XCTAssertEqual(draft.merchant?.localizedCaseInsensitiveContains("harbor"), true, "tilt \(tilt)")
        }
    }

    /// Draws the receipt on white paper; a tilt rotates it like a crooked photo.
    private static func renderReceipt(_ rows: [(String, String)], tilt: CGFloat = 0) -> ReceiptPage? {
        let size = CGSize(width: 640, height: 120 + CGFloat(rows.count) * 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: tilt)
            context.cgContext.scaleBy(x: 0.92, y: 0.92)
            context.cgContext.translateBy(x: -size.width / 2, y: -size.height / 2)
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 28, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            for (index, row) in rows.enumerated() {
                let y = 60 + CGFloat(index) * 64
                (row.0 as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: attributes)
                let price = row.1 as NSString
                let width = price.size(withAttributes: attributes).width
                price.draw(at: CGPoint(x: size.width - 40 - width, y: y), withAttributes: attributes)
            }
        }
        return image.cgImage.map { ReceiptPage(image: $0, orientation: .up) }
    }
}
