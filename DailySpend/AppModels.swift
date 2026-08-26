import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

// MARK: - CSV & JSON
struct CSVDocument: FileDocument, Transferable {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String; init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { guard let data = configuration.file.regularFileContents, let string = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }; text = string }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { let data = text.data(using: .utf8)!; return FileWrapper(regularFileWithContents: data) }
    static var transferRepresentation: some TransferRepresentation { DataRepresentation(contentType: .commaSeparatedText) { document in document.text.data(using: .utf8)! } importing: { data in CSVDocument(text: String(data: data, encoding: .utf8)!) } }
}

struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { return FileWrapper(regularFileWithContents: data) }
}

// MARK: - Versioned Backup Format

/// Optional fields keep previously exported JSON readable after an app update.
struct ExpenseBackupItem: Codable {
    let id: UUID?
    let amount: Double
    let amountMinorUnits: Int64?
    let category: String
    let note: String
    let date: Date
    let frequency: RecurrenceFrequency?
    let lastProcessedDate: Date?
    let isRecurringChild: Bool?

    init(id: UUID? = nil, amount: Double, amountMinorUnits: Int64? = nil, category: String, note: String, date: Date, frequency: RecurrenceFrequency? = nil, lastProcessedDate: Date? = nil, isRecurringChild: Bool? = nil) {
        self.id = id
        self.amount = amount
        self.amountMinorUnits = amountMinorUnits
        self.category = category
        self.note = note
        self.date = date
        self.frequency = frequency
        self.lastProcessedDate = lastProcessedDate
        self.isRecurringChild = isRecurringChild
    }

    var money: Money {
        amountMinorUnits.map(Money.init(minorUnits:)) ?? Money(amount)
    }

    var normalizedAmount: Double { money.amount }
}

struct CategoryBudgetBackupItem: Codable, Equatable {
    let category: String
    let amount: Double
    let amountMinorUnits: Int64?

    init(category: String, amount: Double, amountMinorUnits: Int64? = nil) {
        self.category = category
        self.amount = amount
        self.amountMinorUnits = amountMinorUnits
    }

    var money: Money {
        amountMinorUnits.map(Money.init(minorUnits:)) ?? Money(amount)
    }

    var normalizedAmount: Double { money.amount }
}

struct BackupSettings: Codable, Equatable {
    let isBudgetEnabled: Bool
    let budgetAmount: Double
    let alertThreshold: Double
    let dailyNotify: Bool
    let notifyTime: Double
}

struct AppBackup: Codable {
    static let currentFormatVersion = 3

    let formatVersion: Int
    let createdAt: Date
    let expenses: [ExpenseBackupItem]
    let categoryBudgets: [CategoryBudgetBackupItem]
    let settings: BackupSettings?

    init(expenses: [ExpenseBackupItem], categoryBudgets: [CategoryBudgetBackupItem], settings: BackupSettings?) {
        self.formatVersion = Self.currentFormatVersion
        self.createdAt = Date()
        self.expenses = expenses
        self.categoryBudgets = categoryBudgets
        self.settings = settings
    }
}

/// A legacy export has no stable identifiers or recurrence state. Restoring it
/// safely must never guess which records are recurrence templates.
struct ImportedBackup {
    let backup: AppBackup
    let isLegacy: Bool
}

/// Merge intentionally only adds records that do not already exist. This makes
/// importing a backup safe when the current device has newer edits. Replacing
/// is the explicit recovery path after the user has saved a safety backup.
enum BackupRestoreMode {
    case merge
    case replace
}

enum BackupRestorer {
    /// Applies a validated backup in one save. Any save error is left for the
    /// caller to roll back, so a failed restore never leaves a partial result.
    /// Returns settings only for an explicit replacement; merging records must
    /// not silently overwrite someone’s current notification or budget choices.
    static func apply(
        _ importedBackup: ImportedBackup,
        mode: BackupRestoreMode,
        in modelContext: ModelContext
    ) throws -> BackupSettings? {
        try validate(importedBackup.backup)

        let incomingExpenses = importedBackup.backup.expenses
        let existingExpenses = try modelContext.fetch(FetchDescriptor<Expense>())
        let existingByID = Dictionary(grouping: existingExpenses, by: \.id)
        var incomingIDs = Set<UUID>()

        for item in incomingExpenses {
            let id = importedBackup.isLegacy ? UUID() : (item.id ?? UUID())
            guard incomingIDs.insert(id).inserted else {
                throw CocoaError(.fileReadCorruptFile)
            }

            if let existing = existingByID[id]?.first {
                // A merge never changes a matching local record. The local copy
                // might be newer than the backup, and we have no edit timestamp
                // that could resolve that safely.
                guard mode == .replace else { continue }
                update(existing, from: item)
            } else {
                let expense = Expense(
                    id: id,
                    amount: item.normalizedAmount,
                    amountMinorUnits: item.money.minorUnits,
                    category: item.category,
                    note: item.note,
                    date: item.date
                )
                update(expense, from: item)
                modelContext.insert(expense)
            }
        }

        if mode == .replace {
            for expense in existingExpenses where !incomingIDs.contains(expense.id) {
                modelContext.delete(expense)
            }
        }

        let incomingBudgets = importedBackup.backup.categoryBudgets
        let existingBudgets = try modelContext.fetch(FetchDescriptor<CategoryBudget>())
        let budgetsByCategory = Dictionary(grouping: existingBudgets, by: \.category)
        let incomingCategories = Set(incomingBudgets.map(\.category))

        for item in incomingBudgets {
            if let existing = budgetsByCategory[item.category]?.first {
                if mode == .replace {
                    existing.setMoney(item.money)
                }
            } else {
                modelContext.insert(
                    CategoryBudget(
                        category: item.category,
                        amount: item.normalizedAmount,
                        amountMinorUnits: item.money.minorUnits
                    )
                )
            }
        }

        if mode == .replace {
            for budget in existingBudgets where !incomingCategories.contains(budget.category) {
                modelContext.delete(budget)
            }
        }

        try modelContext.save()
        return mode == .replace ? importedBackup.backup.settings : nil
    }

