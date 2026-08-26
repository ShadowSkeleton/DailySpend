import SwiftUI
import SwiftData

struct KeyboardDismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.body.weight(.semibold))
        }
        .accessibilityLabel(L10n.isZh ? "收起键盘" : "Hide keyboard")
        .accessibilityHint(L10n.isZh ? "关闭数字键盘" : "Dismiss the numeric keyboard")
        .accessibilityIdentifier("keyboard-dismiss")
    }
}
import WidgetKit
import UserNotifications

// MARK: - ✨ Recurrence Engine
struct RecurrenceEngine {
    static func nextDueDate(initialDate: Date, lastProcessed: Date?, frequency: RecurrenceFrequency) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let baseDate = lastProcessed ?? initialDate
        var nextDate: Date?
        
        switch frequency {
        case .none: return nil
        case .daily: nextDate = calendar.date(byAdding: .day, value: 1, to: baseDate)
        case .weekly: nextDate = calendar.date(byAdding: .weekOfYear, value: 1, to: baseDate)
        case .monthly:
            if let last = lastProcessed {
                let components = calendar.dateComponents([.month], from: initialDate, to: last)
                let nextMonthOffset = (components.month ?? 0) + 1
                nextDate = calendar.date(byAdding: .month, value: nextMonthOffset, to: initialDate)
            } else {
                nextDate = calendar.date(byAdding: .month, value: 1, to: initialDate)
            }
        case .yearly: nextDate = calendar.date(byAdding: .year, value: 1, to: baseDate)
        }
        
        if let target = nextDate, target <= now, target > baseDate {
            return target
        }
        return nil
    }

    /// Finds the latest scheduled occurrence without generating any historic
    /// records. It is used only when importing an older backup format that did
    /// not record recurrence ownership or processing state.
    static func mostRecentScheduledDate(initialDate: Date, frequency: RecurrenceFrequency, noLaterThan referenceDate: Date) -> Date? {
        guard frequency != .none, initialDate <= referenceDate else { return nil }

        let calendar = Calendar.current
        let offset: Int
        let component: Calendar.Component

        switch frequency {
        case .none:
            return nil
        case .daily:
            offset = calendar.dateComponents([.day], from: initialDate, to: referenceDate).day ?? 0
            component = .day
        case .weekly:
            let days = calendar.dateComponents([.day], from: initialDate, to: referenceDate).day ?? 0
            offset = max(0, days / 7)
            component = .weekOfYear
        case .monthly:
            offset = max(0, calendar.dateComponents([.month], from: initialDate, to: referenceDate).month ?? 0)
            component = .month
        case .yearly:
            offset = max(0, calendar.dateComponents([.year], from: initialDate, to: referenceDate).year ?? 0)
            component = .year
        }

        guard var candidate = calendar.date(byAdding: component, value: offset, to: initialDate) else {
            return initialDate
        }
        if candidate > referenceDate {
            candidate = calendar.date(byAdding: component, value: -1, to: candidate) ?? initialDate
        }
        return candidate
    }
}

// MARK: - Widget Data Service
struct WidgetDataService {
    static let appGroup = "group.com.jackson.LoveLedger"
    static func saveToWidget(expenses: [Expense], budget: Double, isBudgetEnabled: Bool) {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let firstChartDay = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        var currentMonthTotal = Money.zero
        var totalsByDay: [Date: Money] = [:]

        // Build every value in one pass. The Home screen may contain years of
        // records, and widgets should not repeatedly rescan that full list.
        for expense in expenses {
            let amount = expense.money
            if calendar.isDate(expense.date, equalTo: now, toGranularity: .month) {
                currentMonthTotal = currentMonthTotal + amount
            }

            let day = calendar.startOfDay(for: expense.date)
            if day >= firstChartDay && day <= today {
                totalsByDay[day, default: .zero] = totalsByDay[day, default: .zero] + amount
            }
        }

        let chartData = (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: firstChartDay) ?? firstChartDay
            return totalsByDay[day, default: .zero].amount
        }

