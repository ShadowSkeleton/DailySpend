import SwiftUI
import SwiftData

// MARK: - Home View
struct HomeView: View {
    let themeColor: Color
    let backgroundColor = Color(uiColor: .systemGroupedBackground)
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query private var categoryBudgets: [CategoryBudget]
    
    @State private var showingAddSheet = false
    @State private var expenseToEdit: Expense?
    @State private var homeSelectedMonth = Date()
    
    @AppStorage("isBudgetEnabled") private var isBudgetEnabled = false
    @AppStorage("budgetAmount") private var budgetAmount = 0.0
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()
                List {
                    // MARK: - Header Section
                    Section {
                        HomeHeaderView(
                            currentMonth: $homeSelectedMonth,
                            total: currentMonthTotal,
                            themeColor: themeColor,
                            isBudgetEnabled: isBudgetEnabled,
                            budgetAmount: budgetAmount,
                            categoryBudgets: categoryBudgets,
                            monthlyExpenses: filteredExpenses
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .id("Header-\(homeSelectedMonth.timeIntervalSince1970)")
                    }
                    
                    // MARK: - Transaction List Section
                    if filteredExpenses.isEmpty {
                        ContentUnavailableView(
                            L10n.noExpensesTitle,
                            systemImage: "creditcard.and.123",
                            description: Text(L10n.noExpensesDesc)
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.top, 40)
                    } else {
                        Section(header:
                            HStack {
                                Text(L10n.recentTransactions)
                                Spacer()
                                Text(homeSelectedMonth.formatted(.dateTime.month().year()))
                                    .font(.caption)
                                    .textCase(nil)
                            }
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        ) {
                            ForEach(filteredExpenses) { expense in
                                ExpenseRowCard(expense: expense)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                                    .cornerRadius(12)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) { deleteItem(expense) } label: { Label(L10n.deleteTransaction, systemImage: "trash") }
                                    }
                                    .onTapGesture { expenseToEdit = expense }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("DailySpend")
            .toolbarBackground(backgroundColor, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: generateCSV(), preview: SharePreview("DailySpend Data.csv", image: Image(systemName: "tablecells"))) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 17)).foregroundStyle(themeColor)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(themeColor)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) { AddExpenseView(themeColor: themeColor) }
            .sheet(item: $expenseToEdit) { expense in EditExpenseView(expense: expense, themeColor: themeColor) }
        }
        .onOpenURL { url in
            if url.scheme == "loveledger" && url.host == "add" { showingAddSheet = true }
        }
    }
    
    var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        return expenses.filter { calendar.isDate($0.date, equalTo: homeSelectedMonth, toGranularity: .month) }
    }
    
    var currentMonthTotal: Double {
        filteredExpenses.reduce(0) { $0 + $1.amount }
    }
    
    private func deleteItem(_ expense: Expense) { withAnimation { modelContext.delete(expense) } }
    
    private func generateCSV() -> CSVDocument {
        var csvString = "Date,Category,Amount,Note\n"
        let dateFormatter = DateFormatter(); dateFormatter.dateStyle = .short; dateFormatter.timeStyle = .short
        for expense in filteredExpenses {
            var safeNote = expense.note.replacingOccurrences(of: "\"", with: "\"\"")
            safeNote = "\"\(safeNote)\""
            csvString.append("\(dateFormatter.string(from: expense.date)),\(L10n.categoryName(expense.category)),\(expense.amount),\(safeNote)\n")
        }
        return CSVDocument(text: csvString)
    }
}

// MARK: - Home Header View (UI Optimized)
struct HomeHeaderView: View {
    @Binding var currentMonth: Date
    let total: Double
    let themeColor: Color
    var isBudgetEnabled: Bool = false
    var budgetAmount: Double = 0
    
    var categoryBudgets: [CategoryBudget] = []
    var monthlyExpenses: [Expense] = []
    