    private static func update(_ expense: Expense, from item: ExpenseBackupItem) {
        expense.setMoney(item.money)
        expense.category = item.category
        expense.note = item.note
        expense.date = item.date
        expense.frequency = item.frequency ?? RecurrenceFrequency.none
        expense.lastProcessedDate = item.lastProcessedDate
        expense.isRecurringChild = item.isRecurringChild ?? false
    }

    private static func validate(_ backup: AppBackup) throws {
        guard backup.formatVersion > 0, backup.formatVersion <= AppBackup.currentFormatVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Zero-value records from earlier versions remain restorable. New input
        // blocks zero, but rejecting older backup data would break migration.
        for expense in backup.expenses {
            guard isValidBackupExpenseAmount(expense) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }

        var budgetCategories = Set<String>()
        for budget in backup.categoryBudgets {
            let category = budget.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !category.isEmpty,
                  budget.amount.isFinite,
                  budget.normalizedAmount > 0,
                  budget.money.minorUnits <= ExpenseInputValidator.maximumInputMinorUnits,
                  isConsistent(budget.amount, minorUnits: budget.amountMinorUnits),
                  budgetCategories.insert(budget.category).inserted else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }

        if let settings = backup.settings {
            guard settings.budgetAmount.isFinite,
                  settings.budgetAmount >= 0,
                  settings.alertThreshold.isFinite,
                  settings.alertThreshold >= 0,
                  settings.notifyTime.isFinite,
                  settings.notifyTime >= 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }

    private static func isValidBackupExpenseAmount(_ item: ExpenseBackupItem) -> Bool {
        item.amount.isFinite &&
        item.normalizedAmount >= 0 &&
        item.money.minorUnits <= ExpenseInputValidator.maximumInputMinorUnits &&
        isConsistent(item.amount, minorUnits: item.amountMinorUnits)
    }

    private static func isConsistent(_ amount: Double, minorUnits: Int64?) -> Bool {
        guard let minorUnits else { return true }
        return Money(amount).minorUnits == minorUnits
    }
}

enum BackupMigration {
    /// V1 did not save stable IDs, recurrence-processing state, or child flags.
    /// Keep its recurring templates alive from their next scheduled cycle while
    /// preserving previously generated `(Auto)` entries as children.
    static func upgradeLegacyExpenses(_ items: [ExpenseBackupItem], referenceDate: Date = Date()) -> AppBackup {
        let upgraded = items.map { item in
            let frequency = item.frequency ?? .none
            let isGeneratedChild = item.note == "(Auto)" || item.note.hasSuffix(" (Auto)")
            let lastProcessedDate = isGeneratedChild
                ? nil
                : RecurrenceEngine.mostRecentScheduledDate(
                    initialDate: item.date,
                    frequency: frequency,
                    noLaterThan: referenceDate
                )

            return ExpenseBackupItem(
                id: nil,
                amount: item.amount,
                amountMinorUnits: item.amountMinorUnits,
                category: item.category,
                note: item.note,
                date: item.date,
                frequency: frequency,
                lastProcessedDate: lastProcessedDate,
                isRecurringChild: isGeneratedChild
            )
        }
        return AppBackup(expenses: upgraded, categoryBudgets: [], settings: nil)
    }
}

// MARK: - Enums
enum TimeRange: Int, CaseIterable, Identifiable {
    case thisMonth = 0; case lastMonth = 1; case thisYear = 2; case all = 3
    var id: Int { self.rawValue }
    var displayName: String { L10n.timeRanges[self.rawValue] }
}

// ✨ 关键修复：InsightTab 更新为 Trends 和 Activity
enum InsightTab: String, CaseIterable, Identifiable {
    case trends, activity
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .trends: return L10n.trends
        case .activity: return L10n.activity
        }
    }
}
