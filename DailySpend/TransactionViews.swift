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
    var prefilledDate: Date?
    /// A receipt already read elsewhere, such as from the Home scan button.
    var prefilledDraft: ReceiptDraft?
    
    // ✨ 新增：保存成功后的回调
    var onSave: (() -> Void)? = nil
    
    @State private var amount: Double?
    @State private var category = "Food"
    @State private var note = ""
    @State private var date = Date()
    @State private var scanner = ReceiptScanController()
    @State private var appliedDraft: ReceiptDraft?
    @State private var showsDraftBanner = false
    @State private var hasAppeared = false
    @FocusState private var isInputActive: Bool
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
                        if showsDraftBanner, let draft = appliedDraft {
                            ReceiptDraftBanner(draft: draft, context: .expense, themeColor: themeColor) {
                                withAnimation { showsDraftBanner = false }
                            }
                            .padding(.horizontal)
                        }
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
                // A sheet's onAppear can run again after a nested camera or
                // photo picker closes; only the first appearance prefills.
                guard !hasAppeared else { return }
                hasAppeared = true
                scanner.onDraft = { apply($0) }
                if let initialAmount = prefilledAmount, amount == nil { amount = initialAmount }
                if let initialNote = prefilledNote, note.isEmpty { note = initialNote }
                if let initialCat = prefilledCategory { category = initialCat }
                if let initialDate = prefilledDate { date = initialDate }
                if let prefilledDraft { apply(prefilledDraft) }
                
                if amount == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isInputActive = true }
                }
            }
            .receiptScanning(scanner, themeColor: themeColor)
            .alert(L10n.isZh ? "无法保存支出" : "Couldn’t Save Expense", isPresented: $showSaveError) {
                Button(L10n.ok, role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    var amountSection: some View {
        VStack(spacing: 10) {
            Text(L10n.amount).font(.caption).fontWeight(.bold).foregroundStyle(.secondary).tracking(1)
            ExpenseAmountField(amount: $amount, isFocused: $isInputActive, themeColor: themeColor)
            if amount != nil && !isValidAmount {
                Text(L10n.isZh ? "请输入大于 0 的金额" : "Enter an amount greater than zero")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            ReceiptScanButton(controller: scanner, themeColor: themeColor)
                .padding(.top, 4)
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
            TextField(L10n.notePlaceholder, text: $note, axis: .vertical)
                .lineLimit(2...6)
                .accessibilityIdentifier("expense-note")
                .padding()
        }.background(cardBackground).cornerRadius(16).padding(.horizontal)
    }
    
    /// Fills the form from a receipt. Nothing is saved until the person taps
    /// Save, and fields the scan didn't read keep their current values.
    private func apply(_ draft: ReceiptDraft) {
        withAnimation {
            if let total = draft.amountToRecord { amount = total.amount }
            if let remembered = rememberedCategory(for: draft.merchant) ?? draft.category {
                category = remembered
            }
            if let receiptDate = draft.date { date = receiptDate }
            let suggestion = draft.suggestedNote
            // Replace the note only if the person hasn't written their own.
            if !suggestion.isEmpty && (note.isEmpty || note == appliedDraft?.suggestedNote) {
                note = suggestion
            }
            appliedDraft = draft
            showsDraftBanner = true
        }
        isInputActive = draft.amountToRecord == nil
    }

    /// The category this person chose last time at the same store. Their own
    /// history is a better guess than the model's general one.
    private func rememberedCategory(for merchant: String?) -> String? {
        guard let merchant, merchant.count >= 2 else { return nil }
        var descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.note.localizedStandardContains(merchant) },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        return matches.first { expense in
            let firstLine = expense.note.split(separator: "\n").first.map(String.init) ?? ""
            return firstLine.localizedCaseInsensitiveCompare(merchant) == .orderedSame
        }?.category
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
        _note = State(initialValue: expense.displayNote)
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
            .alert(L10n.deleteExpenseTitle, isPresented: $showDeleteConfirmation) {
                Button(L10n.cancel, role: .cancel) { }
                Button(L10n.deleteTransaction, role: .destructive, action: deleteExpense)
            } message: {
                Text(L10n.deleteExpenseMessage)
            }
            .alert(L10n.isZh ? "无法保存支出" : "Couldn’t Save Expense", isPresented: $showSaveError) {
                Button(L10n.ok, role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }
    
    var amountSection: some View {
        VStack(spacing: 10) {
            Text(L10n.amount).font(.caption).fontWeight(.bold).foregroundStyle(.secondary).tracking(1)
            ExpenseAmountField(
                amount: Binding(get: { amount }, set: { amount = $0 ?? 0 }),
                isFocused: $isInputActive,
                themeColor: themeColor
            )
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
            TextField(L10n.notePlaceholder, text: $note, axis: .vertical)
                .lineLimit(2...6)
                .accessibilityIdentifier("expense-note")
                .padding()
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

// MARK: - Amount Field

/// The large amount entry used by Add and Edit. The currency symbol sits
/// directly beside the number, matching Quick Split, instead of floating at
/// the card's edge.
struct ExpenseAmountField: View {
    @Binding var amount: Double?
    var isFocused: FocusState<Bool>.Binding
    let themeColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(L10n.currencySymbol)
                .roundedNumFont(size: 36, weight: .bold)
                .foregroundStyle(themeColor)
            // Prefilled and edited amounts always show their cents, like
            // every other amount in the app ("222.20", not "222.2").
            TextField("0", value: $amount, format: .number.precision(.fractionLength(2)))
                .roundedNumFont(size: 64, weight: .heavy)
                .keyboardType(.decimalPad)
                .focused(isFocused)
                .tint(themeColor)
                .fixedSize()
                .accessibilityLabel(L10n.amount)
                .accessibilityIdentifier("expense-amount")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
        .onTapGesture { isFocused.wrappedValue = true }
    }
}
