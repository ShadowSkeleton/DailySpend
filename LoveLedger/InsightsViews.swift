import SwiftUI
import SwiftData
import Charts

// MARK: - ✨ 全局定义：时间范围枚举
// 这个枚举定义在这里，整个模块都可以使用
enum InsightTimeRange: Equatable {
    case thisMonth
    case lastMonth
    case last3Months
    case last6Months
    case thisYear
    case allTime
    case customMonth(Date)
    
    // 预设选项 (用于顶部胶囊)
    static let presets: [InsightTimeRange] = [
        .thisMonth, .lastMonth, .last3Months, .last6Months, .thisYear, .allTime
    ]
    
    func isSameType(as other: InsightTimeRange) -> Bool {
        switch (self, other) {
        case (.thisMonth, .thisMonth),
             (.lastMonth, .lastMonth),
             (.last3Months, .last3Months),
             (.last6Months, .last6Months),
             (.thisYear, .thisYear),
             (.allTime, .allTime),
             (.customMonth, .customMonth):
            return true
        default: return false
        }
    }
    
    var shortTitle: String {
        switch self {
        case .thisMonth: return L10n.isZh ? "本月" : "This Month"
        case .lastMonth: return L10n.isZh ? "上月" : "Last Month"
        case .last3Months: return L10n.isZh ? "近3月" : "3M"
        case .last6Months: return L10n.isZh ? "近半年" : "6M"
        case .thisYear: return L10n.isZh ? "今年" : "Year"
        case .allTime: return L10n.isZh ? "全部" : "All"
        case .customMonth: return L10n.isZh ? "自选" : "Custom"
        }
    }
    
    var displayName: String {
        switch self {
        case .thisMonth: return L10n.timeRanges[0]
        case .lastMonth: return L10n.timeRanges[1]
        case .customMonth(let date): return date.formatted(.dateTime.month().year())
        case .last3Months: return L10n.isZh ? "过去3个月" : "Last 3 Months"
        case .last6Months: return L10n.isZh ? "过去半年" : "Last 6 Months"
        case .thisYear: return L10n.timeRanges[2]
        case .allTime: return L10n.timeRanges[3]
        }
    }
}

// MARK: - Insights View (主视图)
struct InsightsView: View {
    @Query private var expenses: [Expense]
    @Query private var categoryBudgets: [CategoryBudget]

    var themeColor: Color
    @State private var selectedTab: InsightTab = .trends

    @State private var currentMonth = Date()
    @State private var selectedDate: Date? = Date()
    
    @AppStorage("isBudgetEnabled") private var isBudgetEnabled = false
    @AppStorage("budgetAmount") private var budgetAmount = 0.0

    let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 顶部概览卡片 (引用自 InsightsAnalysis.swift)
                InsightAnalysisCard(expenses: expenses)
                    .padding(.top, 16)

                // Tab 切换器 (引用自 InsightsAnalysis.swift)
                CustomTabSwitcher(selectedTab: $selectedTab, themeColor: themeColor)
                    .padding(.horizontal)

