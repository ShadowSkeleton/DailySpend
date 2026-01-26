import SwiftUI
import SwiftData

// MARK: - Add View
struct AddExpenseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var themeColor: Color
    
    // 预填充数据
    var prefilledAmount: Double?
    var prefilledNote: String?
    var prefilledCategory: String?
    
    // ✨ 新增：保存成功后的回调
    var onSave: (() -> Void)? = nil
    
    @State private var amount: Double?
    @State private var category = "Food"
    @State private var note = ""
    @State private var date = Date()
    @State private var showingScanner = false
    @FocusState private var isInputActive: Bool
    @AppStorage("showScanTip") private var showScanTip = true
    @State private var showScanAlert = false
    
    @State private var frequency: RecurrenceFrequency = .none
    
    let columns = [GridItem(.adaptive(minimum: 75))]
    let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        amountSection
                        categorySection
                        detailsSection
                        Spacer().frame(height: 100)
                    }.padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { isInputActive = false }
                
                VStack {
                    Button(action: saveExpense) {
                        Text(L10n.save)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(amount == nil ? Color.gray.opacity(0.3) : themeColor)
                            }
                    }
                    .disabled(amount == nil)
                    .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
                }.background(cardBackground)
            }
            .navigationTitle(L10n.newExpense)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.cancel) { dismiss() }.tint(.primary) }
            }
            .onAppear {
                if let initialAmount = prefilledAmount, amount == nil { amount = initialAmount }
                if let initialNote = prefilledNote, note.isEmpty { note = initialNote }
                if let initialCat = prefilledCategory { category = initialCat }
                
                if amount == nil && !showingScanner {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isInputActive = true }
                }
            }
            .alert(L10n.scanTipTitle, isPresented: $showScanAlert) {
                Button(L10n.dontShowAgain) { showScanTip = false; showingScanner = true }
                Button(L10n.gotIt) { showingScanner = true }
            } message: { Text(L10n.scanTipMessage) }
            .sheet(isPresented: $showingScanner) {
                ReceiptScannerView(scannedAmount: $amount).ignoresSafeArea()
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    var amountSection: some View {
        VStack(spacing: 10) {
            Text(L10n.amount).font(.caption).fontWeight(.bold).foregroundStyle(.secondary).tracking(1)
            HStack(alignment: .center, spacing: 8) {
                Text(L10n.currencySymbol).roundedNumFont(size: 36, weight: .bold).foregroundStyle(themeColor)
                TextField("0", value: $amount, format: .number).roundedNumFont(size: 64, weight: .heavy).keyboardType(.decimalPad).focused($isInputActive).multilineTextAlignment(.center).tint(themeColor).frame(minWidth: 60)
                Button(action: { if showScanTip { showScanAlert = true } else { showingScanner = true } }) {
                    Image(systemName: "doc.text.viewfinder").font(.system(size: 24, weight: .semibold)).foregroundColor(themeColor).padding(12).background(themeColor.opacity(0.1)).clipShape(Circle())
                }
            }.padding(.horizontal, 24)
        }.frame(maxWidth: .infinity).padding(.vertical, 30).background { RoundedRectangle(cornerRadius: 24).fill(themeColor.opacity(0.1)) }.padding(.horizontal)
    }
    
    var categorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.category).font(.caption).fontWeight(.bold).foregroundStyle(.secondary).tracking(1).padding(.horizontal)
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Expense.categories, id: \.name) { item in
                    CategoryButton(item: item, isSelected: category == item.name) { category = item.name }
                }
            }.padding(.horizontal)
        }
    }
    
    var detailsSection: some View {
        VStack(spacing: 0) {
            DatePicker(L10n.date, selection: $date, displayedComponents: .date).padding()
            Divider()
            HStack {
                Text(L10n.recurrence)
                Spacer()
                Picker("", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                }
                .tint(themeColor)
            }
            .padding()
            Divider()
            TextField(L10n.notePlaceholder, text: $note).padding()
        }.background(cardBackground).cornerRadius(16).padding(.horizontal)
    }
    
    private func saveExpense() {
        guard let validAmount = amount else { return }
        
        let newExpense = Expense(
            amount: validAmount,
            category: category,
            note: note,
            date: date,
            frequency: frequency
        )
        
        modelContext.insert(newExpense)
        try? modelContext.save()
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // ✨ 先触发回调，再 dismiss
        onSave?()
        dismiss()
    }
}