    @State private var showMonthPicker = false
    let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    
    var isRealCurrentMonth: Bool {
        Calendar.current.isDate(currentMonth, equalTo: Date(), toGranularity: .month)
    }
    
    var overBudgetItems: [(category: String, overAmount: Double)] {
        guard isBudgetEnabled else { return [] }
        var items: [(String, Double)] = []
        let expensesByCategory = Dictionary(grouping: monthlyExpenses, by: { $0.category })
        for budget in categoryBudgets {
            let spent = expensesByCategory[budget.category]?.reduce(0) { $0 + $1.amount } ?? 0
            if spent > budget.amount {
                items.append((budget.category, spent - budget.amount))
            }
        }
        return items.sorted { $0.1 > $1.1 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Part A: 手势区域 (切换月份)
            VStack(alignment: .leading, spacing: 12) {
                // 顶部栏
                HStack {
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        showMonthPicker = true
                    }) {
                        HStack(spacing: 6) {
                            Text(monthTitle)
                                .font(.title3).fontWeight(.bold)
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(themeColor.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if !isRealCurrentMonth {
                        Button(action: {
                            withAnimation(.spring()) { currentMonth = Date() }
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                Text("Today")
                            }
                            .font(.caption).fontWeight(.bold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(themeColor.opacity(0.1))
                            .foregroundStyle(themeColor)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.bottom, 4)
                
                // 金额显示
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(L10n.currencySymbol)
                        .roundedNumFont(size: 32, weight: .bold)
                        .foregroundStyle(themeColor)
                    Text(total.formatted(.number.precision(.fractionLength(2))))
                        .roundedNumFont(size: 52, weight: .heavy)
                        .contentTransition(.numericText())
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                
                // 总预算进度条
                if isBudgetEnabled {
                    if budgetAmount > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.gray.opacity(0.1))
                                    Capsule().fill(progressColor).frame(width: min(geo.size.width * progress, geo.size.width))
                                }
                            }.frame(height: 8)
                            HStack {
                                if isOverBudget {
                                    Text("\(L10n.overBudget): \(overAmount.formatted(.currency(code: L10n.currencyCode)))")
                                        .font(.subheadline).fontWeight(.bold).foregroundStyle(.red)
                                } else {
                                    Text("\(L10n.remaining): \(remainingAmount.formatted(.currency(code: L10n.currencyCode)))")
                                        .font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(String(format: "%.0f", progress * 100))%")
                                    .font(.caption2).bold().foregroundStyle(progressColor)
                            }
                        }
                        .padding(.top, 4)
                    } else {
                        Text(L10n.budgetRequired).font(.caption).foregroundStyle(.red).padding(.top, 4)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.width < -50 { changeMonth(by: 1) }
                        else if value.translation.width > 50 { changeMonth(by: -1) }
                    }
            )
            
            // ✨ Part B: 分类超支胶囊 (独立滚动区)
            if isBudgetEnabled && budgetAmount > 0 && !overBudgetItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(overBudgetItems, id: \.category) { item in
                            HStack(spacing: 6) {
                                if let icon = Expense.categories.first(where: {$0.name == item.category})?.icon {
                                    Image(systemName: icon).font(.caption2)
                                }
                                Text(L10n.categoryName(item.category))
                                    .font(.caption).fontWeight(.bold)
                                Text("-\(item.overAmount.formatted(.currency(code: L10n.currencyCode)))")
                                    .font(.caption).fontWeight(.heavy)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(Color.red)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.red.opacity(0.2), lineWidth: 1))
                            .onTapGesture { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                        }
                    }
                    // 内边距对齐
                    .padding(.horizontal, 24)
                    .scrollTargetLayout()
                }
                // 容器外扩
                .padding(.horizontal, -24)
                
                // ✨ Mask 优化：左侧完全展示，只有右侧淡出
                .mask(
                    HStack(spacing: 0) {
                        // 左侧实色 (完全不透明)
                        Rectangle().fill(Color.black)
                        
                        // 右侧渐变 (黑 -> 透明)
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 24)
                    }
                )
                .scrollTargetBehavior(.viewAligned)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.03), radius: 15, x: 0, y: 5)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        
        .sheet(isPresented: $showMonthPicker) {
            MonthYearPicker(selection: $currentMonth, themeColor: themeColor, isPresented: $showMonthPicker)
        }
    }
    
    func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: currentMonth) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentMonth = newDate
            }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
    
    var monthTitle: String {
        let now = Date()
        let isSameYear = Calendar.current.component(.year, from: currentMonth) == Calendar.current.component(.year, from: now)
        if isSameYear && isRealCurrentMonth { return L10n.thisMonth } else { return currentMonth.formatted(.dateTime.month(.wide).year()) }
    }
    
    var remainingAmount: Double { budgetAmount - total }
    var overAmount: Double { total - budgetAmount }
    var progress: Double { total / max(budgetAmount, 1) }
    var isOverBudget: Bool { total > budgetAmount }
    var progressColor: Color { if progress > 1.0 { return .red }; if progress > 0.8 { return .orange }; return themeColor }
}

