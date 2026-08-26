import SwiftUI
import SwiftData
import Charts

// MARK: - Spending Trend Chart
struct SpendingTrendChart: View {
    let expenses: [Expense]
    let timeRange: InsightTimeRange // 关键：使用新的枚举类型
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
        switch timeRange {
        case .thisMonth, .lastMonth, .customMonth: return .day
        default: return .month
        }
    }

    private func isDateSelected(_ date: Date) -> Bool {
        guard let sel = selectedDate else { return false }
        return Calendar.current.isDate(date, equalTo: sel, toGranularity: currentGranularity)
    }

    var dateLabel: String { timeRange.displayName }

    var trendData: [TrendPoint] {
        let calendar = Calendar.current
        let granularity = currentGranularity
        
        // 显式定义闭包类型，防止编译器超时
        let grouper: (Expense) -> Date = { expense in
            if granularity == .month {
                let components = calendar.dateComponents([.year, .month], from: expense.date)
                return calendar.date(from: components) ?? expense.date
            } else {
                return calendar.startOfDay(for: expense.date)
            }
        }
        
        let grouped = Dictionary(grouping: expenses, by: grouper)
        let sortedKeys = grouped.keys.sorted()
        
        var points: [TrendPoint] = []
        
        if let first = sortedKeys.first, let last = sortedKeys.last {
            var current = first
            while current <= last {
                let total = grouped[current]?.reduce(0) { $0 + $1.normalizedAmount } ?? 0
                points.append(TrendPoint(date: current, amount: total))
                if let next = calendar.date(byAdding: granularity, value: 1, to: current) {
                    current = next
                } else { break }
            }
        }
        return points
    }

    var xAxisStride: (component: Calendar.Component, count: Int) {
        let count = trendData.count
        if currentGranularity == .month {
            if count > 48 { return (.year, 1) }
            if count > 24 { return (.month, 6) }
            if count > 12 { return (.month, 3) }
            if count > 6 { return (.month, 2) }
            return (.month, 1)
        } else {
            if count > 20 { return (.day, 7) }
            if count > 10 { return (.day, 3) }
            return (.day, 1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.xyaxis.line").foregroundStyle(themeColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.isZh ? "消费趋势" : "Spending Trend").font(.headline)
                    Text(dateLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let amount = selectedAmount, let date = selectedDate {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(amount.formatted(.currency(code: L10n.currencyCode))).font(.headline).foregroundStyle(themeColor)
                        Text(date.formatted(
                            currentGranularity == .month
                            ? .dateTime.month(.wide).year()
                            : .dateTime.month(.abbreviated).day()
                        ))
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            if trendData.isEmpty {
                ContentUnavailableView("No enough data", systemImage: "chart.xyaxis.line").frame(height: 200)
            } else {
                Chart {
                    ForEach(trendData) { item in
                        AreaMark(x: .value("Date", item.date, unit: currentGranularity), y: .value("Amount", item.amount))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(colors: [themeColor.opacity(0.3), themeColor.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", item.date, unit: currentGranularity), y: .value("Amount", item.amount))
                            .interpolationMethod(.catmullRom).foregroundStyle(themeColor).lineStyle(StrokeStyle(lineWidth: 3))
                        if isDateSelected(item.date) {
                            PointMark(x: .value("Date", item.date, unit: currentGranularity), y: .value("Amount", item.amount))
                                .foregroundStyle(themeColor).symbolSize(100)
                        }
                    }
                }
                .frame(height: 220)
                .chartXSelection(value: $selectedDate)
                .onChange(of: selectedDate) { _, newValue in
                    if let date = newValue {
                        if let match = trendData.first(where: { Calendar.current.isDate($0.date, equalTo: date, toGranularity: currentGranularity) }) {
                            selectedAmount = match.amount; UISelectionFeedbackGenerator().selectionChanged()
                        } else { selectedAmount = nil }
                    } else { selectedAmount = nil }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: xAxisStride.component, count: xAxisStride.count)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(formatAxisLabel(date: date))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Color.gray.opacity(0.1)); AxisValueLabel() } }
                .accessibilityLabel(L10n.isZh
                    ? "\(dateLabel)消费趋势，共 \(trendData.count) 个数据点"
                    : "Spending trend for \(dateLabel), \(trendData.count) data points")
                .accessibilityHint(L10n.isZh
                    ? "拖动图表以查看每个日期的消费金额。"
                    : "Drag across the chart to inspect spending for each date.")
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 24).fill(cardBackground).shadow(color: .black.opacity(0.03), radius: 15))
        .padding(.horizontal)
    }
    
    private func formatAxisLabel(date: Date) -> String {
        if currentGranularity == .month {
            if xAxisStride.component == .year { return date.formatted(.dateTime.year()) }
            if timeRange == .thisYear { return date.formatted(.dateTime.month(.abbreviated)) }
            return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        } else {
            return date.formatted(.dateTime.day())
        }
    }
}

// MARK: - Interactive Pie Chart
struct InteractivePieChart: View {
    let expenses: [Expense]
    let categoryBudgets: [CategoryBudget]
    let isBudgetEnabled: Bool
    let selectedRange: InsightTimeRange // 关键：使用新类型
    @Binding var selectedCategoryName: String?
    let themeColor: Color
    let cardBackground: Color

    var totalAmount: Double { expenses.reduce(0) { $0 + $1.normalizedAmount } }

    var categoryStats: [(name: String, displayName: String, total: Double, color: Color)] {
        let grouped = Dictionary(grouping: expenses, by: { $0.category })
        return grouped.map { (key, value) in
            let total = value.reduce(0) { $0 + $1.normalizedAmount }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(themeColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.spendingBreakdown).font(.headline)
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
                .accessibilityLabel(selectedCategoryName.flatMap { selectedName in
                    categoryStats.first(where: { $0.name == selectedName })
                }.map { item in
                    L10n.isZh
                        ? "消费构成，已选择\(item.displayName)，\(item.total.formatted(.currency(code: L10n.currencyCode)))"
                        : "Spending breakdown, selected \(item.displayName), \(item.total.formatted(.currency(code: L10n.currencyCode)))"
                } ?? (L10n.isZh
                    ? "消费构成，总计\(totalAmount.formatted(.currency(code: L10n.currencyCode)))"
                    : "Spending breakdown, total \(totalAmount.formatted(.currency(code: L10n.currencyCode)))"))
                .accessibilityHint(L10n.isZh
                    ? "轻点图表中的分类以查看金额。"
                    : "Tap a category in the chart to view its amount.")

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
