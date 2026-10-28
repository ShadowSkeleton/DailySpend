import SwiftUI
import SwiftData

// MARK: - Custom Tab Switcher
struct CustomTabSwitcher: View {
    @Binding var selectedTab: InsightTab
    var themeColor: Color

    var body: some View {
        Picker("Insights view", selection: $selectedTab) {
            ForEach(InsightTab.allCases) { tab in
                Text(tab.displayName).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .tint(themeColor)
        .accessibilityIdentifier("insights-view-picker")
    }
}

// MARK: - Glance

/// The top of Insights, on both tabs: this month at a glance, read as one
/// sentence. "October so far: $3,219 less (green) than this time last month",
/// then what you've spent and what moved. The full summary is one tap away
/// under Details. Without a fair comparison it shows the total.
struct InsightsGlanceCard: View {
    let expenses: [Expense]
    let budget: Money?
    let themeColor: Color

    @State private var showInfo = false
    @State private var wording: RecapWording?
    @State private var isWriting = false
    @State private var showsDetails = false

    var body: some View {
        let period = SpendingPeriod.monthToDate(now: Date())
        if let recap = PeriodRecap.make(records: expenses.map(\.spendingRecord), period: period, budget: budget) {
            let facts = RecapText.facts(for: recap)
            // Words written for other facts are never shown.
            let shown = wording.flatMap { $0.factsSignature == RecapWording.signature(for: facts) ? $0 : nil }
            card {
                headline(recap)
                if recap.previousTotal == nil {
                    Label(L10n.isZh ? "满一个月后，这里会显示与上月的对比。"
                                    : "After your first full month, you'll see how each month compares here.",
                          systemImage: "calendar")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("insights-first-month")
                }
                details(recap, facts: facts, wording: shown)
            }
            .alert(L10n.isZh ? "统计逻辑" : "Calculation Logic", isPresented: $showInfo) {
                Button(L10n.ok, role: .cancel) { }
            } message: {
                Text(RecapText.comparisonExplanation(period))
            }
            .task(id: facts.joined(separator: "\n")) { await loadWording(for: recap, facts: facts) }
        } else if !expenses.isEmpty {
            // History, but nothing yet this month.
            card {
                Text(RecapText.title(for: period)).font(.headline).foregroundStyle(.secondary)
                Text(RecapText.wholeMoney(.zero))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(themeColor)
                Text(L10n.isZh ? "本月还没有支出" : "No spending yet this month")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("insights-glance")
    }

    // MARK: The big number

    @ViewBuilder
    private func headline(_ recap: PeriodRecap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(RecapText.title(for: recap.period))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if recap.previousTotal != nil {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showInfo = true
                    } label: {
                        Image(systemName: "questionmark.circle").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(L10n.isZh ? "统计逻辑" : "How this is calculated")
                }
            }
            let headline = RecapText.headline(for: recap)
            Text(headline.text)
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundStyle(headline.tone == .up ? Color.red : headline.tone == .down ? Color.green : themeColor)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityIdentifier("insights-headline")
            Text(RecapText.headlineCaption(for: recap))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // One idea per line, so an amount never wraps away from its words.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(RecapText.quickLines(for: recap), id: \.self) { line in
                    Text(line)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("insights-quick-line")
        }
    }

    // MARK: Details

    private func details(_ recap: PeriodRecap, facts: [String], wording: RecapWording?) -> some View {
        DisclosureGroup(isExpanded: $showsDetails) {
            VStack(alignment: .leading, spacing: 14) {
                Text(wording?.paragraph(for: recap) ?? RecapText.summary(for: recap))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("insights-summary-text")
                if isWriting {
                    Label(L10n.isZh ? "正在撰写小结…" : "Writing your summary…", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(themeColor)
                        .symbolEffect(.pulse, options: .repeating)
                }
                // The key numbers at a glance; the graph below has the rest.
                HStack(spacing: 8) {
                    ForEach(RecapText.tiles(for: recap), id: \.label) { tile in
                        DetailTile(tile: tile)
                    }
                }
                if recap.laterThisMonth > .zero {
                    Text(L10n.isZh ? "另有 \(RecapText.money(recap.laterThisMonth)) 记在本月稍后日期，到那天才计入。"
                                   : "Plus \(RecapText.money(recap.laterThisMonth)) dated later this month, counted once that day comes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if wording?.isFromModel == true {
                    Text(L10n.isZh ? "最后一句由 Apple 智能在本机撰写，可能出错。"
                                   : "The last sentence was written on this device by Apple Intelligence. AI can make mistakes.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(L10n.isZh ? "详情" : "Details")
                .font(.subheadline.weight(.semibold))
        }
        .tint(themeColor)
    }

    /// The saved wording when the facts are unchanged; otherwise the code's
    /// words at once, then the model's once written.
    private func loadWording(for recap: PeriodRecap, facts: [String]) async {
        if let cached = RecapWording.cached(for: recap, facts: facts) {
            wording = cached
            return
        }
        isWriting = ReceiptIntelligenceStatus.current == .ready
        let made = await RecapWording.make(for: recap, facts: facts)
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut) {
            wording = made
            isWriting = false
        }
        made.store(for: recap)
    }
}

/// One key number under Details: a small label over its value.
private struct DetailTile: View {
    let tile: RecapText.Tile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(tile.value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tile.tone == .up ? Color.red : tile.tone == .down ? Color.green : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
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
            let total = value.reduce(0) { $0 + $1.normalizedAmount }
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
        guard let budget = categoryBudgets.first(where: { $0.category == item.name }), budget.normalizedAmount > 0 else { return nil }
        return budget.normalizedAmount
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
                        if item.total > budget { Text((L10n.isZh ? "超出：" : "Over: ") + (item.total - budget).formatted(.currency(code: L10n.currencyCode))).font(.caption2).foregroundStyle(.red) }
                        else { Text((L10n.isZh ? "预算：" : "Budget: ") + budget.formatted(.currency(code: L10n.currencyCode))).font(.caption2).foregroundStyle(.secondary) }
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
                                Text(expense.notePreview.isEmpty ? item.displayName : expense.notePreview).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                if let freq = expense.frequency, freq != .none {
                                    HStack(spacing: 2) { Image(systemName: "repeat").font(.caption2); Text(L10n.isZh ? "定期" : "Recurring").font(.caption2) }.foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(expense.normalizedAmount.formatted(.currency(code: L10n.currencyCode))).font(.subheadline).fontWeight(.medium).foregroundStyle(item.color).fixedSize()
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
