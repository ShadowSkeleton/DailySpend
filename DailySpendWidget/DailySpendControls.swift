import AppIntents
import SwiftUI
import WidgetKit

// Control Center, Lock Screen, and Action button controls. Each opens the
// app to a screen where the person reviews before anything is saved. Their
// intent, OpenDailySpendIntent, is shared with the app target.

@available(iOS 18.0, *)
struct ScanReceiptControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.jackson.LoveLedger.ScanReceiptControl") {
            ControlWidgetButton(action: OpenDailySpendIntent(target: .scan)) {
                Label("Scan Receipt", systemImage: "doc.text.viewfinder")
            }
        }
        .displayName("Scan Receipt")
        .description("Opens DailySpend's receipt scanner.")
    }
}

@available(iOS 18.0, *)
struct AddExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.jackson.LoveLedger.AddExpenseControl") {
            ControlWidgetButton(action: OpenDailySpendIntent(target: .add)) {
                Label("Add Expense", systemImage: "plus.circle")
            }
        }
        .displayName("Add Expense")
        .description("Opens a new expense in DailySpend.")
    }
}
