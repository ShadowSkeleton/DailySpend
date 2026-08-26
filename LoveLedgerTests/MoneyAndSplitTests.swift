import Foundation
import SwiftData
import XCTest
@testable import LoveLedger

@MainActor
final class MoneyAndSplitTests: XCTestCase {
    func testReceiptParserPrefersPayableTotalOverSubtotal() {
        let amount = ReceiptAmountParser.bestAmount(from: [
            .init(text: "Subtotal 89.00", boundingBox: CGRect(x: 0.65, y: 0.42, width: 0.2, height: 0.03)),
            .init(text: "Sales Tax (8.25%) 7.34", boundingBox: CGRect(x: 0.65, y: 0.37, width: 0.2, height: 0.03)),
            .init(text: "Total 96.34", boundingBox: CGRect(x: 0.65, y: 0.30, width: 0.2, height: 0.03))
        ])

        XCTAssertEqual(amount, 96.34)
    }

    func testReceiptParserPrefersGrandTotalAndReadsCommaSeparatedCurrency() {
        let amount = ReceiptAmountParser.bestAmount(from: [
            .init(text: "Total 1,199.00", boundingBox: CGRect(x: 0.65, y: 0.38, width: 0.2, height: 0.03)),
            .init(text: "Grand Total $1,224.50", boundingBox: CGRect(x: 0.65, y: 0.28, width: 0.2, height: 0.03))
        ])

        XCTAssertEqual(amount, 1_224.50)
    }

    func testEvenSplitDistributesEveryCent() {
        let shares = Money.splitEvenly(Money(10), among: 3)

        XCTAssertEqual(shares.map(\.minorUnits), [334, 333, 333])
        XCTAssertEqual(shares.reduce(.zero, +), Money(10))
    }

    func testWeightedAllocationReconcilesToOriginalTotal() {
        let allocation = Money.allocate(Money(1), by: [1, 1, 1])

        XCTAssertEqual(allocation.map(\.minorUnits), [34, 33, 33])
        XCTAssertEqual(allocation.reduce(.zero, +), Money(1))
    }

    func testVeryLargeInputIsRejectedAndArithmeticCannotOverflow() {
        XCTAssertFalse(ExpenseInputValidator.isValidAmount(1_000_000_000_001))

        let saturated = Money(minorUnits: .max) + Money(minorUnits: 1)
        XCTAssertEqual(saturated.minorUnits, .max)
    }

    func testExpenseInputRejectsFractionsOfACent() {
        XCTAssertTrue(ExpenseInputValidator.isValidAmount(12.34))
        XCTAssertFalse(ExpenseInputValidator.isValidAmount(12.345))
    }

    func testMoneyBackfillPreservesLegacyRawValueAndUsesExactCents() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let legacyExpense = Expense(amount: 12.34, category: "Food", note: "Legacy", date: Date())
        let legacyBudget = CategoryBudget(category: "Food", amount: 100)

        // Simulate records stored by the pre-cents schema. The raw value is
        // intentionally left untouched during the additive migration.
        legacyExpense.amount = 12.346
        legacyExpense.amountMinorUnits = nil
        legacyBudget.amount = 99.996
        legacyBudget.amountMinorUnits = nil
        context.insert(legacyExpense)
        context.insert(legacyBudget)
        try context.save()

        let result = try MoneyStoreMigration.backfillMissingMinorUnits(in: context)
        XCTAssertEqual(result, .init(migratedExpenses: 1, migratedCategoryBudgets: 1))
        XCTAssertEqual(legacyExpense.amount, 12.346)
        XCTAssertEqual(legacyExpense.amountMinorUnits, 1_235)
        XCTAssertEqual(legacyExpense.normalizedAmount, 12.35)
        XCTAssertEqual(legacyBudget.amount, 99.996)
        XCTAssertEqual(legacyBudget.amountMinorUnits, 10_000)
        XCTAssertEqual(legacyBudget.normalizedAmount, 100)

