import XCTest
@testable import DailySpend

/// The Insights summary for each period, with "now" fixed at Monday,
/// October 26, 2026, 3 PM. Month names are written in the device's time
/// zone, so the tests use the device calendar too.
final class PeriodRecapTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private var now: Date { date(10, 26, hour: 15) }

    private func recordIn(_ year: Int, _ cents: Int64, _ category: String, _ month: Int, _ day: Int) -> SpendingRecord {
        SpendingRecord(money: Money(minorUnits: cents), category: category, note: "",
                       date: calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!)
    }

    private func record(_ cents: Int64, _ category: String, _ month: Int, _ day: Int, note: String = "", hour: Int = 12) -> SpendingRecord {
        SpendingRecord(money: Money(minorUnits: cents), category: category, note: note, date: date(month, day, hour: hour))
    }

    private func month(_ date: Date) -> SpendingPeriod { .month(containing: date, now: now, calendar: calendar) }

    private func monthChange(_ records: [SpendingRecord], now: Date? = nil) -> (amount: Money, driver: String, driverChange: Money)? {
        recap(records, .monthToDate(now: now ?? self.now, calendar: calendar))?.change
    }

    private func recap(_ records: [SpendingRecord], _ period: SpendingPeriod, budget: Money? = nil) -> PeriodRecap? {
        PeriodRecap.make(records: records, period: period, budget: budget, calendar: calendar)
    }

    private var thisMonth: SpendingPeriod { .monthToDate(now: now, calendar: calendar) }

    // MARK: This month against the same days last month

    func testThisMonthComparesTheSameDaysOfEachMonth() throws {
        let records = [
            record(5000, "Food", 10, 3), record(3000, "Transport", 10, 20),
            record(10000, "Food", 10, 27),              // after today: not counted yet
            record(2000, "Food", 9, 5), record(1000, "Grocery", 9, 25),
            record(50000, "Food", 9, 27)                // after the same day last month: not counted
        ]
        let change = try XCTUnwrap(monthChange(records))
        XCTAssertEqual(change.amount, Money(minorUnits: 5000))
        // Food and Transport both rose by $30; ties always name the same one.
        XCTAssertEqual(change.driver, "Food")
        XCTAssertEqual(change.driverChange, Money(minorUnits: 3000))
    }

    func testWholeDaysAreCompared() throws {
        // Saved late in the day: the time an expense was saved never matters.
        let records = [record(100, "Food", 9, 1), record(500, "Food", 9, 26, hour: 22), record(1000, "Food", 10, 26, hour: 22)]
        let summary = try XCTUnwrap(recap(records, thisMonth))
        XCTAssertEqual(summary.total, Money(minorUnits: 1000), "All of today counts")
        XCTAssertEqual(summary.previousTotal, Money(minorUnits: 600), "All of the same day last month counts")

        // On March 31, the same day in February is its last day.
        let march31 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 12))!
        let leap = [recordIn(2026, 700, "Food", 2, 1), recordIn(2026, 300, "Food", 2, 28), recordIn(2026, 2000, "Food", 3, 5)]
        XCTAssertEqual(recap(leap, .monthToDate(now: march31, calendar: calendar))?.previousTotal, Money(minorUnits: 1000))
    }

    func testThisMonthNamesTheBiggestDrop() throws {
        let change = try XCTUnwrap(monthChange([record(1000, "Food", 10, 2), record(9000, "Shopping", 9, 2), record(1500, "Food", 9, 3)]))
        XCTAssertEqual(change.amount, Money(minorUnits: -9500))
        XCTAssertEqual(change.driver, "Shopping")
    }

    func testThisMonthStaysQuietWithoutAMeaningfulChange() throws {
        XCTAssertNil(monthChange([]))
        let close = [record(1050, "Food", 10, 2), record(1000, "Food", 9, 2)]
        XCTAssertNil(monthChange(close), "Under $1 apart is no change")
        let summary = try XCTUnwrap(recap(close, thisMonth))
        XCTAssertTrue(summary.isAboutTheSame)
        if !L10n.isZh { XCTAssertEqual(RecapText.headlineCaption(for: summary), "About the same as this time last month") }
    }

    // MARK: Without a fair comparison

    func testFirstMonthShowsItsOwnTotal() throws {
        let records = [record(1200, "Food", 10, 2), record(3000, "Shopping", 10, 9), record(2500, "Food", 10, 20),
                       record(9900, "Food", 10, 28)]   // dated later this month
        let summary = try XCTUnwrap(recap(records, thisMonth))
        XCTAssertEqual(summary.total, Money(minorUnits: 6700))
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.laterThisMonth, Money(minorUnits: 9900), "Home counts it; Details says so")
        XCTAssertNil(summary.previousTotal, "A first month has nothing to compare with")
        XCTAssertNil(summary.change, "…so it isn't shown as up from zero")
        XCTAssertNil(recap(records, month(date(9, 1))))
        guard !L10n.isZh else { return }
        XCTAssertEqual(RecapText.title(for: summary.period), "October So Far")
        XCTAssertEqual(RecapText.headline(for: summary).text, "$67")
        XCTAssertEqual(RecapText.headlineCaption(for: summary), "spent so far")
        XCTAssertEqual(RecapText.quickLines(for: summary), ["3 expenses", "Most on Food"])
        XCTAssertEqual(RecapText.summary(for: summary), "You’ve spent $67.00 in October so far. Food is your biggest category at $37.00.")
        XCTAssertEqual(RecapText.facts(for: summary).last, "Plus $99.00 dated later in October, counted once that day comes")
    }

    func testStartingPartwayThroughLastMonthIsNotAComparison() throws {
        // Started tracking on September 20: Oct 1–26 against Sep 1–26 would be "more than nothing".
        let late = [record(5000, "Food", 9, 20), record(3000, "Food", 10, 5)]
        XCTAssertNil(try XCTUnwrap(recap(late, thisMonth)).previousTotal)
        // Tracking from early September is a fair comparison.
        let early = [record(100, "Food", 9, 4), record(5000, "Food", 9, 20), record(3000, "Food", 10, 5)]
        XCTAssertEqual(try XCTUnwrap(recap(early, thisMonth)).previousTotal, Money(minorUnits: 5100))
    }

    // MARK: The quick look

    func testThisMonthReadsAsOneSentence() throws {
        let records = [record(1200, "Food", 10, 2), record(800, "Food", 9, 3)]
        let summary = try XCTUnwrap(recap(records, thisMonth, budget: Money(minorUnits: 5000)))
        XCTAssertEqual(RecapText.headline(for: summary).tone, .up)
        guard !L10n.isZh else { return }
        XCTAssertEqual(RecapText.headline(for: summary).text, "$4 more")
        XCTAssertEqual(RecapText.headlineCaption(for: summary), "than this time last month")
        XCTAssertEqual(RecapText.quickLines(for: summary), ["You’ve spent $12", "Food is up $4"])
        XCTAssertEqual(RecapText.facts(for: summary), [
            "Spent $12.00 in October so far across 1 expense",
            "50% more than the same days of September, which came to $8.00",
            "Food is 100% of your spending so far ($12.00)",
            "Food rose the most: up $4.00 from the same days of September",
            "Largest expense: $12.00, Food (Oct 2)",
            "Budget $50.00: $38.00 left"
        ])
        // Each amount sits next to what it belongs to.
        XCTAssertEqual(RecapText.summary(for: summary),
                       "You’ve spent $12.00 in October so far, 50% more than the same days of September ($8.00). Food rose the most, up $4.00. You have $38.00 left of your $50.00 budget.")
    }

    func testTheSummaryNeverContradictsTheHeadline() throws {
        // Total up $10: Food rose most, but Shopping fell even more.
        let records = [record(6000, "Food", 10, 2), record(5000, "Transport", 10, 3), record(2000, "Shopping", 10, 4),
                       record(1000, "Food", 9, 2), record(1000, "Transport", 9, 3), record(10000, "Shopping", 9, 4)]
        let summary = try XCTUnwrap(recap(records, thisMonth))
        let change = try XCTUnwrap(summary.change)
        XCTAssertEqual(change.driver, "Food", "The category that moved the total")
        XCTAssertEqual(summary.otherWayMover?.category, "Shopping")
        guard !L10n.isZh else { return }
        XCTAssertEqual(RecapText.quickLines(for: summary), ["You’ve spent $130", "Food is up $50"])
        let facts = RecapText.facts(for: summary)
        XCTAssertTrue(facts.contains("Food rose the most: up $50.00 from the same days of September"))
        XCTAssertTrue(facts.contains("Shopping went the other way: down $80.00 from the same days of September"))
    }

    func testNoPercentEarlyInTheMonthOrFromATinyStart() throws {
        // October 2: rent on the 1st against small spending on Sep 1–2.
        let october2 = date(10, 2, hour: 15)
        let early = [record(180_000, "Housing", 10, 1), record(1000, "Food", 9, 1)]
        let first = try XCTUnwrap(recap(early, .monthToDate(now: october2, calendar: calendar)))
        XCTAssertNil(first.percentChange, "Two days is too early for a percentage")
        XCTAssertEqual(first.change?.amount, Money(minorUnits: 179_000), "The amount still shows")
        // Later in the month, but from $5 to $200.
        let tiny = try XCTUnwrap(recap([record(20000, "Food", 10, 5), record(500, "Food", 9, 2)], thisMonth))
        XCTAssertNil(tiny.percentChange, "+3,900% says nothing useful")
        guard !L10n.isZh else { return }
        XCTAssertEqual(RecapText.facts(for: first)[1], "$1,790.00 more than the same days of September, which came to $10.00")
        XCTAssertEqual(RecapText.tiles(for: tiny).last?.value, "+$195.00")
    }

    // MARK: Longer periods

    func testRecentMonthsCompareWithTheMonthsBefore() throws {
        // Last 3 months: Jul 27 through today. The 3 before: Apr 27 to Jul 27.
        let records = [record(4000, "Food", 10, 1), record(2000, "Transport", 8, 1),
                       record(1000, "Food", 7, 25), record(2000, "Food", 5, 1), record(9999, "Food", 4, 20)]
        let summary = try XCTUnwrap(recap(records, .recentMonths(3, now: now, calendar: calendar), budget: Money(minorUnits: 100)))
        XCTAssertEqual(summary.total, Money(minorUnits: 6000))
        XCTAssertEqual(summary.previousTotal, Money(minorUnits: 3000))
        XCTAssertEqual(summary.change?.amount, Money(minorUnits: 3000))
        XCTAssertNil(summary.budget, "A monthly budget isn't measured against 3 months")
        guard !L10n.isZh else { return }
        XCTAssertEqual(RecapText.title(for: summary.period), "Last 3 Months")
        XCTAssertEqual(RecapText.facts(for: summary)[1], "100% more than the 3 months before, which came to $30.00")
        XCTAssertEqual(RecapText.headlineCaption(for: summary), "than the 3 months before")
        XCTAssertEqual(RecapText.quickLines(for: summary), ["You’ve spent $60", "Transport is up $20"])
    }

    func testYearSoFarComparesWithTheSameDatesLastYear() throws {
        let records = [record(5000, "Food", 3, 1), record(2000, "Food", 10, 26, hour: 10),
                       recordIn(2025, 1000, "Food", 1, 2), recordIn(2025, 12000, "Food", 6, 1), recordIn(2025, 50000, "Food", 11, 1)]
        let summary = try XCTUnwrap(recap(records, .yearToDate(now: now, calendar: calendar)))
        XCTAssertEqual(summary.total, Money(minorUnits: 7000))
        XCTAssertEqual(summary.previousTotal, Money(minorUnits: 13000), "Only last year up to the same date")
        XCTAssertEqual(summary.change?.amount, Money(minorUnits: -6000))
        guard !L10n.isZh else { return }
        XCTAssertEqual(RecapText.title(for: summary.period), "2026 So Far")
        XCTAssertEqual(RecapText.headline(for: summary).text, "$60 less")
        XCTAssertEqual(RecapText.headlineCaption(for: summary), "than this time last year")
    }

    func testAllTimeHasNothingToCompare() throws {
        let records = [record(5000, "Food", 3, 1), recordIn(2025, 12000, "Shopping", 6, 1)]
        let summary = try XCTUnwrap(recap(records, .allTime(now: now), budget: Money(minorUnits: 100)))
        XCTAssertEqual(summary.total, Money(minorUnits: 17000))
        XCTAssertNil(summary.change)
        XCTAssertNil(summary.budget)
        guard !L10n.isZh else { return }
        XCTAssertEqual(RecapText.headlineCaption(for: summary), "spent")
        XCTAssertEqual(RecapText.quickLines(for: summary), ["2 expenses", "Most on Shopping"])
    }

    func testTheCurrentMonthChosenFromTheCalendarRunsToToday() {
        XCTAssertEqual(SpendingPeriod.month(containing: date(10, 3), now: now, calendar: calendar).kind, .monthToDate)
        XCTAssertEqual(SpendingPeriod.month(containing: date(9, 3), now: now, calendar: calendar).kind, .month)
    }

    func testDetailsTilesShowTheKeyNumbers() throws {
        let records = [record(1200, "Food", 10, 2), record(800, "Food", 9, 3)]
        let recap = try XCTUnwrap(PeriodRecap.make(records: records, period: .monthToDate(now: now, calendar: calendar), budget: nil))
        let tiles = RecapText.tiles(for: recap)
        XCTAssertEqual(tiles.map(\.tone), [.plain, .plain, .up])
        let first = try XCTUnwrap(PeriodRecap.make(records: [record(1200, "Food", 10, 2)],
                                                   period: .monthToDate(now: now, calendar: calendar), budget: nil))
        XCTAssertEqual(RecapText.tiles(for: first).count, 2, "A first month shows its total and count")
        guard !L10n.isZh else { return }
        XCTAssertEqual(tiles.map(\.label), ["So far", "Same days, Sep", "Change"])
        XCTAssertEqual(tiles.map(\.value), ["$12.00", "$8.00", "+50%"])
        XCTAssertEqual(RecapText.tiles(for: first).map(\.value), ["$12.00", "1"])
    }

    /// October so far: down overall, Shopping down, Food up.
    private func mixedMonth() throws -> PeriodRecap {
        try XCTUnwrap(recap([record(2000, "Food", 10, 2), record(1000, "Shopping", 10, 3),
                             record(1000, "Food", 9, 2), record(9000, "Shopping", 9, 3)], thisMonth))
    }

    func testTheModelsSentenceCanOnlyAddWordsNotNumbers() throws {
        let month = try mixedMonth()
        XCTAssertTrue(RecapText.isSafeInsight("Most of the drop came from spending less on Shopping.", for: month))
        XCTAssertTrue(RecapText.isSafeInsight("Shopping is down, which explains most of the change.", for: month))
        XCTAssertTrue(RecapText.isSafeInsight("Food is where more of your money is going.", for: month))
        XCTAssertFalse(RecapText.isSafeInsight("Shopping fell by $80.00.", for: month), "No numbers at all")
        XCTAssertFalse(RecapText.isSafeInsight("Shopping fell by 89%.", for: month), "No percentages")
        XCTAssertFalse(RecapText.isSafeInsight("Shopping rose this month.", for: month), "Wrong direction")
        XCTAssertFalse(RecapText.isSafeInsight("Food is down this month.", for: month), "Wrong direction")
        XCTAssertFalse(RecapText.isSafeInsight("Your spending is higher than last month.", for: month), "Total went down")
        XCTAssertFalse(RecapText.isSafeInsight("Housing explains the change.", for: month), "Not spent on this period")
        XCTAssertFalse(RecapText.isSafeInsight("Shopping fell. Food rose.", for: month), "One sentence only")
        XCTAssertFalse(RecapText.isSafeInsight("Shopping fell while Food rose.", for: month), "One direction per sentence")
        XCTAssertFalse(RecapText.isSafeInsight("  ", for: month))
        // Without a comparison, nothing can be "up" or "down".
        let first = try XCTUnwrap(recap([record(1200, "Food", 10, 2)], thisMonth))
        XCTAssertTrue(RecapText.isSafeInsight("Food is where your money went.", for: first))
        XCTAssertFalse(RecapText.isSafeInsight("Food is up this month.", for: first))
        XCTAssertTrue(RecapText.isSafeInsight("购物支出的减少是主要原因。", for: month))
        XCTAssertFalse(RecapText.isSafeInsight("购物支出增加了。", for: month))
    }

    func testDetailsKeepTheAppsNumbersAndAddTheModelsSentence() throws {
        let month = try mixedMonth()
        let signature = RecapWording.signature(for: RecapText.facts(for: month))
        let summary = RecapText.summary(for: month)
        let written = RecapWording(text: "Most of the drop came from Shopping.", isFromModel: true, factsSignature: signature)
        XCTAssertEqual(written.paragraph(for: month), summary + " Most of the drop came from Shopping.")
        XCTAssertEqual(RecapWording(text: "", isFromModel: false, factsSignature: signature).paragraph(for: month), summary)
    }

    func testLongNotesAreShortenedInTheSummary() {
        let long = record(5000, "Food", 9, 3, note: "Dinner with the whole team after the quarterly planning offsite downtown")
        let label = RecapText.biggestLabel(long)
        XCTAssertLessThanOrEqual(label.count, 32)
        XCTAssertTrue(label.hasPrefix("Dinner with the whole team"))
        XCTAssertEqual(RecapText.biggestLabel(record(5000, "Food", 9, 3, note: "KFC\nLunch at KFC 50")), "KFC")
        XCTAssertEqual(RecapText.biggestLabel(record(120000, "Shopping", 10, 3, note: "Shop at Apple 1200")), "Shop at Apple",
                       "The amount isn't repeated in the name")
        XCTAssertEqual(RecapText.biggestLabel(record(1200, "Food", 10, 3, note: "Pier 39 lunch")), "Pier 39 lunch")
    }

    // MARK: Recap facts

    private var septemberRecords: [SpendingRecord] {
        [
            record(18000, "Food", 9, 12, note: "Hudson Lantern Bistro\nFriday dinner"),
            record(4250, "Food", 9, 3), record(6000, "Grocery", 9, 20), record(2500, "Transport", 9, 28),
            // August, the month before
            record(10000, "Food", 8, 10), record(4000, "Shopping", 8, 15), record(2000, "Grocery", 8, 22),
            // October, not part of September's recap
            record(99900, "Housing", 10, 1)
        ]
    }

    func testRecapFactsForTheMonthThatEnded() throws {
        let recap = try XCTUnwrap(PeriodRecap.make(records: septemberRecords, period: month(date(9, 15)), budget: Money(minorUnits: 35000)))
        XCTAssertEqual(recap.total, Money(minorUnits: 30750))
        XCTAssertEqual(recap.count, 4)
        XCTAssertEqual(recap.previousTotal, Money(minorUnits: 16000))
        XCTAssertEqual(recap.percentChange, 92)
        XCTAssertEqual(recap.categories.first?.category, "Food")
        XCTAssertEqual(recap.categories.first?.total, Money(minorUnits: 22250))
        XCTAssertEqual(recap.biggest.money, Money(minorUnits: 18000))
        let change = try XCTUnwrap(recap.change)
        XCTAssertEqual(change.driver, "Food")
        XCTAssertEqual(change.driverChange, Money(minorUnits: 12250))
        XCTAssertNil(recap.otherWayMover)
        XCTAssertTrue(recap.categories.contains { $0.category == "Shopping" && $0.total == .zero },
                      "A category that stopped still counts as a change")

        guard !L10n.isZh else { return }
        XCTAssertEqual(RecapText.facts(for: recap), [
            "Spent $307.50 in September across 4 expenses",
            "92% more than August, which came to $160.00",
            "Food was 72% of your spending ($222.50)",
            "Food rose the most: up $122.50 from August",
            "Largest expense: $180.00, Hudson Lantern Bistro (Sep 12)",
            "Budget $350.00: $42.50 under"
        ])
        XCTAssertEqual(RecapText.summary(for: recap),
                       "You spent $307.50 in September, 92% more than August ($160.00). Food rose the most, up $122.50. You stayed $42.50 under your $350.00 budget.")
    }

    func testRecapWithoutAnEarlierMonthOrBudget() throws {
        let recap = try XCTUnwrap(PeriodRecap.make(records: [record(1200, "Food", 9, 2)], period: month(date(9, 30)), budget: nil))
        XCTAssertNil(recap.previousTotal)
        XCTAssertNil(recap.percentChange)
        XCTAssertNil(recap.change)
        XCTAssertNil(PeriodRecap.make(records: [record(1200, "Food", 9, 2)], period: month(date(7, 1)), budget: nil),
                     "A month with no spending has no recap")
        guard !L10n.isZh else { return }
        XCTAssertEqual(RecapText.summary(for: recap), "You spent $12.00 in September. Food was your biggest category at $12.00.")
        let over = try XCTUnwrap(PeriodRecap.make(records: [record(1200, "Food", 9, 2)], period: month(date(9, 30)), budget: Money(minorUnits: 1000)))
        XCTAssertTrue(RecapText.summary(for: over).hasSuffix("You went $2.00 over your $10.00 budget."))
    }

    // MARK: Keeping the model to the facts

    func testOnlyWordsThatMatchTheFactsAreShown() {
        let facts = ["Spent $307.50 in September across 4 expenses", "92% more than August ($160.00)",
                     "Largest expense: $180.00, Hudson Lantern Bistro (Sep 12)"]
        XCTAssertTrue(RecapText.isFaithful(
            "September came to $307.50 over 4 expenses, 92% more than August. Your largest was $180.00 at Hudson Lantern Bistro on Sep 12.",
            to: facts))
        XCTAssertFalse(RecapText.isFaithful("You spent $310.00 in September.", to: facts), "A changed amount")
        XCTAssertFalse(RecapText.isFaithful("Spending rose 95% from August.", to: facts), "A changed percentage")
        XCTAssertFalse(RecapText.isFaithful("You saved $50.00 on groceries.", to: facts), "An invented number")
        XCTAssertFalse(RecapText.isFaithful("   ", to: facts))
        XCTAssertEqual(RecapText.numbers(in: "$1,240.00 and 12% on 3"), ["1240.00", "12", "3"])
    }

    func testWordingIsKeptForTheMonthUntilTheFactsChange() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PeriodRecapTests"))
        defaults.removePersistentDomain(forName: "PeriodRecapTests")
        defer { defaults.removePersistentDomain(forName: "PeriodRecapTests") }
        let recap = try XCTUnwrap(PeriodRecap.make(records: septemberRecords, period: month(date(9, 15)), budget: nil))
        let facts = RecapText.facts(for: recap)
        RecapWording(text: "Saved words", isFromModel: true, factsSignature: RecapWording.signature(for: facts))
            .store(for: recap, defaults: defaults)
        XCTAssertEqual(RecapWording.cached(for: recap, facts: facts, defaults: defaults)?.text, "Saved words")
        XCTAssertNil(RecapWording.cached(for: recap, facts: facts + ["A late expense"], defaults: defaults),
                     "New facts mean new words")
        RecapWording(text: "Older words", isFromModel: true, factsSignature: facts.joined(separator: "\n"))
            .store(for: recap, defaults: defaults)
        XCTAssertNil(RecapWording.cached(for: recap, facts: facts, defaults: defaults),
                     "Words saved before a wording update are rewritten")
    }

    /// The real on-device model: its words are shown only if faithful.
    func testModelRecapIsFaithfulOrFallsBack() async throws {
        guard ReceiptIntelligenceStatus.current == .ready else { throw XCTSkip("Apple Intelligence isn't available.") }
        let recap = try XCTUnwrap(PeriodRecap.make(records: septemberRecords, period: month(date(9, 15)), budget: Money(minorUnits: 35000)))
        let facts = RecapText.facts(for: recap)
        let wording = await RecapWording.make(for: recap, facts: facts)
        if wording.isFromModel {
            XCTAssertTrue(RecapText.isSafeInsight(wording.text, for: recap), wording.text)
        } else {
            XCTAssertEqual(wording.text, "")
        }
        XCTAssertTrue(wording.paragraph(for: recap).hasPrefix(RecapText.summary(for: recap)), "The app's numbers always come first")
        let soFar = try mixedMonth()
        let soFarWording = await RecapWording.make(for: soFar, facts: RecapText.facts(for: soFar))
        XCTAssertTrue(soFarWording.text.isEmpty || RecapText.isSafeInsight(soFarWording.text, for: soFar), soFarWording.text)
        let attachment = XCTAttachment(string: "fromModel=\(wording.isFromModel)\n\(wording.paragraph(for: recap))\n\nSO FAR fromModel=\(soFarWording.isFromModel)\n\(soFarWording.paragraph(for: soFar))")
        attachment.name = "Period summary wording"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
