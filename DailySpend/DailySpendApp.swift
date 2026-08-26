import SwiftUI
import SwiftData

@main
struct LoveLedgerApp: App {
    static let cloudKitContainerIdentifier = "iCloud.com.jackson.LoveLedger"
    static let cloudKitStoreFallbackKey = "cloudKitStoreFallback"

    static var isRunningAutomatedTests: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing") ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // UI tests use a temporary store so automated runs never inspect, alter, or
    // depend on a person's real expense history.
    private let modelContainer: ModelContainer

    init() {
        let isRunningTests = Self.isRunningAutomatedTests
        let configuration = Self.modelConfiguration(isRunningUITests: isRunningTests)

        do {
            modelContainer = try ModelContainer(
                for: Expense.self,
                CategoryBudget.self,
                configurations: configuration
            )
            if !isRunningTests {
                UserDefaults.standard.set(false, forKey: Self.cloudKitStoreFallbackKey)
            }
        } catch {
            // If CloudKit setup is temporarily unavailable, preserve access to
            // the exact same local store instead of blocking someone from their
            // expenses. The next normal launch retries CloudKit automatically.
            do {
                let localConfiguration = ModelConfiguration(cloudKitDatabase: .none)
                modelContainer = try ModelContainer(
                    for: Expense.self,
                    CategoryBudget.self,
                    configurations: localConfiguration
                )
                if !isRunningTests {
                    UserDefaults.standard.set(true, forKey: Self.cloudKitStoreFallbackKey)
                }
            } catch {
                fatalError("Unable to open DailySpend’s local data store: \(error.localizedDescription)")
            }
        }

        #if DEBUG
        DebugSampleData.seedWhenRequested(in: modelContainer)
        #endif

        // The migration is additive: a failed or interrupted run leaves the
        // original Double values in place, and the app can still read them.
        // UI tests start from a temporary empty store and do not need it.
        if !isRunningTests {
            let migrationContext = ModelContext(modelContainer)
            do {
                _ = try MoneyStoreMigration.backfillMissingMinorUnits(in: migrationContext)
            } catch {
                // Keep the app usable with its legacy values. This must never
                // block a person from opening their expense history.
                #if DEBUG
                print("Couldn’t backfill precise money values: \(error.localizedDescription)")
                #endif
            }
        }
    }

    static func modelConfiguration(isRunningUITests: Bool) -> ModelConfiguration {
        ModelConfiguration(
            isStoredInMemoryOnly: isRunningUITests,
            cloudKitDatabase: isRunningUITests ? .none : .private(Self.cloudKitContainerIdentifier)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 守门员机制：在 App 最底层处理周期性检查
                .background(RecurrenceHandler())
        }
        .modelContainer(modelContainer)
    }
}

struct RecurrenceHandler: View {
    @Environment(\.modelContext) private var modelContext

    // A daily entry left untouched for years should not freeze launch by
    // attempting to materialize its entire history at once. The next launch
    // resumes from the saved cursor, so no due occurrence is discarded.
    private static let maximumGeneratedOccurrencesPerLaunch = 366
    
    // 获取所有账单
    @Query(sort: \Expense.date) var allExpenses: [Expense]
    
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { checkRecurrence() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                checkRecurrence()
            }
    }
    
    private func checkRecurrence() {
        // 1. 筛选出所有“母本”账单
        // ✨ 关键变更：我们只处理 frequency != .none 且 不是子账单 的记录
        // 这样子账单虽然有 frequency (为了显示图标)，但不会被再次处理
        let recurringExpenses = allExpenses.filter {
            $0.safeFrequency != .none && $0.isRecurringChild == false
        }
        
        if recurringExpenses.isEmpty { return }
        
        var addedCount = 0
        var reachedCatchUpLimit = false
        
        for expense in recurringExpenses {
            // 2. 追赶机制
            while addedCount < Self.maximumGeneratedOccurrencesPerLaunch,
                  let nextDate = RecurrenceEngine.nextDueDate(
                initialDate: expense.date,
                lastProcessed: expense.lastProcessedDate,
                frequency: expense.safeFrequency
            ) {
                print("✨ Creating recurring expense for: \(expense.category) on \(nextDate)")
                
                // 3. 生成新账单
                let newExpense = Expense(
                    amount: expense.normalizedAmount,
                    amountMinorUnits: expense.money.minorUnits,
                    category: expense.category,
                    note: expense.note.isEmpty ? "(Auto)" : "\(expense.note) (Auto)",
                    date: nextDate,
                    // ✨ 关键变更：
                    // 现在我们继承母本的 frequency，这样 UI 就会显示 Recurring 图标了！
                    frequency: expense.safeFrequency,
                    // 同时标记它是子账单，防止下次循环时被当成母本
                    isRecurringChild: true
                )
                
                modelContext.insert(newExpense)
                
                // 4. 更新母本状态
                expense.lastProcessedDate = nextDate
                addedCount += 1
            }

            if addedCount >= Self.maximumGeneratedOccurrencesPerLaunch {
                reachedCatchUpLimit = true
                break
            }
        }
        
        if addedCount > 0 {
            do {
                try modelContext.save()
                print("✅ Successfully generated \(addedCount) recurring expenses with icons.")
                if reachedCatchUpLimit {
                    print("⏳ DailySpend will continue catching up recurring expenses on a future launch.")
                }
            } catch {
                print("❌ Failed to save: \(error)")
            }
        }
    }
}