        XCTAssertEqual(
            try MoneyStoreMigration.backfillMissingMinorUnits(in: context),
            .unchanged
        )
    }

    func testBackupRejectsMismatchedRawAndMinorUnitAmounts() throws {
        let backup = AppBackup(
            expenses: [
                ExpenseBackupItem(
                    amount: 12.34,
                    amountMinorUnits: 1_235,
                    category: "Food",
                    note: "Mismatch",
                    date: Date()
                )
            ],
            categoryBudgets: [],
            settings: nil
        )

        XCTAssertThrowsError(
            try BackupRestorer.apply(
                ImportedBackup(backup: backup, isLegacy: false),
                mode: .merge,
                in: ModelContext(try makeInMemoryContainer())
            )
        )
    }

    func testEncryptedBackupRoundTripsAndRejectsWrongPassphrase() throws {
        let original = Data("private DailySpend backup".utf8)
        let encrypted = try SecureBackupCodec.encrypt(
            original,
            passphrase: "correct horse battery staple"
        )

        XCTAssertTrue(SecureBackupCodec.isEncryptedBackup(encrypted))
        XCTAssertNotEqual(encrypted, original)
        XCTAssertEqual(
            try SecureBackupCodec.decrypt(encrypted, passphrase: "correct horse battery staple"),
            original
        )
        XCTAssertThrowsError(
            try SecureBackupCodec.decrypt(encrypted, passphrase: "incorrect passphrase")
        )
    }

    func testEncryptedBackupRequiresAStrongPassphrase() {
        XCTAssertThrowsError(
            try SecureBackupCodec.encrypt(Data("backup".utf8), passphrase: "too-short")
        )
    }

    func testItemizedSettlementReconcilesSharedItemAndTax() {
        let session = SplitSession()
        session.addPerson(name: "Avery")
        session.addPerson(name: "Jordan")
        session.addSharedItem(name: "Dinner", price: 10)
        session.taxAmount = 1
        session.tipSelection = 0

        let recordedTotal = session.people
            .map { Money(session.finalTotal(for: $0)) }
            .reduce(.zero, +)

        XCTAssertTrue(session.isReadyToSettle)
        XCTAssertEqual(recordedTotal, Money(session.grandTotal))
        XCTAssertEqual(recordedTotal, Money(11))
    }

    func testUnassignedSharedItemCannotBeRecorded() {
        let session = SplitSession()
        session.addSharedItem(name: "Unassigned", price: 10)
        session.sharedItems[0].involvedPersonIDs = []

        XCTAssertFalse(session.isReadyToSettle)
        XCTAssertEqual(Money(session.grandTotal), Money(11.5))
    }

    func testVersionedBackupRetainsStableRecurrenceFields() throws {
        let id = UUID()
        let lastProcessed = Date(timeIntervalSince1970: 1_700_000_000)
        let backup = AppBackup(
            expenses: [
                ExpenseBackupItem(
                    id: id,
                    amount: 12.34,
                    category: "Food",
                    note: "Subscription",
                    date: lastProcessed,
                    frequency: .monthly,
                    lastProcessedDate: lastProcessed,
                    isRecurringChild: true
                )
            ],
            categoryBudgets: [CategoryBudgetBackupItem(category: "Food", amount: 200)],
            settings: BackupSettings(
                isBudgetEnabled: true,
                budgetAmount: 500,
                alertThreshold: 100,
                dailyNotify: true,
                notifyTime: 1_700_000_000
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(AppBackup.self, from: encoder.encode(backup))
        let restoredExpense = try XCTUnwrap(restored.expenses.first)

        XCTAssertEqual(restored.formatVersion, AppBackup.currentFormatVersion)
        XCTAssertEqual(restoredExpense.id, id)
        XCTAssertEqual(restoredExpense.frequency, .monthly)
        XCTAssertEqual(restoredExpense.lastProcessedDate, lastProcessed)
        XCTAssertEqual(restoredExpense.isRecurringChild, true)
        XCTAssertEqual(restored.categoryBudgets, [CategoryBudgetBackupItem(category: "Food", amount: 200)])
    }

    func testLegacyBackupMigrationPreservesFutureRecurrenceWithoutDuplicates() {
        let originalDate = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 12:00 UTC
        let referenceDate = Date(timeIntervalSince1970: 1_726_080_000) // 2024-09-12 08:00 UTC
        let legacy = [
            ExpenseBackupItem(
                amount: 25,
                category: "Utilities",
                note: "Internet",
                date: originalDate,
                frequency: .monthly
            ),
            ExpenseBackupItem(
                amount: 25,
                category: "Utilities",
                note: "Internet (Auto)",
                date: originalDate,
                frequency: .monthly
            )
        ]

        let migrated = BackupMigration.upgradeLegacyExpenses(legacy, referenceDate: referenceDate)

        XCTAssertEqual(migrated.expenses[0].frequency, .monthly)
        XCTAssertNotNil(migrated.expenses[0].lastProcessedDate)
        XCTAssertEqual(migrated.expenses[0].isRecurringChild, false)
        XCTAssertEqual(migrated.expenses[1].isRecurringChild, true)
        XCTAssertNil(migrated.expenses[1].lastProcessedDate)
    }

    func testExpenseModelPersistsStableIDAndRecurrenceState() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Expense.self,
            CategoryBudget.self,
            configurations: configuration
        )
        let writer = ModelContext(container)
        let id = UUID()
        let processed = Date(timeIntervalSince1970: 1_700_000_000)
        writer.insert(
            Expense(
                id: id,
                amount: 42.25,
                category: "Food",
                note: "Dinner",
                date: processed,
                frequency: .weekly,
                lastProcessedDate: processed,
                isRecurringChild: false
            )
        )
        try writer.save()

        let reader = ModelContext(container)
        let restored = try XCTUnwrap(reader.fetch(FetchDescriptor<Expense>()).first)

        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.amount, 42.25)
        XCTAssertEqual(restored.safeFrequency, .weekly)
        XCTAssertEqual(restored.lastProcessedDate, processed)
        XCTAssertFalse(restored.isRecurringChild)
    }

    func testSafeMergeAddsMissingRecordsWithoutOverwritingExistingData() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let existingID = UUID()
        let missingID = UUID()

        context.insert(Expense(id: existingID, amount: 90, category: "Food", note: "Newer local edit", date: Date()))
        context.insert(CategoryBudget(category: "Food", amount: 300))
        try context.save()

        let backup = AppBackup(
            expenses: [
                ExpenseBackupItem(id: existingID, amount: 10, category: "Food", note: "Older backup", date: Date()),
                ExpenseBackupItem(id: missingID, amount: 25, category: "Transport", note: "Taxi", date: Date())
            ],
            categoryBudgets: [
                CategoryBudgetBackupItem(category: "Food", amount: 100),
                CategoryBudgetBackupItem(category: "Transport", amount: 80)
            ],
            settings: BackupSettings(isBudgetEnabled: true, budgetAmount: 500, alertThreshold: 100, dailyNotify: true, notifyTime: 1_700_000_000)
        )

        let returnedSettings = try BackupRestorer.apply(
            ImportedBackup(backup: backup, isLegacy: false),
            mode: .merge,
            in: context
        )

        XCTAssertNil(returnedSettings)
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(expenses.count, 2)
        XCTAssertEqual(expenses.first(where: { $0.id == existingID })?.amount, 90)
        XCTAssertEqual(expenses.first(where: { $0.id == missingID })?.note, "Taxi")

        let budgets = try context.fetch(FetchDescriptor<CategoryBudget>())
        XCTAssertEqual(budgets.first(where: { $0.category == "Food" })?.amount, 300)
        XCTAssertEqual(budgets.first(where: { $0.category == "Transport" })?.amount, 80)
    }

    func testReplaceRestoresExactContentAndReturnsSettings() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(Expense(amount: 15, category: "Food", note: "Remove me", date: Date()))
        context.insert(CategoryBudget(category: "Food", amount: 200))
        try context.save()

        let restoredID = UUID()
        let settings = BackupSettings(isBudgetEnabled: true, budgetAmount: 450, alertThreshold: 75, dailyNotify: false, notifyTime: 0)
        let backup = AppBackup(
            expenses: [ExpenseBackupItem(id: restoredID, amount: 42.50, category: "Utilities", note: "Internet", date: Date(), frequency: .monthly)],
            categoryBudgets: [CategoryBudgetBackupItem(category: "Utilities", amount: 120)],
            settings: settings
        )

        let returnedSettings = try BackupRestorer.apply(
            ImportedBackup(backup: backup, isLegacy: false),
            mode: .replace,
            in: context
        )

        XCTAssertEqual(returnedSettings, settings)
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(expenses.count, 1)
        XCTAssertEqual(expenses.first?.id, restoredID)
        XCTAssertEqual(expenses.first?.safeFrequency, .monthly)

        let budgets = try context.fetch(FetchDescriptor<CategoryBudget>())
        XCTAssertEqual(budgets.count, 1)
        XCTAssertEqual(budgets.first?.category, "Utilities")
    }

    func testInvalidBackupIsRejectedBeforeChangingStoredData() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let existingID = UUID()
        context.insert(Expense(id: existingID, amount: 19, category: "Food", note: "Keep me", date: Date()))
        try context.save()

        let invalidBackup = AppBackup(
            expenses: [ExpenseBackupItem(id: UUID(), amount: 1_000_000_000_001, category: "Food", note: "Too large", date: Date())],
            categoryBudgets: [],
            settings: nil
        )

        XCTAssertThrowsError(
            try BackupRestorer.apply(
                ImportedBackup(backup: invalidBackup, isLegacy: false),
                mode: .replace,
                in: context
            )
        )

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(expenses.count, 1)
        XCTAssertEqual(expenses.first?.id, existingID)
        XCTAssertEqual(expenses.first?.amount, 19)
    }

    func testProductionConfigurationUsesTheExplicitPrivateCloudKitContainer() {
        let production = LoveLedgerApp.modelConfiguration(isRunningUITests: false)
        let testing = LoveLedgerApp.modelConfiguration(isRunningUITests: true)

        XCTAssertEqual(production.cloudKitContainerIdentifier, LoveLedgerApp.cloudKitContainerIdentifier)
        XCTAssertNil(testing.cloudKitContainerIdentifier)
        XCTAssertTrue(testing.isStoredInMemoryOnly)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Expense.self,
            CategoryBudget.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
