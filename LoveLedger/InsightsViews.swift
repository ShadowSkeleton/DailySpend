import SwiftUI
import SwiftData
import Charts

// MARK: - Insights View
struct InsightsView: View {
    @Query private var expenses: [Expense]
    @Query private var categoryBudgets: [CategoryBudget]

    var themeColor: Color
    // 使用 AppModels.swift 中定义的 InsightTab
    @State private var selectedTab: InsightTab = .trends

    @State private var currentMonth = Date()
    @State private var selectedDate: Date? = Date()
    @AppStorage("isBudgetEnabled") private var isBudgetEnabled = false
    @AppStorage("budgetAmount") private var budgetAmount = 0.0

    let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. 全局概览卡片
                InsightAnalysisCard(expenses: expenses)
                    .padding(.top, 16)

                // 2. 自定义 Tab 切换器
                CustomTabSwitcher(selectedTab: $selectedTab, themeColor: themeColor)
                    .padding(.horizontal)

                // 3. 内容区域 (拆分为独立函数以避免编译器超时)
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

// MARK: - Custom Tab Switcher
struct CustomTabSwitcher: View {
    @Binding var selectedTab: InsightTab
    var themeColor: Color
    @Namespace private var animationNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(InsightTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(tab.displayName)
                        .font(.headline)
                        .fontWeight(selectedTab == tab ? .bold : .medium)
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(themeColor)
                                    .matchedGeometryEffect(id: "TabBackground", in: animationNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Trends Section
struct TrendsSection: View {
    let expenses: [Expense]
    let categoryBudgets: [CategoryBudget]
    let isBudgetEnabled: Bool
    let cardBackground: Color
    let themeColor: Color

    @State private var selectedRange: TimeRange = .thisMonth
    @State private var selectedCategoryName: String?

    var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        let now = Date()
        return expenses.filter { expense in
            switch selectedRange {
            case .thisMonth: return calendar.isDate(expense.date, equalTo: now, toGranularity: .month)
            case .lastMonth:
                guard let last = calendar.date(byAdding: .month, value: -1, to: now) else { return false }
                return calendar.isDate(expense.date, equalTo: last, toGranularity: .month)
            case .thisYear: return calendar.isDate(expense.date, equalTo: now, toGranularity: .year)
            case .all: return true
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Picker("Time Range", selection: $selectedRange) {
                ForEach(TimeRange.allCases) { range in Text(range.displayName).tag(range) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: selectedRange) { _, _ in selectedCategoryName = nil }

            if filteredExpenses.isEmpty {
                ContentUnavailableView(L10n.noDataFor + selectedRange.displayName, systemImage: "chart.xyaxis.line")
                    .padding(.top, 40)
            } else {
                SpendingTrendChart(
                    expenses: filteredExpenses,
                    timeRange: selectedRange,
                    cardBackground: cardBackground,
                    themeColor: themeColor
                )

                InteractivePieChart(
                    expenses: filteredExpenses,
                    categoryBudgets: categoryBudgets,
                    isBudgetEnabled: isBudgetEnabled,
                    selectedRange: selectedRange,
                    selectedCategoryName: $selectedCategoryName,
                    themeColor: themeColor,
                    cardBackground: cardBackground
                )

                RankingList(
                    expenses: filteredExpenses,
                    categoryBudgets: categoryBudgets,
                    isBudgetEnabled: isBudgetEnabled,
                    selectedRange: selectedRange,
                    selectedCategoryName: $selectedCategoryName,
                    cardBackground: cardBackground
                )
            }
        }
        .onDisappear { selectedCategoryName = nil }
    }
}

// MARK: - Activity Section
struct ActivitySection: View {
    @Binding var currentMonth: Date
    @Binding var selectedDate: Date?
    let expenses: [Expense]
    let themeColor: Color
    let cardBackground: Color
    let isBudgetEnabled: Bool
    let budgetAmount: Double

    var currentDayExpenses: [Expense] {
        if let date = selectedDate {
            return expenses.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        }
        return []
    }

    var body: some View {
        VStack(spacing: 24) {
            CalendarView(
                currentMonth: $currentMonth,
                selectedDate: $selectedDate,
                expenses: expenses,
                themeColor: themeColor,
                cardBackground: cardBackground,
                isBudgetEnabled: isBudgetEnabled,
                budgetAmount: budgetAmount
            )

            DayDetailView(
                date: selectedDate,
                expenses: currentDayExpenses,
                themeColor: themeColor,
                cardBackground: cardBackground
            )
        }
    }
}

// MARK: - Spending Trend Chart
struct SpendingTrendChart: View {
    let expenses: [Expense]
    let timeRange: TimeRange
    let cardBackground: Color
    let themeColor: Color

    @State private var selectedDate: Date?
    @State private var selectedAmount: Double?

    struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let amount: Double
    }

    var currentGranularity: Calendar.Component {
        (timeRange == .thisYear || timeRange == .all) ? .month : .day
    }

    private func isDateSelected(_ date: Date) -> Bool {
        guard let sel = selectedDate else { return false }
        return Calendar.current.isDate(date, equalTo: sel, toGranularity: currentGranularity)
    }

    var dateLabel: String {
        let now = Date()
        let calendar = Calendar.current
        switch timeRange {
        case .thisMonth: return now.formatted(.dateTime.month(.wide).year())
        case .lastMonth: return calendar.date(byAdding: .month, value: -1, to: now)?.formatted(.dateTime.month(.wide).year()) ?? ""
        case .thisYear: return now.formatted(.dateTime.year())
        case .all: return L10n.isZh ? "全部时间" : "All Time"
        }
    }

    var trendData: [TrendPoint] {
        let calendar = Calendar.current
        var points: [TrendPoint] = []
        let granularity = currentGranularity
        let grouped = Dictionary(grouping: expenses) { expense in calendar.startOfDay(for: expense.date) }

        if granularity == .month {
            let monthlyGrouped = Dictionary(grouping: expenses) { expense in
                calendar.date(from: calendar.dateComponents([.year, .month], from: expense.date))!
            }
            let sortedKeys = monthlyGrouped.keys.sorted()
            for date in sortedKeys {
                let total = monthlyGrouped[date]?.reduce(0) { $0 + $1.amount } ?? 0
                points.append(TrendPoint(date: date, amount: total))
            }
        } else {
            let sortedKeys = grouped.keys.sorted()
            if let firstDate = sortedKeys.first, let lastDate = sortedKeys.last {
                var currentDate = firstDate
                while currentDate <= lastDate {
                    let total = grouped[currentDate]?.reduce(0) { $0 + $1.amount } ?? 0
                    points.append(TrendPoint(date: currentDate, amount: total))
                    currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
                }
            }
        }
        return points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(themeColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.isZh ? "消费趋势" : "Spending Trend")
                        .font(.headline)
                    Text(dateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let amount = selectedAmount, let date = selectedDate {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(amount.formatted(.currency(code: L10n.currencyCode)))
                            .font(.headline).foregroundStyle(themeColor)
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            if trendData.isEmpty {
                ContentUnavailableView("No enough data", systemImage: "chart.xyaxis.line").frame(height: 200)
            } else {
                Chart {
                    ForEach(trendData) { item in
                        AreaMark(
                            x: .value("Date", item.date, unit: currentGranularity),
                            y: .value("Amount", item.amount)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [themeColor.opacity(0.3), themeColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Date", item.date, unit: currentGranularity),
                            y: .value("Amount", item.amount)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(themeColor)
                        .lineStyle(StrokeStyle(lineWidth: 3))

                        if isDateSelected(item.date) {
                            PointMark(
                                x: .value("Date", item.date, unit: currentGranularity),
                                y: .value("Amount", item.amount)
                            )
                            .foregroundStyle(themeColor)
                            .symbolSize(100)
                        }
                    }
                }
                .frame(height: 220)
                .chartXSelection(value: $selectedDate)
                .onChange(of: selectedDate) { _, newValue in
                    if let date = newValue {
                        if let match = trendData.first(where: {
                            Calendar.current.isDate($0.date, equalTo: date, toGranularity: currentGranularity)
                        }) {
                            selectedAmount = match.amount
                            UISelectionFeedbackGenerator().selectionChanged()
                        } else {
                            selectedAmount = nil
                        }
                    } else {
                        selectedAmount = nil
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: currentGranularity, count: (timeRange == .thisYear || timeRange == .all) ? 1 : 5)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(
                                    date.formatted(
                                        (timeRange == .thisYear || timeRange == .all)
                                        ? .dateTime.month(.abbreviated)
                                        : .dateTime.day()
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Color.gray.opacity(0.1))
                        AxisValueLabel()
                    }
                }
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 24).fill(cardBackground).shadow(color: .black.opacity(0.03), radius: 15))
        .padding(.horizontal)
    }
}

// MARK: - Interactive Pie Chart
struct InteractivePieChart: View {
    let expenses: [Expense]
    let categoryBudgets: [CategoryBudget]
    let isBudgetEnabled: Bool
    let selectedRange: TimeRange
    @Binding var selectedCategoryName: String?
    let themeColor: Color
    let cardBackground: Color

    var totalAmount: Double { expenses.reduce(0) { $0 + $1.amount } }

    var categoryStats: [(name: String, displayName: String, total: Double, color: Color)] {
        let grouped = Dictionary(grouping: expenses, by: { $0.category })
        return grouped.map { (key, value) in
            let total = value.reduce(0) { $0 + $1.amount }
            let color = Expense.categories.first(where: { $0.name == key })?.color ?? .gray
            return (key, L10n.categoryName(key), total, color)
        }.sorted {
            if $0.total != $1.total { return $0.total > $1.total } else { return $0.name < $1.name }
        }
    }

    func findSelectedCategory(value: Double) -> String? {
        var accumulated = 0.0
        for item in categoryStats {
            let next = accumulated + item.total
            if value >= accumulated && value <= next { return item.name }
            accumulated = next
        }
        return nil
    }

    var dateLabel: String {
        let now = Date()
        let calendar = Calendar.current
        switch selectedRange {
        case .thisMonth: return now.formatted(.dateTime.month(.wide).year())
        case .lastMonth: return calendar.date(byAdding: .month, value: -1, to: now)?.formatted(.dateTime.month(.wide).year()) ?? ""
        case .thisYear: return now.formatted(.dateTime.year())
        case .all: return L10n.isZh ? "全部时间" : "All Time"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(themeColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.spendingBreakdown).font(.headline)
                    Text(dateLabel).font(.caption).foregroundStyle(.secondary)
                }
            }

            ZStack {
                Chart(categoryStats, id: \.name) { item in
                    let isSelected = selectedCategoryName == item.name
                    SectorMark(
                        angle: .value("Amount", item.total),
                        innerRadius: .ratio(0.62),
                        outerRadius: isSelected ? .ratio(1.0) : .ratio(0.9),
                        angularInset: 2
                    )
                    .cornerRadius(8)
                    .foregroundStyle(item.color)
                    .shadow(radius: isSelected ? 4 : 0)
                    .opacity(selectedCategoryName == nil || isSelected ? 1.0 : 0.5)
                }
                .frame(height: 260)
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Color.clear
                            .contentShape(Circle())
                            .onTapGesture { location in
                                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                                let vector = CGVector(dx: location.x - center.x, dy: location.y - center.y)
                                var angle = atan2(vector.dy, vector.dx) + .pi / 2
                                if angle < 0 { angle += 2 * .pi }
                                let angleValue = (angle / (2 * .pi)) * totalAmount

                                if let category = findSelectedCategory(value: angleValue) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                        if selectedCategoryName == category {
                                            selectedCategoryName = nil
                                        } else {
                                            selectedCategoryName = category
                                        }
                                    }
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                            }
                    }
                }

                VStack(spacing: 4) {
                    if let selectedName = selectedCategoryName,
                       let selectedItem = categoryStats.first(where: { $0.name == selectedName }) {
                        Text(L10n.categoryName(selectedItem.name))
                            .font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
                        Text(selectedItem.total.formatted(.currency(code: L10n.currencyCode)))
                            .roundedNumFont(size: 28, weight: .black)
                            .foregroundStyle(selectedItem.color)
                            .minimumScaleFactor(0.5).lineLimit(1)
                            .contentTransition(.numericText())
                        Text("\(String(format: "%.1f", selectedItem.total / totalAmount * 100))%")
                            .font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(selectedItem.color.opacity(0.1)).clipShape(Capsule())
                    } else {
                        Text(L10n.total).font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
                        Text(totalAmount.formatted(.currency(code: L10n.currencyCode)))
                            .roundedNumFont(size: 28, weight: .black)
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.5).lineLimit(1)
                            .contentTransition(.numericText())
                    }
                }
                .frame(width: 140)
                .allowsHitTesting(false)
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 24).fill(cardBackground).shadow(color: .black.opacity(0.03), radius: 15))
        .padding(.horizontal)
    }
}

// MARK: - Ranking List Component
struct RankingList: View {
    let expenses: [Expense]
    let categoryBudgets: [CategoryBudget]
    let isBudgetEnabled: Bool
    let selectedRange: TimeRange
    @Binding var selectedCategoryName: String?
    let cardBackground: Color