// MARK: - Custom Month Picker Component
struct MonthYearPicker: View {
    @Binding var selection: Date
    var themeColor: Color
    @Binding var isPresented: Bool
    @State private var displayYear: Int = 0
    
    var body: some View {
        VStack(spacing: 20) {
            HStack { Text("Select Month").font(.headline); Spacer() }.padding(.top, 24).padding(.horizontal)
            HStack(spacing: 24) {
                Button(action: { withAnimation { displayYear -= 1 }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }) { Image(systemName: "chevron.left").font(.title3.bold()).foregroundStyle(.secondary).padding(10).background(Color.gray.opacity(0.1)).clipShape(Circle()) }
                Text(String(displayYear).replacingOccurrences(of: ",", with: "")).font(.largeTitle.bold()).frame(minWidth: 100).contentTransition(.numericText())
                Button(action: { withAnimation { displayYear += 1 }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }) { Image(systemName: "chevron.right").font(.title3.bold()).foregroundStyle(.secondary).padding(10).background(Color.gray.opacity(0.1)).clipShape(Circle()) }
            }.padding(.vertical, 10)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(1...12, id: \.self) { month in
                    let isSelected = isSelectedMonth(month); let isCurrentRealMonth = isThisRealMonth(month)
                    Button(action: { selectMonth(month) }) {
                        Text(Calendar.current.shortMonthSymbols[month - 1]).font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                            .background(isSelected ? themeColor : (isCurrentRealMonth ? themeColor.opacity(0.1) : Color.gray.opacity(0.05)))
                            .foregroundStyle(isSelected ? .white : (isCurrentRealMonth ? themeColor : .primary))
                            .cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(themeColor, lineWidth: isCurrentRealMonth && !isSelected ? 2 : 0))
                    }
                }
            }.padding(.horizontal)
            Spacer()
        }.presentationDetents([.height(400)]).presentationDragIndicator(.visible).onAppear { displayYear = Calendar.current.component(.year, from: selection) }
    }
    private func isSelectedMonth(_ month: Int) -> Bool { let selYear = Calendar.current.component(.year, from: selection); let selMonth = Calendar.current.component(.month, from: selection); return selYear == displayYear && selMonth == month }
    private func isThisRealMonth(_ month: Int) -> Bool { let now = Date(); let year = Calendar.current.component(.year, from: now); let m = Calendar.current.component(.month, from: now); return year == displayYear && m == month }
    private func selectMonth(_ month: Int) { var components = DateComponents(); components.year = displayYear; components.month = month; components.day = 1; if let newDate = Calendar.current.date(from: components) { withAnimation { selection = newDate }; UIImpactFeedbackGenerator(style: .medium).impactOccurred(); isPresented = false } }
}