        if let store = UserDefaults(suiteName: appGroup) {
            store.set(currentMonthTotal.amount, forKey: "widget_total")
            store.set(budget, forKey: "widget_budget")
            store.set(isBudgetEnabled, forKey: "widget_isBudgetEnabled")
            store.set(chartData, forKey: "widget_chartData")
            store.set(Date(), forKey: "widget_lastUpdated")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - L10n
struct L10n {
    static var isZh: Bool {
        guard let lang = Locale.preferredLanguages.first else { return false }
        return lang.hasPrefix("zh")
    }
    
    static var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }
    static var currencySymbol: String {
        Locale.current.currencySymbol ?? Locale(identifier: "en_US").currencySymbol ?? "$"
    }
    
    // Core
    static var home: String { isZh ? "首页" : "Home" }
    static var insights: String { isZh ? "统计" : "Insights" }
    static var settings: String { isZh ? "设置" : "Settings" }
    
    // Dashboard
    static var thisMonth: String { isZh ? "本月支出" : "This Month" }
    static var remaining: String { isZh ? "本月剩余" : "Remaining" }
    static var overBudget: String { isZh ? "已超支" : "Over Budget" }
    static var budget: String { isZh ? "预算" : "Budget" }
    static var recentTransactions: String { isZh ? "最近记录" : "Recent Transactions" }
    static var noExpensesTitle: String { isZh ? "暂无账单" : "No Expenses Yet" }
    static var noExpensesDesc: String { isZh ? "点击 + 号记一笔" : "Tap + to track your first spending." }
    
    // Editor
    static var newExpense: String { isZh ? "记一笔" : "New Expense" }
    static var editExpense: String { isZh ? "编辑账单" : "Edit Expense" }
    static var amount: String { isZh ? "金额" : "Amount" }
    static var category: String { isZh ? "分类" : "Category" }
    static var date: String { isZh ? "日期" : "Date" }
    static var notePlaceholder: String { isZh ? "备注..." : "Add a note..." }
    static var save: String { isZh ? "保存" : "Save" }
    static var cancel: String { isZh ? "取消" : "Cancel" }
    static var deleteTransaction: String { isZh ? "删除" : "Delete" }
    
    // Insights
    static var spendingBreakdown: String { isZh ? "支出构成" : "Spending Breakdown" }
    static var topSpending: String { isZh ? "花费排行" : "Top Spending" }
    static var total: String { isZh ? "总计" : "Total" }
    static var tapTotalAmount: String { isZh ? "请点击小票上的总金额" : "Tap the Total Amount" }
    static var timeRanges: [String] { isZh ? ["本月", "上月", "今年", "全部"] : ["This Month", "Last Month", "This Year", "All Time"] }
    static var noDataFor: String { isZh ? "暂无数据: " : "No data for " }
    static var chartView: String { isZh ? "图表" : "Chart" }
    static var calendarView: String { isZh ? "日历" : "Calendar" }
    static var noSpendDay: String { isZh ? "🎉 完美！今天零支出" : "🎉 Amazing! No spend day." }
    static var dailyTotal: String { isZh ? "当日支出" : "Daily Total" }
    static var trends: String { isZh ? "趋势" : "Trends" }
    static var activity: String { isZh ? "动态" : "Activity" }
    
    // Recurrence
    static var recurrence: String { isZh ? "重复周期" : "Repeat" }
    static var recurrenceNone: String { isZh ? "不重复" : "None" }
    static var recurrenceDaily: String { isZh ? "每天" : "Daily" }
    static var recurrenceWeekly: String { isZh ? "每周" : "Weekly" }
    static var recurrenceMonthly: String { isZh ? "每月" : "Monthly" }
    static var recurrenceYearly: String { isZh ? "每年" : "Yearly" }
    
    // Budget & Settings
    static var budgetEnable: String { isZh ? "启用月度预算" : "Enable Monthly Budget" }
    static var budgetAmount: String { isZh ? "预算金额" : "Budget Amount" }
    static var budgetRequired: String { isZh ? "⚠️ 请输入预算金额" : "⚠️ Budget amount required" }
    static var alertThreshold: String { isZh ? "低余额提醒阈值" : "Low Balance Alert Threshold" }
    static var dailyNotification: String { isZh ? "每日预算播报" : "Daily Budget Report" }
    static var notificationTime: String { isZh ? "播报时间" : "Notification Time" }
    static var alertTitle: String { isZh ? "预算告急" : "Budget Alert" }
    static var alertMessage: String { isZh ? "本月仅剩" : "Only remaining" }
    static var dailyMessage: String { isZh ? "📅 今日预算播报：本月还剩" : "📅 Daily Report: You have" }
    static var remainingSuffix: String { isZh ? "可供支配" : "remaining this month" }
    static var done: String { isZh ? "完成" : "Done" }
    static var ok: String { isZh ? "知道了" : "OK" }
    
    // Scanner
    static var scanTipTitle: String { isZh ? "💡 扫描提示" : "💡 Scanning Tip" }
    static var scanTipMessage: String { isZh ? "拍摄完成后，请点击右上角的 'Save' (保存) 以开始识别。" : "After capturing the receipt, tap 'Save' at the top right to process." }
    static var dontShowAgain: String { isZh ? "不再提示" : "Don't show again" }
    static var gotIt: String { isZh ? "知道了" : "Got it" }
    
    // Data Management
    static var dataManagement: String { isZh ? "数据管理" : "Data Management" }
    static var backupData: String { isZh ? "备份数据 (JSON)" : "Backup Data (JSON)" }
    static var restoreData: String { isZh ? "恢复数据" : "Restore Data" }
    static var restoreAlertTitle: String { isZh ? "确认恢复？" : "Confirm Restore?" }
    static var restoreAlertMessage: String { isZh ? "这将覆盖当前的记账数据，建议先备份。" : "This will overwrite current data. Backup recommended first." }
    static var success: String { isZh ? "成功" : "Success" }
    static var restoreSuccess: String { isZh ? "数据已恢复！\n请检查 '最近记录' 确认日期。" : "Data restored!\nCheck 'Recent Transactions' for dates." }
    static var errorTitle: String { isZh ? "出错了" : "Error" }
    
    // iCloud
    static var iCloudStatus: String { isZh ? "iCloud 状态" : "iCloud Status" }
    static var iCloudAvailable: String { isZh ? "已登录 iCloud" : "Signed in to iCloud" }
    static var iCloudUnavailable: String { isZh ? "未连接 (请检查设置)" : "Signed Out (Check Settings)" }
    static var iCloudRestricted: String { isZh ? "受限" : "Restricted" }
    static var iCloudVerifying: String { isZh ? "正在检查..." : "Verifying..." }
    
    // ✨ Split Bill (Updated for Clarity & Bilingual)
    static var splitModeEvenly: String { isZh ? "平分" : "Evenly" }
    static var splitModeItemized: String { isZh ? "按项" : "Itemized" }
    static var tax: String { isZh ? "税费" : "Tax" }
    static var subtotal: String { isZh ? "餐费小计" : "Subtotal" }
    
    // ✨ UX Improvements & Missing Keys Fix
    static var addItemOrPerson: String { isZh ? "添加项目 / 人" : "Add Item / Person" }
    static var itemNamePlaceholder: String { isZh ? "例如: 汉堡 或 小明" : "e.g., Burger or Alice" }
    // 修复: 之前缺失的 itemizedHelper
    static var itemizedHelper: String { isZh ? "输入具体菜名（如牛排）或人名，我们将按比例分配税费和小费。" : "Enter specific items (e.g. Steak) or people. Tax & tip will be split proportionally." }
    static var recordThisShare: String { isZh ? "记这笔" : "Record" }
    // 修复: 之前缺失的 breakdown 和 breakdownSubtitle
    static var breakdown: String { isZh ? "分配明细" : "Breakdown" }
    static var breakdownSubtitle: String { isZh ? "(含分摊后的税和小费)" : "(incl. shared tax & tip)" }
    
    static func categoryName(_ id: String) -> String {
        guard isZh else { return id }
        switch id {
        case "Food": return "餐饮"; case "Grocery": return "超市/杂货"; case "Shopping": return "购物"; case "Transport": return "交通"; case "Housing": return "居住"; case "Entertainment": return "娱乐"; case "Health": return "医疗"; case "Utilities": return "生活缴费"; case "Other": return "其他"
        default: return id
        }
    }
}

// MARK: - Notification Manager
class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    override init() { super.init(); UNUserNotificationCenter.current().delegate = self }
    func requestPermission() { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in } }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound, .list]) }
    func cancelDailyNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["dailyBudget"])
    }

    func scheduleDailyNotification(remaining: Double, alertThreshold: Double, time: Date, isEnabled: Bool) {
        let center = UNUserNotificationCenter.current(); cancelDailyNotification()
        guard isEnabled else { return }
        let content = UNMutableNotificationContent(); content.title = "DailySpend"
        if remaining < 0 {
            let over = abs(remaining)
            let overText = L10n.isZh ? "已超支" : "Over budget by"
            content.body = "📅 \(overText) \(over.formatted(.currency(code: L10n.currencyCode)))"
        } else if alertThreshold > 0 && remaining <= alertThreshold {
            let thresholdText = alertThreshold.formatted(.currency(code: L10n.currencyCode))
            content.body = L10n.isZh
                ? "📅 本月仅剩 \(remaining.formatted(.currency(code: L10n.currencyCode)))，低于你的 \(thresholdText) 提醒阈值。"
                : "📅 Only \(remaining.formatted(.currency(code: L10n.currencyCode))) remains, below your \(thresholdText) alert threshold."
        } else { content.body = "\(L10n.dailyMessage) \(remaining.formatted(.currency(code: L10n.currencyCode))) \(L10n.remainingSuffix)" }
        content.sound = .default
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: "dailyBudget", content: content, trigger: trigger))
    }
}

