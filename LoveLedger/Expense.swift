import Foundation
import SwiftData
import SwiftUI

// 核心枚举：周期性频率
enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case none = "None"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .none: return L10n.recurrenceNone
        case .daily: return L10n.recurrenceDaily
        case .weekly: return L10n.recurrenceWeekly
        case .monthly: return L10n.recurrenceMonthly
        case .yearly: return L10n.recurrenceYearly
        }
    }
}

// 分类预算模型
@Model
final class CategoryBudget {
    var category: String = ""
    var amount: Double = 0.0
    
    init(category: String, amount: Double) {
        self.category = category
        self.amount = amount
    }
}

@Model
final class Expense {
    var id: UUID = UUID()
    var amount: Double = 0.0
    var category: String = "Other"
    var note: String = ""
    var date: Date = Date()
    
    // 频率：Optional 兼容旧数据
    var frequency: RecurrenceFrequency? = RecurrenceFrequency.none
    
    // 核心字段：记录上一次自动生成的时间
    var lastProcessedDate: Date? = nil
    
    // ✨ 新增字段：标记这是否是自动生成的子账单
    // 作用：让 UI 可以显示 Recurring 图标，但逻辑层知道不要再次处理它
    var isRecurringChild: Bool = false
    
    init(amount: Double, category: String, note: String, date: Date = Date(), frequency: RecurrenceFrequency = .none, lastProcessedDate: Date? = nil, isRecurringChild: Bool = false) {
        self.id = UUID()
        self.amount = amount
        self.category = category
        self.note = note
        self.date = date
        self.frequency = frequency
        self.lastProcessedDate = lastProcessedDate
        self.isRecurringChild = isRecurringChild
    }
    
    var safeFrequency: RecurrenceFrequency {
        return frequency ?? .none
    }
    
    // UI 配置
    static let categories: [(name: String, icon: String, color: Color)] = [
        ("Food", "fork.knife", .orange),
        ("Grocery", "basket.fill", .green),
        ("Shopping", "bag.fill", .pink),
        ("Transport", "car.fill", .blue),
        ("Housing", "house.fill", .indigo),
        ("Entertainment", "popcorn.fill", .purple),
        ("Health", "heart.fill", .red),
        ("Utilities", "bolt.fill", .yellow),
        ("Other", "creditcard.fill", .gray)
    ]
    
    var color: Color {
        Expense.categories.first(where: { $0.name == category })?.color ?? .gray
    }
    
    var icon: String {
        Expense.categories.first(where: { $0.name == category })?.icon ?? "questionmark.circle"
    }
}
