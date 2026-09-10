import SwiftUI
import SwiftData

// MARK: - Home View
struct HomeView: View {
    let themeColor: Color
    var onOpenSplitBill: () -> Void = { }
    @Binding var pendingQuickAdd: Bool
    var canOpenQuickAdd: Bool
    let backgroundColor = Color(uiColor: .systemGroupedBackground)
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query private var categoryBudgets: [CategoryBudget]
    
    private enum ExpenseSheet: Identifiable {
        case add
        case edit(Expense)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let expense): "edit-\(expense.id)"
            }
        }
    }
    @State private var expenseSheet: ExpenseSheet?
    @State private var homeSelectedMonth = Date()
    @State private var expensePendingDeletion: Expense?
    @State private var showDeleteConfirmation = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    
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
                        HomeEmptyState(
                            onAddExpense: { expenseSheet = .add },
                            onOpenSplitBill: onOpenSplitBill
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.top, 28)
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
                                Button {
                                    guard expenseSheet == nil else { return }
                                    expenseSheet = .edit(expense)
                                } label: {
                                    ExpenseRowCard(expense: expense)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("transaction-\(expense.id)")
                                .accessibilityHint(L10n.isZh ? "编辑这笔支出" : "Edit this expense")
                                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                                    .cornerRadius(12)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            expensePendingDeletion = expense
                                            showDeleteConfirmation = true
                                        } label: { Label(L10n.deleteTransaction, systemImage: "trash") }
                                        .tint(.red)
                                    }
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
                if !filteredExpenses.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: generateCSV(), preview: SharePreview("DailySpend Data.csv", image: Image(systemName: "tablecells"))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(L10n.isZh ? "导出账单" : "Export expenses")
                        .accessibilityHint(L10n.isZh ? "导出当前月份的账单 CSV 文件" : "Exports this month's expenses as a CSV file.")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { expenseSheet = .add }) {
                        Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(themeColor)
                    }
                    .accessibilityLabel(L10n.isZh ? "添加账单" : "Add expense")
                    .accessibilityHint(L10n.isZh ? "记录一笔新支出或扫描收据" : "Record a new expense or scan a receipt.")
                }
            }
            .sheet(item: $expenseSheet, onDismiss: openPendingQuickAdd) { sheet in
                switch sheet {
                case .add:
                    AddExpenseView(themeColor: themeColor)
                case .edit(let expense):
                    EditExpenseView(expense: expense, themeColor: themeColor)
                }
            }
            .alert("Delete this expense?", isPresented: $showDeleteConfirmation) {
                Button(L10n.cancel, role: .cancel) { expensePendingDeletion = nil }
                Button(L10n.deleteTransaction, role: .destructive) { deletePendingExpense() }
            } message: {
                Text("You can restore it later only if it exists in an iCloud or JSON backup.")
            }
            .alert("Couldn’t Delete Expense", isPresented: $showDeleteError) {
                Button(L10n.ok, role: .cancel) { }
            } message: {
                Text(deleteErrorMessage)
            }
        }
        .onAppear { openPendingQuickAdd() }
        .onChange(of: pendingQuickAdd) { _, _ in openPendingQuickAdd() }
        .onChange(of: canOpenQuickAdd) { _, _ in openPendingQuickAdd() }
    }

    private func openPendingQuickAdd() {
        // Wait for onDismiss, not merely the selection becoming nil: the
        // outgoing sheet must finish dismissing before a queued Add opens.
        guard pendingQuickAdd, canOpenQuickAdd else { return }
        if case .add? = expenseSheet {
            // Repeated widget taps already have their destination open.
            pendingQuickAdd = false
            return
        }
        guard expenseSheet == nil else { return }
        expenseSheet = .add
        pendingQuickAdd = false
    }
    
    var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        return expenses.filter { calendar.isDate($0.date, equalTo: homeSelectedMonth, toGranularity: .month) }
    }
    
    var currentMonthTotal: Double {
        filteredExpenses.reduce(0) { $0 + $1.normalizedAmount }
    }
    
    private func deletePendingExpense() {
        guard let expense = expensePendingDeletion else { return }
        do {
            modelContext.delete(expense)
            try modelContext.save()
            expensePendingDeletion = nil
        } catch {
            modelContext.rollback()
            deleteErrorMessage = error.localizedDescription
            showDeleteError = true
        }
    }
    
    private func generateCSV() -> CSVDocument {
        var csvString = CSVDocument.row(["Date", "Category", "Amount", "Note"])
        let dateFormatter = ISO8601DateFormatter()
        for expense in filteredExpenses {
            csvString.append(CSVDocument.row([
                dateFormatter.string(from: expense.date), L10n.categoryName(expense.category),
                String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), expense.normalizedAmount),
                expense.note
            ]))
        }
        return CSVDocument(text: csvString)
    }
}

