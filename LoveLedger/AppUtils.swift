import SwiftUI
import WidgetKit
import UserNotifications

// MARK: - 0. 数据共享工具
struct WidgetDataService {
    static let appGroup = "group.com.jackson.LoveLedger"
    
    static func saveToWidget(expenses: [Expense], budget: Double, isBudgetEnabled: Bool) {
        let calendar = Calendar.current
        let now = Date()
        
        // 1. 计算本月总额
        let currentMonthTotal = expenses
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
        
        // 2. ✨ 计算过去 7 天的趋势数据 (用于小组件图表)
        // 结果是一个 [Double] 数组，例如 [0, 50, 20, 100, 0, 15, 30]
        var chartData: [Double] = []
        // 获取过去 6 天 + 今天
        for i in (0..<7).reversed() {
            if let date = calendar.date(byAdding: .day, value: -i, to: now) {
                let dailyTotal = expenses
                    .filter { calendar.isDate($0.date, inSameDayAs: date) }
                    .reduce(0) { $0 + $1.amount }
                chartData.append(dailyTotal)
            }
        }
        
        // 3. 写入 UserDefaults
        if let store = UserDefaults(suiteName: appGroup) {
            store.set(currentMonthTotal, forKey: "widget_total")
            store.set(budget, forKey: "widget_budget")
            store.set(isBudgetEnabled, forKey: "widget_isBudgetEnabled")
            store.set(chartData, forKey: "widget_chartData") // ✨ 新增
            store.set(Date(), forKey: "widget_lastUpdated")
        }
        
        // 4. 刷新小组件
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - 1. 本地化翻译引擎
struct L10n {
    static var isZh: Bool {
        guard let lang = Locale.preferredLanguages.first else { return false }
        return lang.hasPrefix("zh")
    }
    
    static var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }
    static var currencySymbol: String { currencyCode == "CNY" ? "¥" : "$" }
    
    static var home: String { isZh ? "首页" : "Home" }
    static var insights: String { isZh ? "统计" : "Insights" }
    static var settings: String { isZh ? "设置" : "Settings" }
    static var thisMonth: String { isZh ? "本月支出" : "THIS MONTH" }
    static var remaining: String { isZh ? "本月剩余" : "REMAINING" }
    static var overBudget: String { isZh ? "已超支" : "OVER BUDGET" }
    static var budget: String { isZh ? "预算" : "Budget" }
    static var recentTransactions: String { isZh ? "最近记录" : "Recent Transactions" }
    static var noExpensesTitle: String { isZh ? "暂无账单" : "No Expenses Yet" }
    static var noExpensesDesc: String { isZh ? "点击 + 号记一笔" : "Tap + to track your first spending." }
    static var newExpense: String { isZh ? "记一笔" : "New Expense" }
    static var editExpense: String { isZh ? "编辑账单" : "Edit Expense" }
    static var amount: String { isZh ? "金额" : "AMOUNT" }
    static var category: String { isZh ? "分类" : "CATEGORY" }
    static var date: String { isZh ? "日期" : "Date" }
    static var notePlaceholder: String { isZh ? "备注..." : "Add a note..." }
    static var save: String { isZh ? "保存" : "Save" }
    static var cancel: String { isZh ? "取消" : "Cancel" }
    static var deleteTransaction: String { isZh ? "删除" : "Delete" }
    static var spendingBreakdown: String { isZh ? "支出构成" : "Spending Breakdown" }
    static var topSpending: String { isZh ? "花费排行" : "Top Spending" }
    static var total: String { isZh ? "总计" : "Total" }
    static var tapTotalAmount: String { isZh ? "请点击小票上的总金额" : "Tap the Total Amount" }
    static var timeRanges: [String] { isZh ? ["本月", "上月", "今年", "全部"] : ["This Month", "Last Month", "This Year", "All Time"] }
    static var noDataFor: String { isZh ? "暂无数据: " : "No data for " }
    
    // ✨ Recurrence (周期性)
    static var recurrence: String { isZh ? "重复周期" : "Repeat" }
    static var recurrenceNone: String { isZh ? "不重复" : "None" }
    static var recurrenceDaily: String { isZh ? "每天" : "Daily" }
    static var recurrenceWeekly: String { isZh ? "每周" : "Weekly" }
    static var recurrenceMonthly: String { isZh ? "每月" : "Monthly" }
    static var recurrenceYearly: String { isZh ? "每年" : "Yearly" }
    
    // Insights Tabs
    static var chartView: String { isZh ? "图表" : "Chart" }
    static var calendarView: String { isZh ? "日历" : "Calendar" }
    static var noSpendDay: String { isZh ? "🎉 完美！今天零支出" : "🎉 Amazing! No spend day." }
    static var dailyTotal: String { isZh ? "当日支出" : "Daily Total" }
    
    // Budget Settings
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
    
    // Scanning Tip
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
    
    // iCloud Status
    static var iCloudStatus: String { isZh ? "iCloud 状态" : "iCloud Status" }
    static var iCloudAvailable: String { isZh ? "已连接 (自动同步中)" : "Signed In (Auto Sync)" }
    static var iCloudUnavailable: String { isZh ? "未连接 (请检查设置)" : "Signed Out (Check Settings)" }
    static var iCloudRestricted: String { isZh ? "受限" : "Restricted" }
    static var iCloudVerifying: String { isZh ? "正在检查..." : "Verifying..." }
    
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
    func scheduleDailyNotification(remaining: Double, time: Date, isEnabled: Bool) {
        let center = UNUserNotificationCenter.current(); center.removePendingNotificationRequests(withIdentifiers: ["dailyBudget"])
        guard isEnabled else { return }
        let content = UNMutableNotificationContent(); content.title = "DailySpend"
        if remaining < 0 {
            let over = abs(remaining)
            let overText = L10n.isZh ? "已超支" : "Over budget by"
            content.body = "📅 \(overText) \(over.formatted(.currency(code: L10n.currencyCode)))"
        } else { content.body = "\(L10n.dailyMessage) \(remaining.formatted(.currency(code: L10n.currencyCode))) \(L10n.remainingSuffix)" }
        content.sound = .default
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        // 修复：移除了多余的转义反斜杠
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
