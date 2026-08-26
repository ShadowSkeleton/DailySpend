import SwiftUI
import SwiftData

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

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            selectedDate = date
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
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
                    }
                    .buttonStyle(.plain)
                    .disabled(isFuture)
                    .accessibilityLabel(calendarAccessibilityLabel(for: date, total: total, isToday: isToday))
                    .accessibilityHint(isFuture
                        ? (L10n.isZh ? "未来日期不可选择。" : "Future dates cannot be selected.")
                        : (L10n.isZh ? "选择这一天以查看记录。" : "Select to view this day’s expenses."))
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24).fill(cardBackground).shadow(color: .black.opacity(0.03), radius: 15))
            .padding(.horizontal)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard abs(value.translation.width) > 30 else { return }
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        
                        if value.translation.width < 0 { changeMonth(by: 1) }
                        else { changeMonth(by: -1) }
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
        let calendar = Calendar.current
        guard let newDate = calendar.date(byAdding: .month, value: value, to: currentMonth) else { return }
        
        let now = Date()
        let targetComponents = calendar.dateComponents([.year, .month], from: newDate)
        let currentComponents = calendar.dateComponents([.year, .month], from: now)
        
        if let tYear = targetComponents.year, let tMonth = targetComponents.month,
           let cYear = currentComponents.year, let cMonth = currentComponents.month {
            
            if tYear > cYear || (tYear == cYear && tMonth > cMonth) {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                return
            }
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { currentMonth = newDate }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func calendarAccessibilityLabel(for date: Date, total: Double, isToday: Bool) -> String {
        let dateText = date.formatted(.dateTime.month(.wide).day().year())
        let totalText = total > 0
            ? total.formatted(.currency(code: L10n.currencyCode))
            : (L10n.isZh ? "无支出" : "No expenses")
        let todayText = isToday ? (L10n.isZh ? "，今天" : ", today") : ""
        return "\(dateText)\(todayText)，\(totalText)"
    }

    @MainActor func recalculateExpenses() async {
        let calendar = Calendar.current
        let filtered = expenses.filter { calendar.isDate($0.date, equalTo: currentMonth, toGranularity: .month) }
        var dict: [Date: Double] = [:]
        for exp in filtered { dict[calendar.startOfDay(for: exp.date), default: 0] += exp.normalizedAmount }
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
                        let total = expenses.reduce(0) { $0 + $1.normalizedAmount }
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
                                Text(expense.normalizedAmount.formatted(.currency(code: L10n.currencyCode)))
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
                .disabled(displayYear >= Calendar.current.component(.year, from: Date()))
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
                    .disabled(isFutureMonth(month))
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
        if let newDate = Calendar.current.date(from: components), !isFutureMonth(month) {
            withAnimation { selection = newDate }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            isPresented = false
        }
    }

    private func isFutureMonth(_ month: Int) -> Bool {
        guard let candidate = Calendar.current.date(from: DateComponents(year: displayYear, month: month, day: 1)) else { return true }
        return candidate > Date().startOfMonth()
    }
}