                contentView
            }
            .padding(.bottom, 30)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
        }
        .navigationTitle(L10n.insights)
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
        .onAppear {
            if selectedDate == nil { selectedDate = Date() }
            currentMonth = Date()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if selectedTab == .trends {
            TrendsSection(
                expenses: expenses,
                categoryBudgets: categoryBudgets,
                isBudgetEnabled: isBudgetEnabled,
                cardBackground: cardBackground,
                themeColor: themeColor
            )
            .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            // Activity Section (引用自 InsightsActivity.swift)
            ActivitySection(
                currentMonth: $currentMonth,
                selectedDate: $selectedDate,
                expenses: expenses,
                themeColor: themeColor,
                cardBackground: cardBackground,
                isBudgetEnabled: isBudgetEnabled,
                budgetAmount: budgetAmount
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

// MARK: - Trends Section (UI UX Optimized)
struct TrendsSection: View {
    let expenses: [Expense]
    let categoryBudgets: [CategoryBudget]
    let isBudgetEnabled: Bool
    let cardBackground: Color
    let themeColor: Color

    @State private var timeRange: InsightTimeRange = .thisMonth
    @State private var selectedCategoryName: String?
    @State private var showMonthPicker = false
    @State private var navigationDate = Date()

    var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        let now = Date()
        
        return expenses.filter { expense in
            switch timeRange {
            case .thisMonth:
                return calendar.isDate(expense.date, equalTo: now, toGranularity: .month)
            case .lastMonth:
                guard let last = calendar.date(byAdding: .month, value: -1, to: now) else { return false }
                return calendar.isDate(expense.date, equalTo: last, toGranularity: .month)
            case .customMonth(let date):
                return calendar.isDate(expense.date, equalTo: date, toGranularity: .month)
            case .last3Months:
                guard let start = calendar.date(byAdding: .month, value: -3, to: now) else { return false }
                return expense.date >= start && expense.date <= now
            case .last6Months:
                guard let start = calendar.date(byAdding: .month, value: -6, to: now) else { return false }
                return expense.date >= start && expense.date <= now
            case .thisYear:
                return calendar.isDate(expense.date, equalTo: now, toGranularity: .year)
            case .allTime:
                return true
            }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // MARK: 1. 混合导航栏
            HStack(spacing: 12) {
                // 左侧预设胶囊
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(InsightTimeRange.presets, id: \.shortTitle) { option in
                            let isSelected = timeRange.isSameType(as: option)
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    timeRange = option
                                }
                                UISelectionFeedbackGenerator().selectionChanged()
                            }) {
                                Text(option.shortTitle)
                                    .font(.subheadline)
                                    .fontWeight(isSelected ? .bold : .medium)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? themeColor : Color.gray.opacity(0.1))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.leading)
                    .padding(.trailing, 4)
                }
                
                Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 24)
                
                // ✨ 日历开关按钮 (UI 修复：使用 ZStack 固定尺寸，避免点击时大小变化)
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if isCustomMode {
                            timeRange = .thisMonth
                        } else {
                            timeRange = .customMonth(navigationDate)
                        }
                    }
                }) {
                    ZStack {
                        // 固定大小的背景圆，始终存在（只改变颜色）
                        Circle()
                            .fill(isCustomMode ? themeColor.opacity(0.15) : Color.clear)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "calendar")
                            .font(.title3)
                            .foregroundStyle(isCustomMode ? themeColor : .secondary)
                    }
                    .frame(width: 44, height: 44)
                }
                .padding(.trailing, 8)
                .accessibilityLabel(L10n.isZh
                    ? (isCustomMode ? "退出自定义月份" : "选择自定义月份")
                    : (isCustomMode ? "Exit custom month" : "Choose a custom month"))
                .accessibilityHint(L10n.isZh
                    ? "显示月份选择和前后月份导航。"
                    : "Shows the month picker and previous or next month navigation.")
            }
            
            // MARK: 2. 月份导航器 (仅 Custom 模式)
            if case .customMonth(let date) = timeRange {
                VStack(spacing: 12) {
                    // Row 1: 居中导航 (左右箭头 + 标题)
                    HStack(spacing: 24) {
                        Button(action: { moveMonth(by: -1) }) {
                            Image(systemName: "chevron.left")
                                .font(.headline).foregroundStyle(themeColor)
                                .frame(width: 44, height: 44).background(themeColor.opacity(0.1)).clipShape(Circle())
                        }
                        .accessibilityLabel(L10n.isZh ? "上个月" : "Previous month")
                        
                        Button(action: { showMonthPicker = true }) {
                            Text(date.formatted(.dateTime.month(.wide).year()))
                                .font(.headline).foregroundStyle(themeColor)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(themeColor.opacity(0.1)).clipShape(Capsule())
                        }
                        .accessibilityLabel(L10n.isZh ? "选择月份" : "Choose month")
                        
                        Button(action: { moveMonth(by: 1) }) {
                            Image(systemName: "chevron.right")
                                .font(.headline)
                                .foregroundStyle(isFuture(date: date) ? themeColor.opacity(0.3) : themeColor)
                                .frame(width: 44, height: 44).background(themeColor.opacity(0.1)).clipShape(Circle())
                        }
                        .disabled(isFuture(date: date))
                        .accessibilityLabel(L10n.isZh ? "下个月" : "Next month")
                    }
                    
                    // Row 2: "Back to Today" 单独一行，右对齐
                    if !Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month) {
                        HStack {
                            Spacer()
                            Button(action: {
                                let now = Date()
                                navigationDate = now
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { timeRange = .customMonth(now) }
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.backward")
                                    Text("Back to Today")
                                }
                                .font(.caption).fontWeight(.bold)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(themeColor.opacity(0.1))
                                .foregroundStyle(themeColor)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // MARK: 3. 内容展示 (引用 Charts 和 Analysis 文件中的组件)
            if filteredExpenses.isEmpty {
                ContentUnavailableView(L10n.noDataFor + timeRange.displayName, systemImage: "chart.xyaxis.line")
                    .padding(.top, 40)
            } else {
                SpendingTrendChart(
                    expenses: filteredExpenses,
                    timeRange: timeRange,
                    cardBackground: cardBackground,
                    themeColor: themeColor
                )

                InteractivePieChart(
                    expenses: filteredExpenses,
                    categoryBudgets: categoryBudgets,
                    isBudgetEnabled: isBudgetEnabled,
                    selectedRange: timeRange,
                    selectedCategoryName: $selectedCategoryName,
                    themeColor: themeColor,
                    cardBackground: cardBackground
                )

                RankingList(
                    expenses: filteredExpenses,
                    categoryBudgets: categoryBudgets,
                    isBudgetEnabled: isBudgetEnabled,
                    selectedRange: timeRange,
                    selectedCategoryName: $selectedCategoryName,
                    cardBackground: cardBackground
                )
            }
        }
        .onDisappear { selectedCategoryName = nil }
        .sheet(isPresented: $showMonthPicker) {
            // 引用自 InsightsActivity.swift (我们复用那个选择器)
            InsightsMonthYearPicker(selection: $navigationDate, themeColor: themeColor, isPresented: $showMonthPicker)
                .onDisappear { withAnimation { timeRange = .customMonth(navigationDate) } }
        }
    }
    
    var isCustomMode: Bool {
        if case .customMonth = timeRange { return true }
        return false
    }
    
    private func moveMonth(by value: Int) {
        if case .customMonth(let date) = timeRange {
            if let newDate = Calendar.current.date(byAdding: .month, value: value, to: date) {
                if value > 0 && isFuture(date: newDate) { return }
                navigationDate = newDate
                withAnimation { timeRange = .customMonth(newDate) }
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }
    
    private func isFuture(date: Date) -> Bool {
        return Calendar.current.startOfMonth(for: date) > Calendar.current.startOfMonth(for: Date())
    }
}

// 辅助扩展
extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