    var categoryStats: [(name: String, displayName: String, total: Double, color: Color)] {
        let grouped = Dictionary(grouping: expenses, by: { $0.category })
        return grouped.map { (key, value) in
            let total = value.reduce(0) { $0 + $1.amount }
            let color = Expense.categories.first(where: { $0.name == key })?.color ?? .gray
            return (key, L10n.categoryName(key), total, color)
        }.sorted {
            if $0.total != $1.total { return $0.total > $1.total } else { return $0.name < $1.name }
        }
    }

    func getBudget(for category: String) -> Double? {
        guard let budget = categoryBudgets.first(where: { $0.category == category }), budget.amount > 0 else { return nil }
        return budget.amount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.number")
                    .foregroundStyle(.blue)
                Text(L10n.topSpending).font(.headline).foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            VStack(spacing: 12) {
                ForEach(categoryStats, id: \.name) { item in
                    let isSelected = selectedCategoryName == item.name
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Circle().fill(item.color).frame(width: 12, height: 12)
                            Text(item.displayName).fontWeight(.medium)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(item.total.formatted(.currency(code: L10n.currencyCode)))
                                    .roundedNumFont(size: 16, weight: .semibold)
                                Text("\(String(format: "%.1f", item.total / (categoryStats.reduce(0) { $0 + $1.total }) * 100))%")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if isBudgetEnabled, let budget = getBudget(for: item.name), selectedRange == .thisMonth {
                            VStack(alignment: .leading, spacing: 4) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.gray.opacity(0.1))
                                        Capsule().fill(item.total > budget ? Color.red : item.color)
                                            .frame(width: min(geo.size.width * (item.total / budget), geo.size.width))
                                    }
                                }.frame(height: 4)
                                HStack {
                                    if item.total > budget {
                                        Text("Over budget by \((item.total - budget).formatted(.currency(code: L10n.currencyCode)))")
                                            .font(.caption2).foregroundStyle(.red)
                                    } else {
                                        Text("Budget: \(budget.formatted(.currency(code: L10n.currencyCode)))")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(isSelected ? item.color.opacity(0.1) : cardBackground).shadow(color: .black.opacity(0.02), radius: 5))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            selectedCategoryName = (selectedCategoryName == item.name) ? nil : item.name
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
            }.padding(.horizontal)
        }
    }
}

