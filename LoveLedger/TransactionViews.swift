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
    @State private var scanErrorMessage: String?
    @FocusState private var isInputActive: Bool
    @AppStorage("showScanTip") private var showScanTip = true
    @State private var showScanAlert = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    
    @State private var frequency: RecurrenceFrequency = .none
    
    let columns = [GridItem(.adaptive(minimum: 75))]
    let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)

    private var isValidAmount: Bool {
        ExpenseInputValidator.isValidAmount(amount)
    }
    
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
                
                VStack {
                    Button(action: saveExpense) {
                        Text(L10n.save)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeColor)
                    .controlSize(.large)
                    .disabled(!isValidAmount)
                    .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
                }.background(cardBackground)
            }
            .navigationTitle(L10n.newExpense)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.cancel) { dismiss() }.tint(.primary) }
                // Keep this away from the keyboard accessory row. On current
                // iOS releases that row can visually collide with the sticky
                // Save button, leaving two unrelated controls in one target.
                ToolbarItem(placement: .topBarTrailing) {
                    if isInputActive {
                        KeyboardDismissButton { isInputActive = false }
                    }
                }
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
                ReceiptScannerView(
                    scannedAmount: $amount,
                    scanErrorMessage: $scanErrorMessage
                )
                .ignoresSafeArea()
            }
            .alert("Couldn’t Save Expense", isPresented: $showSaveError) {
                Button(L10n.ok, role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
            .alert("Couldn’t Scan Receipt", isPresented: Binding(
                get: { scanErrorMessage != nil },
                set: { if !$0 { scanErrorMessage = nil } }
            )) {
                Button(L10n.ok, role: .cancel) { scanErrorMessage = nil }
            } message: {
                Text(scanErrorMessage ?? "")
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
                .accessibilityLabel(L10n.isZh ? "扫描收据" : "Scan receipt")
                .accessibilityHint(L10n.isZh ? "用相机识别收据金额" : "Use the camera to recognize a receipt amount.")
            }.padding(.horizontal, 24)
            if amount != nil && !isValidAmount {
                Text("Enter an amount greater than zero")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 24).background { RoundedRectangle(cornerRadius: 20).fill(themeColor.opacity(0.1)) }.padding(.horizontal)
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
        guard let validAmount = amount, isValidAmount else { return }
        let money = Money(validAmount)
        
        let newExpense = Expense(
            amount: money.amount,
            amountMinorUnits: money.minorUnits,
            category: category,
            note: note,
            date: date,
            frequency: frequency
        )
        
        do {
            modelContext.insert(newExpense)
            try modelContext.save()

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            onSave?()
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
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
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showDeleteConfirmation = false
    
    let columns = [GridItem(.adaptive(minimum: 75))]
    let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)

    private var isValidAmount: Bool {
        ExpenseInputValidator.isValidAmount(amount)
    }
    
    init(expense: Expense, themeColor: Color) {
        self.expense = expense
        self.themeColor = themeColor
        _amount = State(initialValue: expense.normalizedAmount)
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
                        Button(L10n.deleteTransaction, role: .destructive) { showDeleteConfirmation = true }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal)
                            .padding(.top, 10)
                        Spacer().frame(height: 100)
                    }.padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                
                VStack {
                    Button(action: saveChanges) {
                        Text(L10n.save).frame(maxWidth: .infinity).frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeColor)
                    .controlSize(.large)
                    .disabled(!isValidAmount)
                    .padding(.horizontal).padding(.vertical)
                }.background(cardBackground)
            }
            .navigationTitle(L10n.editExpense)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.cancel) { dismiss() }.tint(.primary) }
                ToolbarItem(placement: .topBarTrailing) {
                    if isInputActive {
                        KeyboardDismissButton { isInputActive = false }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .alert("Delete this expense?", isPresented: $showDeleteConfirmation) {
                Button(L10n.cancel, role: .cancel) { }
                Button(L10n.deleteTransaction, role: .destructive, action: deleteExpense)
            } message: {
                Text("This can’t be undone from the transaction list.")
            }
            .alert("Couldn’t Save Expense", isPresented: $showSaveError) {
                Button(L10n.ok, role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }
    
    var amountSection: some View {
        VStack(spacing: 10) {
            Text(L10n.amount).font(.caption).fontWeight(.bold).foregroundStyle(.secondary).tracking(1)
            HStack(alignment: .center, spacing: 8) {
                Text(L10n.currencySymbol).roundedNumFont(size: 36, weight: .bold).foregroundStyle(themeColor)
                TextField("0", value: $amount, format: .number).roundedNumFont(size: 64, weight: .heavy).keyboardType(.decimalPad).focused($isInputActive).multilineTextAlignment(.center).tint(themeColor).frame(minWidth: 60)
            }.padding(.horizontal, 24)
        }.frame(maxWidth: .infinity).padding(.vertical, 24).background { RoundedRectangle(cornerRadius: 20).fill(themeColor.opacity(0.1)) }.padding(.horizontal)
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
        guard isValidAmount else { return }
        let isFrequencyChanged = expense.safeFrequency != frequency
        let isDateChanged = !Calendar.current.isDate(expense.date, inSameDayAs: date)
        if isFrequencyChanged || isDateChanged { expense.lastProcessedDate = nil }
        
        expense.setAmount(amount)
        expense.category = category
        expense.note = note
        expense.date = date
        expense.frequency = frequency
        
        do {
            try modelContext.save()
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
    
    private func deleteExpense() {
        do {
            modelContext.delete(expense)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
}
