import Foundation
import SwiftData

/// Backfills cents for records created before DailySpend stored an exact minor
/// unit representation. This is deliberately additive: it never deletes or
/// rewrites a legacy `Double`, so an interrupted migration continues to read
/// every existing record through the fallback in `Expense.money`.
enum MoneyStoreMigration {
    struct Result: Equatable {
        let migratedExpenses: Int
        let migratedCategoryBudgets: Int

        static let unchanged = Result(migratedExpenses: 0, migratedCategoryBudgets: 0)
    }

    static func backfillMissingMinorUnits(in modelContext: ModelContext) throws -> Result {
        let expenses = try modelContext.fetch(FetchDescriptor<Expense>())
        let categoryBudgets = try modelContext.fetch(FetchDescriptor<CategoryBudget>())

        let expensesToMigrate = expenses.filter { $0.amountMinorUnits == nil }
        let budgetsToMigrate = categoryBudgets.filter { $0.amountMinorUnits == nil }

        guard !expensesToMigrate.isEmpty || !budgetsToMigrate.isEmpty else {
            return .unchanged
        }

        // Do not touch `amount`. It remains a recovery-safe legacy source
        // while the new minor-unit value supplies precise calculations.
        expensesToMigrate.forEach { $0.backfillMinorUnitsIfNeeded() }
        budgetsToMigrate.forEach { $0.backfillMinorUnitsIfNeeded() }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        return Result(
            migratedExpenses: expensesToMigrate.count,
            migratedCategoryBudgets: budgetsToMigrate.count
        )
    }
}