// MARK: - Edit View
struct EditExpenseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var expense: Expense
    var themeColor: Color
    
    @State private var amount: Double
    @State private var category: String
    @State private var note: String
    @State private var date: Date
    @FocusState private var isInputActive: Bool
    @State private var frequency: RecurrenceFrequency
    
    let columns = [GridItem(.adaptive(minimum: 75))]
    let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    
    init(expense: Expense, themeColor: Color) {
        self.expense = expense
        self.themeColor = themeColor
        _amount = State(initialValue: expense.amount)
        _category = State(initialValue: expense.category)
        _note = State(initialValue: expense.note)
        _date = State(initialValue: expense.date)
        _frequency = State(initialValue: expense.safeFrequency)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        amountSection
                        categorySection
                        detailsSection
                        Button(role: .destructive, action: deleteExpense) {
                            Text(L10n.deleteTransaction).fontWeight(.medium).frame(maxWidth: .infinity).padding().background(Color.red.opacity(0.1)).foregroundColor(.red).cornerRadius(12)
                        }.padding(.horizontal).padding(.top, 10)
                        Spacer().frame(height: 100)
                    }.padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { isInputActive = false }
                
                VStack {
                    Button(action: saveChanges) {
                        Text(L10n.save).fontWeight(.bold).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16).background(themeColor).cornerRadius(16)
                    }.padding(.horizontal).padding(.vertical)
                }.background(cardBackground)
            }
            .navigationTitle(L10n.editExpense)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.cancel) { dismiss() }.tint(.primary) }
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    var amountSection: some View {
        VStack(spacing: 10) {
            Text(L10n.amount).font(.caption).fontWeight(.bold).foregroundStyle(.secondary).tracking(1)
            HStack(alignment: .center, spacing: 8) {
                Text(L10n.currencySymbol).roundedNumFont(size: 36, weight: .bold).foregroundStyle(themeColor)
                TextField("0", value: $amount, format: .number).roundedNumFont(size: 64, weight: .heavy).keyboardType(.decimalPad).focused($isInputActive).multilineTextAlignment(.center).tint(themeColor).frame(minWidth: 60)
            }.padding(.horizontal, 24)
        }.frame(maxWidth: .infinity).padding(.vertical, 30).background { RoundedRectangle(cornerRadius: 24).fill(themeColor.opacity(0.1)) }.padding(.horizontal)
    }
    
    var categorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.category).font(.caption).fontWeight(.bold).foregroundStyle(.secondary).tracking(1).padding(.horizontal)
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Expense.categories, id: \.name) { item in
                    CategoryButton(item: item, isSelected: category == item.name) { category = item.name }
                }
            }.padding(.horizontal)
        }
    }
    
    var detailsSection: some View {
        VStack(spacing: 0) {
            DatePicker(L10n.date, selection: $date, displayedComponents: .date).padding()
            Divider()
            HStack {
                Text(L10n.recurrence)
                Spacer()
                Picker("", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                }
                .tint(themeColor)
            }
            .padding()
            Divider()
            TextField(L10n.notePlaceholder, text: $note).padding()
        }.background(cardBackground).cornerRadius(16).padding(.horizontal)
    }
    
    private func saveChanges() {
        let isFrequencyChanged = expense.safeFrequency != frequency
        let isDateChanged = !Calendar.current.isDate(expense.date, inSameDayAs: date)
        if isFrequencyChanged || isDateChanged { expense.lastProcessedDate = nil }
        
        expense.amount = amount
        expense.category = category
        expense.note = note
        expense.date = date
        expense.frequency = frequency
        
        try? modelContext.save()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        dismiss()
    }
    
    private func deleteExpense() {
        modelContext.delete(expense)
        try? modelContext.save()
        dismiss()
    }
}
