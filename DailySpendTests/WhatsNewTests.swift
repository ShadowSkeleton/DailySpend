import SwiftData
import XCTest
@testable import DailySpend

/// When the one-time 2.0 tour shows, and which version of it. Each test uses
/// its own preferences suite, never the app's.
@MainActor
final class WhatsNewTests: XCTestCase {
    private var defaults: UserDefaults!
    private var widgetDefaults: UserDefaults!
    private var suites: [String] = []

    override func setUp() {
        super.setUp()
        defaults = makeSuite()
        widgetDefaults = makeSuite()
    }

    override func tearDown() {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        super.tearDown()
    }

    private func makeSuite() -> UserDefaults {
        let name = "WhatsNewTests.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    func testANewInstallGetsTheWelcomeTour() {
        WhatsNew.recordEarlierUse(defaults: defaults, widgetDefaults: widgetDefaults)

        XCTAssertTrue(WhatsNew.needsTour(defaults: defaults, arguments: [], isTesting: false))
        XCTAssertEqual(WhatsNew.kind(expenseCount: 0, defaults: defaults), .welcome)
        XCTAssertEqual(WhatsNew.pages(for: .welcome).first, .welcome)
        XCTAssertFalse(WhatsNew.pages(for: .welcome).contains(.backup))
    }

    func testAnyPreference1Point0WroteMeansAnUpdate() {
        for key in WhatsNew.earlierUseKeys {
            let defaults = makeSuite()
            defaults.set(false, forKey: key)
            WhatsNew.recordEarlierUse(defaults: defaults, widgetDefaults: makeSuite())
            XCTAssertEqual(WhatsNew.kind(expenseCount: 0, defaults: defaults), .upgrade(expenseCount: 0), key)
        }
    }

    func testAWidgetSnapshotMeansAnUpdate() {
        widgetDefaults.set(Data(), forKey: WidgetSnapshot.storageKey)
        WhatsNew.recordEarlierUse(defaults: defaults, widgetDefaults: widgetDefaults)
        XCTAssertEqual(WhatsNew.kind(expenseCount: 0, defaults: defaults), .upgrade(expenseCount: 0))
    }

    func testRecordsOnThisPhoneMeanAnUpdateWithTheirCount() {
        WhatsNew.recordEarlierUse(defaults: defaults, widgetDefaults: widgetDefaults)
        let kind = WhatsNew.kind(expenseCount: 128, defaults: defaults)
        XCTAssertEqual(kind, .upgrade(expenseCount: 128))
        XCTAssertEqual(WhatsNew.pages(for: kind).first, .backup)
    }

    /// 2.0's own first launch writes preferences; a second launch before the
    /// tour is finished must still treat a new install as new.
    func testTheFirstLaunchDecidesOnce() {
        WhatsNew.recordEarlierUse(defaults: defaults, widgetDefaults: widgetDefaults)
        defaults.set(false, forKey: DailySpendApp.cloudKitStoreFallbackKey)
        WhatsNew.recordEarlierUse(defaults: defaults, widgetDefaults: widgetDefaults)
        XCTAssertEqual(WhatsNew.kind(expenseCount: 0, defaults: defaults), .welcome)
    }

    func testFinishingTheTourShowsItOnlyOnce() {
        defaults.set(false, forKey: DailySpendApp.cloudKitStoreFallbackKey)
        WhatsNew.recordEarlierUse(defaults: defaults, widgetDefaults: widgetDefaults)
        WhatsNew.markSeen(defaults: defaults)

        XCTAssertFalse(WhatsNew.needsTour(defaults: defaults, arguments: [], isTesting: false))
        XCTAssertNil(defaults.object(forKey: WhatsNew.earlierUseKey))
        // A later launch doesn't record anything again.
        WhatsNew.recordEarlierUse(defaults: defaults, widgetDefaults: widgetDefaults)
        XCTAssertNil(defaults.object(forKey: WhatsNew.earlierUseKey))
    }

    func testAutomatedRunsOnlySeeItWhenAsked() {
        XCTAssertFalse(WhatsNew.needsTour(defaults: defaults, arguments: [], isTesting: true))
        XCTAssertTrue(WhatsNew.needsTour(defaults: defaults, arguments: [WhatsNew.showArgument], isTesting: true))
    }

    func testReplayFromSettingsShowsOnlyTheFeatures() {
        XCTAssertEqual(WhatsNew.pages(for: .replay), [.scan, .split, .quickAdd, .siri, .insights])
    }

    /// The tour's backup is the same file Settings saves.
    func testTourBackupMatchesTheSettingsFormat() throws {
        let container = try ModelContainer(
            for: Expense.self, CategoryBudget.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        context.insert(Expense(amount: 12.5, category: "Food", note: "Lunch", date: Date()))
        try context.save()

        let settings = BackupSettings(isBudgetEnabled: true, budgetAmount: 500, alertThreshold: 100, dailyNotify: false, notifyTime: 0)
        let data = try AppBackup.data(from: context, settings: settings)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(AppBackup.self, from: data)
        XCTAssertEqual(backup.formatVersion, AppBackup.currentFormatVersion)
        XCTAssertEqual(backup.expenses.count, 1)
        XCTAssertEqual(backup.expenses.first?.amountMinorUnits, 1250)
        XCTAssertEqual(backup.settings?.budgetAmount, 500)

        let encrypted = try SecureBackupCodec.encrypt(data, passphrase: "correct horse battery")
        XCTAssertEqual(try SecureBackupCodec.decrypt(encrypted, passphrase: "correct horse battery"), data)
    }
}