// MARK: - UI Extension
extension View {
    func roundedNumFont(size: CGFloat, weight: Font.Weight = .bold) -> some View {
        self.font(.system(size: size, weight: weight, design: .rounded))
    }
}
extension Date {
    func startOfMonth() -> Date { Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self))! }
    func endOfMonth() -> Date { Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: self.startOfMonth())! }
    func getAllDays() -> [Date] {
        let calendar = Calendar.current; let range = calendar.range(of: .day, in: .month, for: self)!; let start = self.startOfMonth()
        return range.compactMap { day -> Date in return calendar.date(byAdding: .day, value: day - 1, to: start)! }
    }
}

// MARK: - Debug-only sample data
// This is deliberately compiled out of Release builds. It is opt-in at launch,
// writes only into an empty store, and never changes the persistent schema.
#if DEBUG
enum DebugSampleData {
    static let launchArgument = "-seed-demo-data"

    @MainActor
    static func seedWhenRequested(in container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }

        let context = container.mainContext
        let existingExpenses = (try? context.fetchCount(FetchDescriptor<Expense>())) ?? 1
        guard existingExpenses == 0 else { return }

        let calendar = Calendar.current
        let now = Date()
        let sampleExpenses: [(daysAgo: Int, amount: Double, category: String, note: String)] = [
            (0, 4.80, "Food", "[Demo] Coffee at Atlas"),
            (1, 18.60, "Transport", "[Demo] Subway and bus"),
            (1, 42.15, "Grocery", "[Demo] Weeknight groceries"),
            (2, 16.40, "Food", "[Demo] Lunch with Morgan"),
            (3, 12.99, "Entertainment", "[Demo] Movie rental"),
            (4, 36.72, "Shopping", "[Demo] Running supplies"),
            (5, 9.50, "Food", "[Demo] Bakery"),
            (6, 25.00, "Health", "[Demo] Pharmacy"),
            (8, 58.40, "Utilities", "[Demo] Mobile plan"),
            (10, 31.85, "Grocery", "[Demo] Farmers market"),
            (13, 72.00, "Housing", "[Demo] Home supplies"),
            (18, 21.30, "Food", "[Demo] Dinner with friends"),
            (24, 14.25, "Transport", "[Demo] Ride share"),
            (31, 68.45, "Grocery", "[Demo] Monthly staples"),
            (38, 54.00, "Entertainment", "[Demo] Concert tickets"),
            (47, 22.75, "Food", "[Demo] Sunday brunch"),
            (62, 110.00, "Utilities", "[Demo] Electric bill"),
            (75, 39.90, "Shopping", "[Demo] Gift for a friend")
        ]

        for sample in sampleExpenses {
            let date = calendar.date(byAdding: .day, value: -sample.daysAgo, to: now) ?? now
            context.insert(Expense(
                amount: sample.amount,
                category: sample.category,
                note: sample.note,
                date: date
            ))
        }

        let existingBudgets = (try? context.fetchCount(FetchDescriptor<CategoryBudget>())) ?? 1
        if existingBudgets == 0 {
            [
                CategoryBudget(category: "Food", amount: 180),
                CategoryBudget(category: "Grocery", amount: 180),
                CategoryBudget(category: "Transport", amount: 100),
                CategoryBudget(category: "Entertainment", amount: 80)
            ].forEach(context.insert)
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: "isBudgetEnabled")
            UserDefaults.standard.set(650.0, forKey: "budgetAmount")
            UserDefaults.standard.set(120.0, forKey: "alertThreshold")
        } catch {
            assertionFailure("Could not seed DailySpend debug data: \(error.localizedDescription)")
        }
    }
}
#endif
