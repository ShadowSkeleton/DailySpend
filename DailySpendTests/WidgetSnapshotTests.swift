import XCTest
@testable import DailySpend

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 12))! }

    func testSnapshotPreservesEveryCentAndExcludesOtherMonths() {
        let expenses = [
            Expense(amount: 0.1, category: "Food", note: "", date: now),
            Expense(amount: 0.2, category: "Food", note: "", date: now),
            Expense(amount: 90, category: "Food", note: "", date: now.addingTimeInterval(-40 * 86400))
        ]
        let snapshot = WidgetDataService.makeSnapshot(expenses: expenses, budget: 20.99,
                                                      isBudgetEnabled: true, hidesAmounts: false,
                                                      now: now, calendar: calendar)
        XCTAssertEqual(snapshot.totalCents, 30)
        XCTAssertEqual(snapshot.budgetCents, 2099)
        XCTAssertEqual(snapshot.chartCents, [0, 0, 0, 0, 0, 0, 30])
    }

    func testLocalizedBillInputNeverDropsDecimalComma() {
        XCTAssertEqual(MoneyTextInput.parse("12,50", locale: Locale(identifier: "de_DE")), 12.5)
        XCTAssertEqual(MoneyTextInput.parse("1.234,56", locale: Locale(identifier: "de_DE")), 1234.56)
        XCTAssertEqual(MoneyTextInput.parse("1,234.56", locale: Locale(identifier: "en_US")), 1234.56)
        XCTAssertNil(MoneyTextInput.parse("12,50", locale: Locale(identifier: "en_US")))
        XCTAssertNil(MoneyTextInput.parse("12.50oops", locale: Locale(identifier: "en_US")))
    }

    func testCSVQuotesEveryFieldAndTreatsFormulasAsText() {
        XCTAssertEqual(CSVDocument.row(["9/4/26, 12:00 PM", "Food", "12.50", "He said \"Hi\"\nAgain"]),
                       "\"9/4/26, 12:00 PM\",\"Food\",\"12.50\",\"He said \"\"Hi\"\"\nAgain\"\r\n")
        XCTAssertEqual(CSVDocument.row(["=1+1", "  @SUM(A1)"]), "\"'=1+1\",\"'  @SUM(A1)\"\r\n")
    }

    func testEditedAndDeletedExpensesProduceCurrentValues() {
        let expense = Expense(amount: 19.99, category: "Food", note: "", date: now)
        func snapshot(_ values: [Expense]) -> WidgetSnapshot {
            WidgetDataService.makeSnapshot(expenses: values, budget: 0, isBudgetEnabled: false,
                                           hidesAmounts: false, now: now, calendar: calendar)
        }
        XCTAssertEqual(snapshot([expense]).totalCents, 1999)
        expense.amount = 2.34
        expense.amountMinorUnits = 234
        XCTAssertEqual(snapshot([expense]).totalCents, 234)
        XCTAssertEqual(snapshot([]).totalCents, 0)
    }

    func testAppLockSnapshotContainsNoBalances() {
        let snapshot = WidgetDataService.makeSnapshot(
            expenses: [Expense(amount: 192.35, category: "Food", note: "Private", date: now)],
            budget: 500, isBudgetEnabled: true, hidesAmounts: true, now: now, calendar: calendar)
        XCTAssertTrue(snapshot.hidesAmounts)
        XCTAssertTrue(snapshot.isValid)
        XCTAssertEqual(snapshot.totalCents, 0)
        XCTAssertEqual(snapshot.budgetCents, 0)
        XCTAssertEqual(snapshot.chartCents, Array(repeating: 0, count: 7))
        XCTAssertFalse(snapshot.isBudgetEnabled)
    }

    func testAtomicRoundTripRemovesLegacyBalances() throws {
        let suite = "DailySpend.WidgetTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        store.set(999.99, forKey: "widget_total")
        let snapshot = WidgetSnapshot.preview
        XCTAssertTrue(snapshot.save(to: store))
        XCTAssertEqual(WidgetSnapshot.load(from: store), snapshot)
        XCTAssertNil(store.object(forKey: "widget_total"))
    }

    func testCorruptAndFutureSchemaSnapshotsFailClosed() throws {
        let suite = "DailySpend.WidgetTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        store.set(Data("broken".utf8), forKey: WidgetSnapshot.storageKey)
        XCTAssertEqual(WidgetSnapshot.load(from: store), .empty)
        var unsupported = WidgetSnapshot.preview
        unsupported.version = 2
        store.set(try JSONEncoder().encode(unsupported), forKey: WidgetSnapshot.storageKey)
        XCTAssertEqual(WidgetSnapshot.load(from: store), .empty)
    }

    func testRejectsNegativeOrPrivateLeakingPayload() {
        XCTAssertFalse(WidgetSnapshot(totalCents: -1, budgetCents: 0, isBudgetEnabled: false,
                                      chartCents: Array(repeating: 0, count: 7), lastUpdated: now,
                                      hasData: true, hidesAmounts: false).isValid)
        XCTAssertFalse(WidgetSnapshot(totalCents: 1, budgetCents: 0, isBudgetEnabled: false,
                                      chartCents: Array(repeating: 0, count: 7), lastUpdated: now,
                                      hasData: true, hidesAmounts: true).isValid)
    }

    func testSnapshotBecomesStaleAtDayAndMonthBoundary() {
        let snapshot = WidgetDataService.makeSnapshot(expenses: [], budget: 0, isBudgetEnabled: false,
                                                      hidesAmounts: false, now: now, calendar: calendar)
        XCTAssertFalse(snapshot.needsRefresh(at: now.addingTimeInterval(3600), calendar: calendar))
        XCTAssertTrue(snapshot.needsRefresh(at: now.addingTimeInterval(86400), calendar: calendar))
        XCTAssertTrue(snapshot.needsRefresh(at: now.addingTimeInterval(31 * 86400), calendar: calendar))
    }
}
