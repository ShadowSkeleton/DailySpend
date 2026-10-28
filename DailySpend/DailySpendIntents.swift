import AppIntents
import Foundation
import SwiftData
import SwiftUI

// MARK: - Routing into the app

/// What Siri, Shortcuts, or Control Center asked the app to open. ContentView
/// takes the request and Home opens it once App Lock allows.
@MainActor
@Observable
final class AppRouter {
    enum Action: Equatable {
        case addExpense
        case scanReceipt
    }

    static let shared = AppRouter()
    var pendingAction: Action?
}

// MARK: - Saving and summing for intents

/// The work behind the Siri actions, kept apart from App Intents so it can be
/// tested against an in-memory store. It uses the app's own container, so a
/// Siri entry is the same kind of record New Expense saves and syncs the same
/// way.
@MainActor
enum ExpenseIntentStore {
    /// What an entry will save, read back before saving.
    struct Plan: Equatable {
        var amount: Money
        var category: String
        var note: String
        var date: Date
        /// The whole bill and how many share it, when the words say "split".
        var splitTotal: Money? = nil
        var splitCount: Int? = nil
        /// The words as Siri heard them, read back so a mishearing is caught.
        var heard: String = ""
    }

    /// Nil when the words have no amount, so Siri asks again instead of guessing.
    static func plan(for entry: QuickEntry, now: Date = Date()) -> Plan? {
        guard let amount = entry.amount, amount > .zero else { return nil }
        var plan = Plan(amount: amount, category: entry.category ?? "Other", note: entry.note, date: entry.date ?? now)
        plan.heard = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let count = entry.splitCount, count > 1 {
            plan.splitTotal = entry.total
            plan.splitCount = count
        }
        return plan
    }

    /// Siri's decimal amount in exact cents; nil unless it's more than zero.
    static func money(from amount: Decimal) -> Money? {
        var cents = amount * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &cents, 0, .plain)
        let minorUnits = NSDecimalNumber(decimal: rounded).int64Value
        return minorUnits > 0 ? Money(minorUnits: minorUnits) : nil
    }

    /// Debug builds keep the last few Siri requests in the app's caches, so
    /// what Siri actually passed can be read from a test device. Release
    /// builds never write them.
    static func recordForDebugging(_ line: String) {
        #if DEBUG
        guard let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let file = folder.appendingPathComponent("siri-requests.txt")
        let previous = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let entry = "\(Date().formatted(.iso8601)) \(line)\n"
        let kept = (previous + entry).split(separator: "\n").suffix(20).joined(separator: "\n") + "\n"
        try? kept.write(to: file, atomically: true, encoding: .utf8)
        #endif
    }

    static func confirmation(for plan: Plan, calendar: Calendar = .current) -> String {
        let amount = plan.amount.amount.formatted(.currency(code: L10n.currencyCode))
        let category = L10n.categoryName(plan.category)
        let words = plan.heard.isEmpty ? (plan.note.split(separator: "\n").first.map(String.init) ?? "") : plan.heard
        let day: String
        if calendar.isDateInToday(plan.date) {
            day = ""
        } else if calendar.isDateInYesterday(plan.date) {
            day = L10n.isZh ? "，昨天" : ", yesterday"
        } else {
            day = (L10n.isZh ? "，" : ", ") + plan.date.formatted(.dateTime.month().day())
        }
        // The words come first, as Siri heard them, so a mishearing such as
        // "launch" for "lunch" is noticed before saying yes.
        let share: String
        if let total = plan.splitTotal, let count = plan.splitCount {
            let whole = total.amount.formatted(.currency(code: L10n.currencyCode))
            share = L10n.isZh ? "你的份额 \(amount)（\(whole) 由 \(count) 人平分）" : "your share, \(amount) of \(whole) split \(count) ways"
        } else {
            share = amount
        }
        return L10n.isZh
            ? "记下“\(words)”：\(share)，\(category)\(day)？"
            : "Save “\(words)”: \(share), \(category)\(day)?"
    }

    static func savedMessage(for plan: Plan) -> String {
        let amount = plan.amount.amount.formatted(.currency(code: L10n.currencyCode))
        let words = plan.note.split(separator: "\n").first.map(String.init) ?? ""
        return L10n.isZh ? "已记下“\(words)”，\(amount)。" : "Saved “\(words)”, \(amount)."
    }

    @discardableResult
    static func save(_ plan: Plan, in container: ModelContainer) throws -> Expense {
        let context = container.mainContext
        let expense = Expense(amount: plan.amount.amount, amountMinorUnits: plan.amount.minorUnits,
                              category: plan.category, note: plan.note, date: plan.date)
        do {
            context.insert(expense)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        refreshWidget(in: context)
        return expense
    }

    /// This month's spending, and what's left when a budget is set.
    struct MonthSummary: Equatable {
        var spent: Money
        var budget: Money?
        var remaining: Money? { budget.map { $0 - spent } }
    }

    static func monthSummary(in container: ModelContainer, now: Date = Date(), calendar: Calendar = .current,
                             defaults: UserDefaults = .standard) throws -> MonthSummary {
        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        // The same rule as Home's "This Month" total.
        let spent = expenses
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(Money.zero) { $0 + Money($1.normalizedAmount) }
        let budgetAmount = defaults.double(forKey: "budgetAmount")
        let hasBudget = defaults.bool(forKey: "isBudgetEnabled") && budgetAmount > 0
        return MonthSummary(spent: spent, budget: hasBudget ? Money(budgetAmount) : nil)
    }

    static func spokenSummary(_ summary: MonthSummary) -> String {
        func currency(_ money: Money) -> String { money.amount.formatted(.currency(code: L10n.currencyCode)) }
        let spent = currency(summary.spent)
        guard let remaining = summary.remaining, let budget = summary.budget else {
            return L10n.isZh ? "本月已花 \(spent)。" : "You’ve spent \(spent) this month."
        }
        if remaining < .zero {
            let over = currency(Money(minorUnits: -remaining.minorUnits))
            return L10n.isZh
                ? "本月已花 \(spent)，超出 \(currency(budget)) 的预算 \(over)。"
                : "You’ve spent \(spent) this month, \(over) over your \(currency(budget)) budget."
        }
        return L10n.isZh
            ? "本月已花 \(spent)，\(currency(budget)) 的预算还剩 \(currency(remaining))。"
            : "You’ve spent \(spent) this month, with \(currency(remaining)) left of your \(currency(budget)) budget."
    }

    /// Siri can save while the app isn't open, so the widget is refreshed
    /// here rather than waiting for the next launch.
    static func refreshWidget(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard let expenses = try? context.fetch(FetchDescriptor<Expense>()) else { return }
        WidgetDataService.saveToWidget(expenses: expenses,
                                      budget: defaults.double(forKey: "budgetAmount"),
                                      isBudgetEnabled: defaults.bool(forKey: "isBudgetEnabled"),
                                      hidesAmounts: defaults.bool(forKey: "isAppLockEnabled"))
    }
}

