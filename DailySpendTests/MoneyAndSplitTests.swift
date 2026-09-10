import Foundation
import SwiftData
import XCTest
import SwiftUI
@testable import DailySpend

@MainActor
final class MoneyAndSplitTests: XCTestCase {
    func testWalletBrandAssetLoadsAndAboutRenders() throws {
        let logo = try XCTUnwrap(UIImage(named: "DailySpendLogo"))
        XCTAssertEqual(logo.size.width, logo.size.height)
        XCTAssertGreaterThanOrEqual(logo.size.width * logo.scale, 1024)
        let renderer = ImageRenderer(content: Image("DailySpendLogo")
            .resizable().scaledToFit().frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous)))
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertNotNil(image.pngData())
        let attachment = XCTAttachment(image: image)
        attachment.name = "Wallet logo at home screen size"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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

    func testRecurringDisplayCleansOnlyGeneratedLegacyNotes() {
        let child = Expense(amount: 100, category: "Housing", note: "Rent (Auto)", frequency: .monthly, isRecurringChild: true)
        XCTAssertEqual(child.displayNote, "Rent")
        XCTAssertEqual(child.note, "Rent (Auto)", "Displaying an old note must not mutate stored history")
        child.note = "(Auto)"
        XCTAssertEqual(child.displayNote, "")
        child.note = "Rent"
        XCTAssertEqual(child.displayNote, "Rent")
        child.isRecurringChild = false
        child.note = "Car (Auto)"
        XCTAssertEqual(child.displayNote, "Car (Auto)", "Never strip a user's ordinary note")
    }

    func testSplitNoteDoesNotRepeatEqualShare() {
        let note = SplitNote.quick(total: Money(115), share: Money(57.5), people: 2)
        let amount = Money(57.5).amount.formatted(.currency(code: L10n.currencyCode))
        XCTAssertEqual(note.components(separatedBy: amount).count - 1, 1)
        XCTAssertTrue(note.contains("\n"))
        XCTAssertTrue(note.contains(Money(115).amount.formatted(.currency(code: L10n.currencyCode))))
    }

    func testLegacySplitNoteDisplayRemovesOnlyExactRedundancy() {
        let old = "Split: Total $115.00; my share $57.50. Each pays $57.50"
        let expense = Expense(amount: 57.5, category: "Food", note: old)
        XCTAssertEqual(expense.displayNote, "Split: Total $115.00\nMy share $57.50")
        XCTAssertEqual(expense.note, old)
        for note in ["Dinner. Each pays $57.50", old + " — paid cash", "Split: Total $10.00; my share $3.34. Each pays $3.33"] {
            XCTAssertEqual(SplitNote.readableLegacyNote(note), note)
        }
        XCTAssertEqual(SplitNote.readableLegacyNote("AA分账: 总额US$115.00；我的份额 US$57.50。每人支付 US$57.50"),
                       "AA分账: 总额US$115.00\n我的份额 US$57.50")
    }

    func testLongRecurringTransactionRendersAtAccessibilitySize() throws {
        let expense = Expense(amount: 57.5, category: "Housing",
                              note: "Split: Total $115.00; my share $57.50. Each pays $57.50 (Auto)",
                              frequency: .monthly, isRecurringChild: true)
        let renderer = ImageRenderer(content: ExpenseRowCard(expense: expense)
            .frame(width: 375)
            .background(Color(uiColor: .systemBackground))
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(width: 375, height: nil)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertGreaterThan(image.size.height, 200)
        XCTAssertFalse(expense.displayNote.contains("(Auto)"))
        XCTAssertFalse(expense.displayNote.contains("Each pays"))
        let attachment = XCTAttachment(image: image)
        attachment.name = "Recurring note at largest text size"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSharedItemBreakdownUsesExactAllocatedCentsAndOnlyAssignedItems() throws {
        let session = SplitSession()
        session.addPerson(name: "Friend")
        session.addPerson(name: "Guest")
        session.tipSelection = 0
        session.addSharedItem(name: "Shared starter", price: 10)
        session.addSharedItem(name: "Tea", price: 0.01)
        session.sharedItems[1].involvedPersonIDs = [session.people[0].id, session.people[1].id]
        for person in session.people {
            let shares = session.sharedItemShares(for: person.id)
            XCTAssertEqual(shares.reduce(Money.zero) { $0 + $1.share }, Money(session.sharedPortion(for: person.id)))
        }
        XCTAssertEqual(session.sharedItemShares(for: session.people[0].id).map { $0.share.minorUnits }, [334, 1])
        XCTAssertEqual(session.sharedItemShares(for: session.people[1].id).map { $0.share.minorUnits }, [333, 0])
        XCTAssertEqual(session.sharedItemShares(for: session.people[2].id).map(\.name), ["Shared starter"])
        session.removePerson(id: session.people[0].id)
        XCTAssertEqual(session.people.reduce(Money.zero) { $0 + Money(session.sharedPortion(for: $1.id)) }, Money(10.01))
        XCTAssertEqual(session.sharedItemShares(for: UUID()).count, 0)
    }

    func testDetailedReceiptIncludesItemSharesAndOneCentTaxWithoutDoubleCounting() throws {
        let session = SplitSession()
        session.tipSelection = 0
        session.addPerson(name: "Friend")
        session.addPersonalItem(to: session.people[0].id, name: "Steak", price: 45)
        session.addPersonalItem(to: session.people[1].id, name: "Fish", price: 25)
        session.addSharedItem(name: "A shared starter with a deliberately long name", price: 6)
        session.addSharedItem(name: "Tea 茶", price: 4)
        session.taxAmount = 0.01
        let receipt = session.makeReceiptData()
        XCTAssertEqual(receipt.total, 80.01)
        let details = receipt.items.filter { $0.style == .detail }
        XCTAssertEqual(details.count, 4)
        XCTAssertEqual(details.map(\.value), [.currency(3), .currency(2), .currency(3), .currency(2)])
        XCTAssertTrue(details.allSatisfy { $0.subtitle == nil && $0.participants == session.people.map(\.name) })
        XCTAssertEqual(receipt.items.filter { $0.style == .sharedSubtotal }.map(\.value), [.currency(5), .currency(5)])
        XCTAssertTrue(receipt.items.contains { $0.style == .standard && $0.value == .currency(0.01) })
        let totals = receipt.items.filter { $0.style == .personTotal }.reduce(Money.zero) { total, item in
            guard case .currency(let amount) = item.value else { return total }
            return total + Money(amount)
        }
        XCTAssertEqual(totals, Money(receipt.total))

        let image = try XCTUnwrap(ReceiptImageExporter.image(data: receipt, scale: 2))
        XCTAssertNotNil(image.pngData())
        XCTAssertGreaterThan(image.size.height, 500)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Detailed shared receipt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSharedReceiptNamesFollowAssignmentsAndRenamesWithoutChangingShares() throws {
        let session = SplitSession()
        session.people[0].name = "Alex"
        session.addPerson(name: "Alex")
        session.addPerson(name: "Not involved")
        session.tipSelection = 0
        session.addSharedItem(name: "Tea", price: 0.01)
        session.sharedItems[0].involvedPersonIDs = [session.people[1].id, UUID(), session.people[0].id, session.people[0].id]
        var details = session.makeReceiptData().items.filter { $0.style == .detail }
        XCTAssertEqual(details.map(\.participants), [["Alex", "Alex"], ["Alex", "Alex"]])
        XCTAssertEqual(details.map(\.value), [.currency(0.01), .currency(0)])
        session.people[1].name = "  Jamie  "
        XCTAssertEqual(session.makeReceiptData().items.first { $0.style == .detail }?.participants, ["Alex", "Jamie"])
        session.removePerson(id: session.people[0].id)
        session.people[0].name = " \n "
        details = session.makeReceiptData().items.filter { $0.style == .detail }
        XCTAssertEqual(details.count, 1)
        XCTAssertEqual(details[0].participants, [L10n.isZh ? "未命名" : "Guest"])
        XCTAssertEqual(details[0].value, .currency(0.01))
    }

    func testApprovedSharedReceiptLayoutRendersShortLongAndMultipleNames() throws {
        let session = SplitSession()
        session.people[0].name = "Alex"
        session.addPerson(name: "Jamie")
        session.addPerson(name: "Alexandra Catherine Montgomery-Wellington")
        session.tipSelection = 0
        session.addSharedItem(name: "Starter", price: 6)
        session.sharedItems[0].involvedPersonIDs = [session.people[0].id, session.people[1].id]
        session.addSharedItem(name: "Jasmine tea 茉莉花茶 for the table", price: 12)
        let receipt = session.makeReceiptData()
        XCTAssertEqual(receipt.total, 18)
        XCTAssertEqual(receipt.items.filter { $0.style == .sharedSubtotal }.map(\.value), [.currency(7), .currency(7), .currency(4)])
        XCTAssertEqual(Array(receipt.items.filter { $0.style == .detail }.prefix(2)).map(\.value), [.currency(3), .currency(4)])
        XCTAssertTrue(receipt.items.allSatisfy { $0.subtitle == nil })
        let image = try XCTUnwrap(ReceiptImageExporter.image(data: receipt, scale: 2))
        XCTAssertNotNil(image.pngData())
        XCTAssertEqual(image.size.width, 375)
        XCTAssertGreaterThan(image.size.height, 800)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Approved shared receipt - short long and multiple names"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Two long names must also fall back to the stacked layout, not truncate.
        session.people[0].name = "Christopher Alexander Worthington-Smythe"
        session.people[1].name = "王小明 Wang Xiaoming"
        let largeImage = try XCTUnwrap(ReceiptImageExporter.image(data: session.makeReceiptData(), scale: 2,
                                                                dynamicTypeSize: .accessibility3))
        XCTAssertNotNil(largeImage.pngData())
        XCTAssertGreaterThan(largeImage.size.height, image.size.height)
        let largeAttachment = XCTAttachment(image: largeImage)
        largeAttachment.name = "Shared receipt - long names and accessibility text"
        largeAttachment.lifetime = .keepAlways
        add(largeAttachment)
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

    func testBackupRejectsInvalidMoneySettingsBeforeChangingStoredData() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let existingID = UUID()
        context.insert(Expense(id: existingID, amount: 19, category: "Food", note: "Keep me", date: Date()))
        try context.save()

        let invalidSettings = BackupSettings(
            isBudgetEnabled: true,
            budgetAmount: 12.345,
            alertThreshold: 10,
            dailyNotify: false,
            notifyTime: 0
        )
        let backup = AppBackup(expenses: [], categoryBudgets: [], settings: invalidSettings)

        XCTAssertThrowsError(
            try BackupRestorer.apply(
                ImportedBackup(backup: backup, isLegacy: false),
                mode: .replace,
                in: context
            )
        )

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(expenses.map(\.id), [existingID])
    }

    func testProductionConfigurationUsesTheExplicitPrivateCloudKitContainer() {
        let production = DailySpendApp.modelConfiguration(isRunningUITests: false)
        let testing = DailySpendApp.modelConfiguration(isRunningUITests: true)

        XCTAssertEqual(production.cloudKitContainerIdentifier, DailySpendApp.cloudKitContainerIdentifier)
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