// MARK: - First-use path
private struct HomeEmptyState: View {
    let onAddExpense: () -> Void
    let onOpenSplitBill: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ContentUnavailableView(
                L10n.noExpensesTitle,
                systemImage: "creditcard.and.123",
                description: Text(L10n.isZh
                    ? "添加支出、扫描收据，或和朋友轻松分账。"
                    : "Add an expense, scan a receipt, or settle a bill with friends.")
            )

            VStack(spacing: 10) {
                Button(action: onAddExpense) {
                    Label(L10n.isZh ? "记录第一笔支出" : "Add your first expense", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("add-first-expense")

                Button(action: onOpenSplitBill) {
                    Label(L10n.isZh ? "发起分账" : "Start a Split Bill", systemImage: "person.2.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("start-split-bill")
            }
            .frame(maxWidth: 280)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
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
            let spent = expensesByCategory[budget.category]?.reduce(0) { $0 + $1.normalizedAmount } ?? 0
            if spent > budget.normalizedAmount {
                items.append((budget.category, spent - budget.normalizedAmount))
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
                        .roundedNumFont(size: 48, weight: .heavy)
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
            // Let the List keep its native vertical scroll while supporting a
            // deliberate horizontal month change on the summary card.
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width < -50 {
                            // 左滑 (前往下个月)
                            changeMonth(by: 1)
                        }
                        else if value.translation.width > 50 {
                            // 右滑 (前往上个月)
                            changeMonth(by: -1)
                        }
                    }
            )
            
            // Part B: 分类超支胶囊 (独立滚动区)
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
                        }
                    }
                    .padding(.horizontal, 24)
                    .scrollTargetLayout()
                }
                .padding(.horizontal, -24)
                .mask(
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.black)
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
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                changeMonth(by: 1)
            case .decrement:
                changeMonth(by: -1)
            @unknown default:
                break
            }
        }
        
        .sheet(isPresented: $showMonthPicker) {
            MonthYearPicker(selection: $currentMonth, themeColor: themeColor, isPresented: $showMonthPicker)
        }
    }
    
    // ✨ 核心修改：月份切换逻辑
    func changeMonth(by value: Int) {
        let calendar = Calendar.current
        
        // 1. 计算目标日期
        guard let newDate = calendar.date(byAdding: .month, value: value, to: currentMonth) else { return }
        
        // 2. 检查未来限制：如果目标月份晚于当前真实月份，则禁止跳转
        let now = Date()
        let targetComponents = calendar.dateComponents([.year, .month], from: newDate)
        let currentComponents = calendar.dateComponents([.year, .month], from: now)
        
        if let tYear = targetComponents.year, let tMonth = targetComponents.month,
           let cYear = currentComponents.year, let cMonth = currentComponents.month {
            
            // 如果年份更大，或者年份相同但月份更大
            if tYear > cYear || (tYear == cYear && tMonth > cMonth) {
                // 触发错误触感反馈，告知用户不可操作
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                return
            }
        }
        
        // 3. 执行切换
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            currentMonth = newDate
        }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
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
                    .disabled(displayYear >= Calendar.current.component(.year, from: Date()))
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
                    .disabled(isFutureMonth(month))
                }
            }.padding(.horizontal)
            Spacer()
        }.presentationDetents([.height(400)]).presentationDragIndicator(.visible).onAppear { displayYear = Calendar.current.component(.year, from: selection) }
    }
    private func isSelectedMonth(_ month: Int) -> Bool { let selYear = Calendar.current.component(.year, from: selection); let selMonth = Calendar.current.component(.month, from: selection); return selYear == displayYear && selMonth == month }
    private func isThisRealMonth(_ month: Int) -> Bool { let now = Date(); let year = Calendar.current.component(.year, from: now); let m = Calendar.current.component(.month, from: now); return year == displayYear && m == month }
    private func isFutureMonth(_ month: Int) -> Bool {
        guard let candidate = Calendar.current.date(from: DateComponents(year: displayYear, month: month, day: 1)) else { return true }
        return candidate > Date().startOfMonth()
    }
    private func selectMonth(_ month: Int) { var components = DateComponents(); components.year = displayYear; components.month = month; components.day = 1; if let newDate = Calendar.current.date(from: components), !isFutureMonth(month) { withAnimation { selection = newDate }; UIImpactFeedbackGenerator(style: .medium).impactOccurred(); isPresented = false } }
}