// MARK: - Intents

/// "Log an expense in DailySpend." Siri asks how much and what it was for,
/// reads it back, and saves only after a yes. The amount is Siri's own
/// currency amount, so "four fifty" and "four dollars and fifty cents" both
/// arrive as 4.50; the words give the category, date, and any split.
struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log an Expense"
    static let description = IntentDescription("Records an amount and what it was for, like $4.50 for coffee.")
    // Spending is personal: the iPhone must be unlocked.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    // A currency amount starts at 0 rather than empty, so perform() asks
    // for it. The listed currencies keep Shortcuts from offering an odd default.
    @Parameter(title: "Amount",
               currencyCodes: ["USD", "CNY", "EUR", "GBP", "CAD", "AUD", "JPY", "HKD", "SGD", "TWD", "KRW"],
               requestValueDialog: IntentDialog("How much was it?"))
    var amount: IntentCurrencyAmount?

    @Parameter(title: "What it was for", requestValueDialog: IntentDialog("What was it for? For example, coffee."))
    var item: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) for \(\.$item)")
    }

    @Dependency private var container: ModelContainer

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The system fills an unanswered currency amount with 0, so zero
        // means "not asked yet" and Siri asks for it here.
        let spoken: IntentCurrencyAmount
        if let amount, amount.amount > 0 {
            spoken = amount
        } else {
            spoken = try await $amount.requestValue(IntentDialog(stringLiteral: L10n.isZh ? "花了多少？" : "How much was it?"))
        }
        ExpenseIntentStore.recordForDebugging("amount=\(spoken.amount) \(spoken.currencyCode) item=\(item)")
        guard let total = ExpenseIntentStore.money(from: spoken.amount) else {
            throw $amount.needsValueError(IntentDialog(stringLiteral: L10n.isZh
                ? "金额需要大于 0。花了多少？"
                : "The amount needs to be more than zero. How much was it?"))
        }
        var entry = await QuickEntryReader().read(item)
        // Siri's amount is the total; the words can still say "split 3".
        entry.total = total
        guard let plan = ExpenseIntentStore.plan(for: entry) else {
            throw $amount.needsValueError(IntentDialog("How much was it?"))
        }
        let question = IntentDialog(stringLiteral: ExpenseIntentStore.confirmation(for: plan))
        if #available(iOS 18.0, *) {
            try await requestConfirmation(actionName: .add, dialog: question)
        } else if try await !$item.requestConfirmation(for: item, dialog: question) {
            // iOS 17 asks the same yes-or-no question about the words.
            return .result(dialog: IntentDialog(stringLiteral: L10n.isZh ? "好的，没有记下。" : "Okay, nothing was saved."))
        }
        try ExpenseIntentStore.save(plan, in: container)
        ExpenseIntentStore.recordForDebugging("saved \(plan.amount.minorUnits) cents, \(plan.category), split \(plan.splitCount ?? 1)")
        return .result(dialog: IntentDialog(stringLiteral: ExpenseIntentStore.savedMessage(for: plan)))
    }
}

/// "Scan a receipt with DailySpend." Opens the scanner; the person reviews
/// what was read before anything is saved.
struct ScanReceiptIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan a Receipt"
    static let description = IntentDescription("Opens DailySpend's receipt scanner.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pendingAction = .scanReceipt
        return .result()
    }
}

/// "How much have I spent this month in DailySpend?"
struct MonthSpendingIntent: AppIntent {
    static let title: LocalizedStringResource = "Spending This Month"
    static let description = IntentDescription("Tells you this month's spending and what's left of your budget.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Dependency private var container: ModelContainer

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = try ExpenseIntentStore.monthSummary(in: container)
        return .result(dialog: IntentDialog(stringLiteral: ExpenseIntentStore.spokenSummary(summary)))
    }
}

// MARK: - Siri phrases

struct DailySpendShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Add an expense in \(.applicationName)",
                "Record spending in \(.applicationName)"
            ],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: ScanReceiptIntent(),
            phrases: [
                "Scan a receipt with \(.applicationName)",
                "Scan a receipt in \(.applicationName)"
            ],
            shortTitle: "Scan Receipt",
            systemImageName: "doc.text.viewfinder"
        )
        AppShortcut(
            intent: MonthSpendingIntent(),
            phrases: [
                "How much have I spent this month in \(.applicationName)",
                "What did I spend this month in \(.applicationName)",
                "\(.applicationName) spending this month"
            ],
            shortTitle: "Spent This Month",
            systemImageName: "chart.pie"
        )
    }
}
