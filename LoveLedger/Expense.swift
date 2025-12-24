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

// ✨ 关键修复：frequency 改为 Optional，兼容旧数据
@Model
final class Expense {
    var id: UUID = UUID()
    var amount: Double = 0.0
    var category: String = "Other"
    var note: String = ""
    var date: Date = Date()
    
    // ✨ 核心修复：改为 Optional，旧数据会自动返回 nil
    var frequency: RecurrenceFrequency? = RecurrenceFrequency.none
    
    init(amount: Double, category: String, note: String, date: Date = Date(), frequency: RecurrenceFrequency = .none) {
        self.id = UUID()
        self.amount = amount
        self.category = category
        self.note = note
        self.date = date
        self.frequency = frequency
    }
    
    // ✨ 便捷属性：安全获取 frequency
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
