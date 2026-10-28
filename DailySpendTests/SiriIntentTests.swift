import SwiftData
import XCTest
@testable import DailySpend

/// The logic behind the Siri and Shortcuts actions, against an in-memory
/// store and separate settings, never a person's real data.
@MainActor
final class SiriIntentTests: XCTestCase {
    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private let suiteName = "SiriIntentTests"

    override func setUp() async throws {
        container = try ModelContainer(for: Expense.self, CategoryBudget.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
    }

    private func cents(_ value: Int64) -> Money { Money(minorUnits: value) }

    func testWordsWithoutAnAmountAreNeverSaved() {
        XCTAssertNil(ExpenseIntentStore.plan(for: QuickEntryParser.parse("lunch with Alex")))
        XCTAssertNil(ExpenseIntentStore.plan(for: QuickEntryParser.parse("")))
    }

    func testAPlanCarriesTheSharePlusTheWords() throws {
        let now = Date()
        let plan = try XCTUnwrap(ExpenseIntentStore.plan(for: QuickEntryParser.parse("lunch with Alex 36, split 3", now: now), now: now))
        XCTAssertEqual(plan.amount, cents(1200))
        XCTAssertEqual(plan.category, "Food")
        XCTAssertTrue(plan.note.hasPrefix("Lunch with Alex\nlunch with Alex 36, split 3"))
        XCTAssertEqual(plan.date, now)

        let unknown = try XCTUnwrap(ExpenseIntentStore.plan(for: QuickEntryParser.parse("thing 12")))
        XCTAssertEqual(unknown.category, "Other", "No category guess leaves it as Other")
    }

    func testSiriReadsBackWhatItWillSave() throws {
        let today = ExpenseIntentStore.Plan(amount: cents(450), category: "Food", note: "coffee 4.50", date: Date())
        let yesterday = ExpenseIntentStore.Plan(amount: cents(2340), category: "Transport", note: "Uber 23.40 yesterday",
                                                date: try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date())))
        if !L10n.isZh {
            XCTAssertEqual(ExpenseIntentStore.confirmation(for: today), "Save “coffee 4.50”: $4.50, Food?")
            XCTAssertEqual(ExpenseIntentStore.confirmation(for: yesterday), "Save “Uber 23.40 yesterday”: $23.40, Transport, yesterday?")
            XCTAssertEqual(ExpenseIntentStore.savedMessage(for: today), "Saved “coffee 4.50”, $4.50.")
        }
    }

    func testSavingCreatesTheSameRecordAsNewExpense() throws {
        let date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let plan = ExpenseIntentStore.Plan(amount: cents(1234), category: "Transport", note: "taxi 12.34", date: date)
        try ExpenseIntentStore.save(plan, in: container)

        let saved = try container.mainContext.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].money, cents(1234))
        XCTAssertEqual(saved[0].amountMinorUnits, 1234, "Exact cents are stored, as New Expense does")
        XCTAssertEqual(saved[0].category, "Transport")
        XCTAssertEqual(saved[0].note, "taxi 12.34")
        XCTAssertEqual(saved[0].date, date)
        XCTAssertEqual(saved[0].frequency, RecurrenceFrequency.none)
    }

    func testMonthSummaryMatchesHomesThisMonthTotal() throws {
        let now = Date()
        let calendar = Calendar.current
        let lastMonth = try XCTUnwrap(calendar.date(byAdding: .month, value: -1, to: now))
        for (cents, date) in [(1250, now), (3000, now), (9900, lastMonth)] {
            container.mainContext.insert(Expense(amount: Double(cents) / 100, amountMinorUnits: Int64(cents),
                                                 category: "Food", note: "", date: date))
        }
        try container.mainContext.save()

        let noBudget = try ExpenseIntentStore.monthSummary(in: container, now: now, defaults: defaults)
        XCTAssertEqual(noBudget.spent, cents(4250), "Last month's expense isn't counted")
        XCTAssertNil(noBudget.remaining)

        defaults.set(true, forKey: "isBudgetEnabled")
        defaults.set(100.0, forKey: "budgetAmount")
        let underBudget = try ExpenseIntentStore.monthSummary(in: container, now: now, defaults: defaults)
        XCTAssertEqual(underBudget.remaining, cents(5750))

        defaults.set(40.0, forKey: "budgetAmount")
        let overBudget = try ExpenseIntentStore.monthSummary(in: container, now: now, defaults: defaults)
        XCTAssertEqual(overBudget.remaining, cents(-250))

        if !L10n.isZh {
            XCTAssertEqual(ExpenseIntentStore.spokenSummary(noBudget), "You’ve spent $42.50 this month.")
            XCTAssertEqual(ExpenseIntentStore.spokenSummary(underBudget),
                           "You’ve spent $42.50 this month, with $57.50 left of your $100.00 budget.")
            XCTAssertEqual(ExpenseIntentStore.spokenSummary(overBudget),
                           "You’ve spent $42.50 this month, $2.50 over your $40.00 budget.")
        }
    }

    func testSirisAmountBecomesExactCents() {
        XCTAssertEqual(ExpenseIntentStore.money(from: Decimal(string: "4.5")!), cents(450))
        XCTAssertEqual(ExpenseIntentStore.money(from: Decimal(string: "4.505")!), cents(451))
        XCTAssertEqual(ExpenseIntentStore.money(from: Decimal(string: "1234.99")!), cents(123_499))
        XCTAssertNil(ExpenseIntentStore.money(from: 0))
        XCTAssertNil(ExpenseIntentStore.money(from: -3))
    }

    /// Siri gives the amount; the words still say what it was, the day, and a split.
    func testSirisAmountWithTheItemWords() throws {
        let now = Date()
        var entry = QuickEntryParser.parse("lunch with Alex split 3 yesterday", now: now)
        entry.total = cents(3600)
        let plan = try XCTUnwrap(ExpenseIntentStore.plan(for: entry, now: now))
        XCTAssertEqual(plan.amount, cents(1200))
        XCTAssertEqual(plan.splitTotal, cents(3600))
        XCTAssertEqual(plan.splitCount, 3)
        XCTAssertEqual(plan.category, "Food")
        XCTAssertTrue(plan.note.hasPrefix("Lunch with Alex\nlunch with Alex split 3 yesterday"))
        if !L10n.isZh {
            XCTAssertEqual(ExpenseIntentStore.confirmation(for: plan),
                           "Save “lunch with Alex split 3 yesterday”: your share, $12.00 of $36.00 split 3 ways, Food, yesterday?")
        }
        XCTAssertTrue(Calendar.current.isDateInYesterday(plan.date))

        var coffee = QuickEntryParser.parse("coffee", now: now)
        coffee.total = cents(450)
        let coffeePlan = try XCTUnwrap(ExpenseIntentStore.plan(for: coffee, now: now))
        XCTAssertEqual(coffeePlan.note, "Coffee", "The note is a short title, like other expenses")
        XCTAssertEqual(coffeePlan.amount, cents(450))
    }

    func testRequestsFromSiriWaitForTheApp() {
        let router = AppRouter.shared
        router.pendingAction = .scanReceipt
        XCTAssertEqual(router.pendingAction, .scanReceipt)
        router.pendingAction = nil
    }
}
