import SwiftUI
import SwiftData

@main
struct LoveLedgerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // 守门员机制：在 App 最底层处理周期性检查
                .background(RecurrenceHandler())
        }
        .modelContainer(for: [Expense.self, CategoryBudget.self])
    }
}

struct RecurrenceHandler: View {
    @Environment(\.modelContext) private var modelContext
    
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
        
        for expense in recurringExpenses {
            // 2. 追赶机制
            while let nextDate = RecurrenceEngine.nextDueDate(
                initialDate: expense.date,
                lastProcessed: expense.lastProcessedDate,
                frequency: expense.safeFrequency
            ) {
                print("✨ Creating recurring expense for: \(expense.category) on \(nextDate)")
                
                // 3. 生成新账单
                let newExpense = Expense(
                    amount: expense.amount,
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
        }
        
        if addedCount > 0 {
            do {
                try modelContext.save()
                print("✅ Successfully generated \(addedCount) recurring expenses with icons.")
            } catch {
                print("❌ Failed to save: \(error)")
            }
        }
    }
}