// MARK: - Insight Analysis Card
struct InsightAnalysisCard: View {
    let expenses: [Expense]
    var analysis: (diff: Double, driver: String, driverAmount: Double, isUp: Bool)? {
        let calendar = Calendar.current
        let now = Date()
        let startOfThisMonth = now.startOfMonth()
        guard let startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth),
              let endOfLastMonthMTD = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
        let thisMonthExpenses = expenses.filter { $0.date >= startOfThisMonth && $0.date <= now }
        let lastMonthExpenses = expenses.filter { $0.date >= startOfLastMonth && $0.date <= endOfLastMonthMTD }
        let thisTotal = thisMonthExpenses.reduce(0) { $0 + $1.amount }
        let lastTotal = lastMonthExpenses.reduce(0) { $0 + $1.amount }
        if thisTotal == 0 && lastTotal == 0 { return nil }
        let diff = thisTotal - lastTotal
        if abs(diff) < 1 { return nil }
        let thisCats = Dictionary(grouping: thisMonthExpenses, by: { $0.category }).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let lastCats = Dictionary(grouping: lastMonthExpenses, by: { $0.category }).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let allCategories = Set(thisCats.keys).union(lastCats.keys)
        var driverCat = ""; var driverDelta = 0.0
        if diff > 0 {
            var maxIncrease = -Double.infinity
            for cat in allCategories {
                let increase = (thisCats[cat] ?? 0) - (lastCats[cat] ?? 0)
                if increase > maxIncrease { maxIncrease = increase; driverCat = cat }
            }
            driverDelta = maxIncrease
        } else {
            var maxDecrease = Double.infinity
            for cat in allCategories {
                let decrease = (thisCats[cat] ?? 0) - (lastCats[cat] ?? 0)
                if decrease < maxDecrease { maxDecrease = decrease; driverCat = cat }
            }
            driverDelta = maxDecrease
        }
        return (diff, driverCat, driverDelta, diff > 0)
    }

    // ✅ FIX: avoid interpolating Text inside Text("... \(Text) ...") which can crash the compiler diagnostics.
    func explanationText(data: (diff: Double, driver: String, driverAmount: Double, isUp: Bool)) -> Text {
        let categoryName = L10n.categoryName(data.driver)
        let amountStr = (data.driverAmount > 0 ? "+" : "") + data.driverAmount.formatted(.currency(code: L10n.currencyCode))

        // Replaced concatenated Text with single interpolated Text per instructions:
        if L10n.isZh {
            // "主要原因是 {cat} 的支出变动 {amt}"
            return Text("主要原因是 \(categoryName) 的支出变动 \(amountStr)").fontWeight(.bold)
        } else {
            // "Driven primarily by changes in {cat} spending ({amt})"
            return Text("Driven primarily by changes in \(categoryName) spending (\(amountStr))").fontWeight(.bold)
        }
    }

    var body: some View {
        if let data = analysis {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.isZh ? "月度支出摘要" : "Spending Summary")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: data.isUp ? "arrow.up" : "arrow.down")
                        Text(L10n.isZh ? "对比上月" : "vs Last Month")
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(data.isUp ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    .foregroundStyle(data.isUp ? .red : .green)
                    .clipShape(Capsule())
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(abs(data.diff).formatted(.currency(code: L10n.currencyCode)))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(data.isUp ? (L10n.isZh ? "增加" : "More") : (L10n.isZh ? "减少" : "Less"))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(data.isUp ? .red : .green)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    explanationText(data: data)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
            .padding(.horizontal)
        }
    }
}

