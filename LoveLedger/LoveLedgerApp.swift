import SwiftUI
import SwiftData

@main
struct LoveLedgerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // 关键：注册所有模型
        .modelContainer(for: [Expense.self, CategoryBudget.self])
    }
}
