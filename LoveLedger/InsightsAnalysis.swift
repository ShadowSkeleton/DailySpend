import SwiftUI
import SwiftData

// MARK: - Custom Tab Switcher
struct CustomTabSwitcher: View {
    @Binding var selectedTab: InsightTab
    var themeColor: Color
    @Namespace private var animationNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(InsightTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = tab }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(tab.displayName).font(.headline).fontWeight(selectedTab == tab ? .bold : .medium)
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 12).fill(themeColor).matchedGeometryEffect(id: "TabBackground", in: animationNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4).background(Color(uiColor: .tertiarySystemGroupedBackground)).cornerRadius(16)
    }
}

// MARK: - Insight Analysis Card
struct InsightAnalysisCard: View {
    let expenses: [Expense]
    @State private var showInfo = false

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

    func explanationText(data: (diff: Double, driver: String, driverAmount: Double, isUp: Bool)) -> Text {
        let categoryName = L10n.categoryName(data.driver)
        let amountStr = (data.driverAmount > 0 ? "+" : "") + data.driverAmount.formatted(.currency(code: L10n.currencyCode))
        if L10n.isZh { return Text("主要因为 \(categoryName) 支出的变化 (\(amountStr))").fontWeight(.bold) }
        else { return Text("Mainly due to \(categoryName) spending (\(amountStr))").fontWeight(.bold) }
    }

    var body: some View {
        if let data = analysis {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.isZh ? "月度支出摘要" : "Spending Summary").font(.headline).foregroundStyle(.secondary)
                    Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); showInfo = true }) {
                        Image(systemName: "questionmark.circle").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: data.isUp ? "arrow.up" : "arrow.down")
                        Text(L10n.isZh ? "对比上月同期" : "vs Same Period")
                    }
                    .font(.caption).fontWeight(.bold).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(data.isUp ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    .foregroundStyle(data.isUp ? .red : .green).clipShape(Capsule())
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(abs(data.diff).formatted(.currency(code: L10n.currencyCode)))
                        .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Color.primary)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text(data.isUp ? (L10n.isZh ? "增加" : "More") : (L10n.isZh ? "减少" : "Less"))
                        .font(.headline).fontWeight(.semibold).foregroundStyle(data.isUp ? .red : .green)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill").font(.subheadline).foregroundStyle(.secondary).padding(.top, 2)
                    explanationText(data: data).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .padding(20).background(Color(uiColor: .secondarySystemGroupedBackground)).cornerRadius(20)
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6).padding(.horizontal)
            .alert(L10n.isZh ? "统计逻辑" : "Calculation Logic", isPresented: $showInfo) { Button(L10n.ok, role: .cancel) { } } message: {
                Text(L10n.isZh ? "此数据对比的是【本月1号至今】与【上月1号至同日】的支出总额（MTD 同期对比）。" : "This compares your spending from the start of this month to today, against the start of last month to the same day (Month-to-Date).")
            }
        }
    }
}

// MARK: - Ranking List Component
struct RankingList: View {
    let expenses: [Expense]
    let categoryBudgets: [CategoryBudget]
    let isBudgetEnabled: Bool
    let selectedRange: InsightTimeRange // 关键：新类型
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.number").foregroundStyle(.blue)
                Text(L10n.topSpending).font(.headline).foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            VStack(spacing: 12) {
                ForEach(categoryStats, id: \.name) { item in
                    CategoryRankingRow(
                        item: item,
                        expenses: expenses,
                        categoryBudgets: categoryBudgets,
                        isBudgetEnabled: isBudgetEnabled,
                        selectedRange: selectedRange,
                        isSelected: selectedCategoryName == item.name,
                        cardBackground: cardBackground,
                        onTap: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                selectedCategoryName = (selectedCategoryName == item.name) ? nil : item.name
                            }
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    )
                }
            }.padding(.horizontal)
        }
    }
}

// MARK: - Independent Ranking Row
struct CategoryRankingRow: View {
    let item: (name: String, displayName: String, total: Double, color: Color)
    let expenses: [Expense]
    let categoryBudgets: [CategoryBudget]
    let isBudgetEnabled: Bool
    let selectedRange: InsightTimeRange // 关键：新类型
    let isSelected: Bool
    let cardBackground: Color
    let onTap: () -> Void
    
    var transactions: [Expense] {
        if !isSelected { return [] }
        let filtered = expenses.filter { $0.category == item.name }.sorted { $0.date > $1.date }
        if filtered.isEmpty { return [] }
        let maxDate = filtered.first!.date
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -2, to: maxDate) else { return filtered }
        return filtered.filter { $0.date >= startDate && $0.date <= maxDate }
    }
    
    var budgetLimit: Double? {
        guard let budget = categoryBudgets.first(where: { $0.category == item.name }), budget.amount > 0 else { return nil }
        return budget.amount
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(item.color).frame(width: 12, height: 12)
                Text(item.displayName).fontWeight(.medium).foregroundStyle(.primary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.total.formatted(.currency(code: L10n.currencyCode))).roundedNumFont(size: 16, weight: .semibold).foregroundStyle(.primary)
                    if isSelected { Text("\(transactions.count) transactions").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .padding(16).contentShape(Rectangle()).onTapGesture { onTap() }
            
            // 预算条 (仅在本月显示)
            if isBudgetEnabled, let budget = budgetLimit, selectedRange == .thisMonth {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.1))
                            Capsule().fill(item.total > budget ? Color.red : item.color)
                                .frame(width: min(geo.size.width * (item.total / budget), geo.size.width))
                        }
                    }.frame(height: 4)
                    HStack {
                        if item.total > budget { Text("Over: \((item.total - budget).formatted(.currency(code: L10n.currencyCode)))").font(.caption2).foregroundStyle(.red) }
                        else { Text("Budget: \(budget.formatted(.currency(code: L10n.currencyCode)))").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 12).onTapGesture { onTap() }
            }
            
            if isSelected {
                Divider().padding(.horizontal, 16).opacity(0.5)
                LazyVStack(spacing: 0) {
                    ForEach(transactions, id: \.id) { expense in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .center, spacing: 0) {
                                Text(expense.date.formatted(.dateTime.day())).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.primary)
                                Text(expense.date.formatted(.dateTime.month(.abbreviated))).font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
                            }
                            .frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(expense.note.isEmpty ? item.displayName : expense.note).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                if let freq = expense.frequency, freq != .none {
                                    HStack(spacing: 2) { Image(systemName: "repeat").font(.caption2); Text("Recurring").font(.caption2) }.foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(expense.amount.formatted(.currency(code: L10n.currencyCode))).font(.subheadline).fontWeight(.medium).foregroundStyle(item.color)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12).background(Color.gray.opacity(0.03))
                        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.gray.opacity(0.1)), alignment: .bottom)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity)).zIndex(-1)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(isSelected ? item.color.opacity(0.05) : cardBackground).shadow(color: .black.opacity(0.02), radius: 5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