// MARK: - Calendar View
struct CalendarView: View {
    @Binding var currentMonth: Date
    @Binding var selectedDate: Date?
    let expenses: [Expense]
    let themeColor: Color
    let cardBackground: Color
    var isBudgetEnabled: Bool
    var budgetAmount: Double
    @State private var cachedExpenses: [Date: Double] = [:]
    @State private var showMonthPicker = false

    var colorBenchmark: Double {
        let dailyTotals = cachedExpenses.values.filter { $0 > 0 }.sorted()
        guard !dailyTotals.isEmpty else { return 100.0 }
        let index = Int(Double(dailyTotals.count) * 0.9)
        if index < dailyTotals.count { return dailyTotals[index] }
        return dailyTotals.last ?? 100.0
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showMonthPicker = true
                }) {
                    HStack(spacing: 6) {
                        Text(currentMonth.formatted(.dateTime.year().month()))
                            .font(.title3)
                            .bold()
                            .foregroundStyle(.primary)
                            // ✅ FIX: use numericText() (function) instead of numericText (value)
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(themeColor.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if !Calendar.current.isDate(currentMonth, equalTo: Date(), toGranularity: .month) {
                    Button(action: {
                        withAnimation(.spring()) { currentMonth = Date() }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }) {
                        HStack(spacing: 4) { Image(systemName: "arrow.uturn.backward"); Text("Today") }
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(themeColor.opacity(0.1))
                            .foregroundStyle(themeColor)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)

            let days = currentMonth.getAllDays()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(day).font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                }
                if let first = days.first {
                    let firstWeekday = Calendar.current.component(.weekday, from: first)
                    ForEach(0..<(firstWeekday - 1), id: \.self) { _ in Color.clear }
                }
                ForEach(days, id: \.self) { date in
                    let total = cachedExpenses[Calendar.current.startOfDay(for: date)] ?? 0
                    let isSelected = selectedDate != nil && Calendar.current.isDate(date, inSameDayAs: selectedDate!)
                    let isToday = Calendar.current.isDateInToday(date)
                    let isFuture = Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: Date())

                    VStack(spacing: 2) {
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.caption2)
                            .fontWeight(isToday ? .black : .bold)
                            .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : (isFuture ? Color.gray.opacity(0.3) : .primary))
                        if isToday {
                            Circle()
                                .fill(isSelected ? Color(uiColor: .systemBackground) : themeColor)
                                .frame(width: 4, height: 4)
                        } else {
                            Spacer().frame(height: 4)
                        }
                    }
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary)
                                .shadow(radius: 2)
                        } else if isFuture {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.gray.opacity(0.05))
                        } else if total > 0 {
                            if isBudgetEnabled && budgetAmount > 0 {
                                let dailyLimit = budgetAmount / 30.0
                                if total > dailyLimit * 1.5 {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.red.opacity(0.8))
                                } else {
                                    let intensity = min(sqrt(total / colorBenchmark), 1.0)
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(themeColor.opacity(0.15 + intensity * 0.85))
                                }
                            } else {
                                let intensity = min(sqrt(total / colorBenchmark), 1.0)
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(themeColor.opacity(0.15 + intensity * 0.85))
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.gray.opacity(0.05))
                        }
                    }
                    .onTapGesture {
                        if !isFuture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { selectedDate = date }
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24).fill(cardBackground).shadow(color: .black.opacity(0.03), radius: 15))
            .padding(.horizontal)
            .gesture(
                DragGesture().onEnded { value in
                    if value.translation.width < -50 { changeMonth(by: 1) }
                    else if value.translation.width > 50 { changeMonth(by: -1) }
                }
            )
        }
        .sheet(isPresented: $showMonthPicker) {
            InsightsMonthYearPicker(selection: $currentMonth, themeColor: themeColor, isPresented: $showMonthPicker)
        }
        .task(id: currentMonth) { await recalculateExpenses() }
        .task(id: expenses) { await recalculateExpenses() }
    }

    func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: currentMonth) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { currentMonth = newDate }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @MainActor func recalculateExpenses() async {
        let calendar = Calendar.current
        let filtered = expenses.filter { calendar.isDate($0.date, equalTo: currentMonth, toGranularity: .month) }
        var dict: [Date: Double] = [:]
        for exp in filtered { dict[calendar.startOfDay(for: exp.date), default: 0] += exp.amount }
        self.cachedExpenses = dict
    }
}

// MARK: - Day Detail View
struct DayDetailView: View {
    let date: Date?
    let expenses: [Expense]
    let themeColor: Color
    let cardBackground: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let date = date {
                HStack {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if expenses.isEmpty {
                        Text(L10n.noSpendDay)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(themeColor)
                    } else {
                        let total = expenses.reduce(0) { $0 + $1.amount }
                        Text("\(L10n.dailyTotal): \(total.formatted(.currency(code: L10n.currencyCode)))")
                            .font(.headline)
                            .bold()
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal)

                if !expenses.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(expenses) { expense in
                            HStack {
                                ZStack {
                                    Circle().fill(expense.color.opacity(0.15)).frame(width: 32, height: 32)
                                    Image(systemName: expense.icon).font(.caption).foregroundStyle(expense.color)
                                }
                                VStack(alignment: .leading) {
                                    Text(L10n.categoryName(expense.category)).font(.subheadline).bold()
                                    if !expense.note.isEmpty {
                                        Text(expense.note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(expense.amount.formatted(.currency(code: L10n.currencyCode)))
                                    .font(.subheadline)
                                    .bold()
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(cardBackground).shadow(color: .black.opacity(0.02), radius: 4))
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top, 10)
    }
}

// MARK: - Private Month Picker
struct InsightsMonthYearPicker: View {
    @Binding var selection: Date
    var themeColor: Color
    @Binding var isPresented: Bool
    @State private var displayYear: Int = 0

    var body: some View {
        VStack(spacing: 20) {
            HStack { Text("Select Month").font(.headline); Spacer() }
                .padding(.top, 24)
                .padding(.horizontal)

            HStack(spacing: 24) {
                Button(action: {
                    withAnimation { displayYear -= 1 }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }

                Text(String(displayYear).replacingOccurrences(of: ",", with: ""))
                    .font(.largeTitle.bold())
                    .frame(minWidth: 100)
                    .contentTransition(.numericText())

                Button(action: {
                    withAnimation { displayYear += 1 }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(.vertical, 10)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(1...12, id: \.self) { month in
                    let isSelected = isSelectedMonth(month)
                    let isCurrentRealMonth = isThisRealMonth(month)
                    Button(action: { selectMonth(month) }) {
                        Text(Calendar.current.shortMonthSymbols[month - 1])
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(isSelected ? themeColor : (isCurrentRealMonth ? themeColor.opacity(0.1) : Color.gray.opacity(0.05)))
                            .foregroundStyle(isSelected ? .white : (isCurrentRealMonth ? themeColor : .primary))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(themeColor, lineWidth: isCurrentRealMonth && !isSelected ? 2 : 0)
                            )
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .onAppear { displayYear = Calendar.current.component(.year, from: selection) }
    }

    private func isSelectedMonth(_ month: Int) -> Bool {
        let selYear = Calendar.current.component(.year, from: selection)
        let selMonth = Calendar.current.component(.month, from: selection)
        return selYear == displayYear && selMonth == month
    }

    private func isThisRealMonth(_ month: Int) -> Bool {
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let m = Calendar.current.component(.month, from: now)
        return year == displayYear && m == month
    }

    private func selectMonth(_ month: Int) {
        var components = DateComponents()
        components.year = displayYear
        components.month = month
        components.day = 1
        if let newDate = Calendar.current.date(from: components) {
            withAnimation { selection = newDate }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            isPresented = false
        }
    }
}

