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
    /// Called with the saved date, so a list can show the month it went to.
    var onSaved: ((Date) -> Void)? = nil
    
    @State private var amount: Double?
    @State private var category = "Food"
    @State private var note = ""
    @State private var date = Date()
    @State private var scanner = ReceiptScanController()
    @State private var appliedDraft: ReceiptDraft?
    @State private var showsDraftBanner = false
    @State private var hasAppeared = false
    @FocusState private var isInputActive: Bool
    @State private var quickText = ""
    @State private var appliedEntry: QuickEntry?
    @State private var isRefiningCategory = false
    @State private var categoryHelper = QuickEntryCategoryHelper()
    @FocusState private var isQuickEntryFocused: Bool
    /// After the first use the explanation and examples step aside.
    @AppStorage("quickAddUsed") private var hasUsedQuickAdd = false
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
                        quickEntrySection
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
    
    private var quickExamples: [String] {
        L10n.isZh ? ["咖啡 18 元", "午饭 36，三人平分", "昨天打车 23"]
                  : ["Coffee 4.50", "Lunch 36, split 3", "Uber 18 yesterday"]
    }

    /// Describe the expense in plain words and the form fills itself in.
    var quickEntrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(themeColor)
                        .accessibilityHidden(true)
                    Text(L10n.isZh ? "快速记账" : "Quick Add")
                        .font(.subheadline.weight(.semibold))
                }
                if !hasUsedQuickAdd {
                    Text(L10n.isZh ? "用一句话说说这笔花费，打字或语音都行，下面的表格会自动填好。"
                                   : "Type or say what you spent in your own words, and the form below fills itself in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    TextField(L10n.isZh ? "例如：午饭 36，3 人平分" : "e.g. Lunch 36, split 3",
                              text: $quickText, axis: .vertical)
                        .lineLimit(1...3)
                        .submitLabel(.done)
                        .focused($isQuickEntryFocused)
                        .onSubmit(readQuickEntry)
                        .onChange(of: quickText) { _, newValue in
                            // A vertical text field puts Return into the text.
                            if newValue.contains("\n") {
                                quickText = newValue.replacingOccurrences(of: "\n", with: "")
                                readQuickEntry()
                            }
                        }
                        .accessibilityIdentifier("quick-entry-field")
                    if !quickText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button(action: readQuickEntry) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundStyle(themeColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.isZh ? "填写" : "Fill in")
                        .accessibilityIdentifier("quick-entry-submit")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: isQuickEntryFocused) { _, focused in
                    if focused { categoryHelper.prepare() }
                }

                if !hasUsedQuickAdd && quickText.isEmpty {
                    // Wrapped, so every example is visible without scrolling.
                    FlowLayout(spacing: 8) {
                            Text(L10n.isZh ? "试试：" : "Try:")
                                .padding(.vertical, 6)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(Array(quickExamples.enumerated()), id: \.offset) { index, example in
                                Button {
                                    quickText = example
                                    readQuickEntry()
                                } label: {
                                    Text(example)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(themeColor)
                                        .background(themeColor.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("quick-example-\(index)")
                            }
                    }
                    .transition(.opacity)
                }
            }
            .padding(14)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))

            if let entry = appliedEntry {
                QuickEntrySummary(entry: entry, isChoosingCategory: isRefiningCategory, themeColor: themeColor)
                    .padding(.horizontal, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
        .animation(.snappy, value: hasUsedQuickAdd)
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
    
    /// Fills the form at once from what the rules read (amount, date, split),
    /// then lets the model refine the category a moment later.
    private func readQuickEntry() {
        let text = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let entry = QuickEntryParser.parse(text)
        apply(entry)
        hasUsedQuickAdd = true
        guard QuickEntryCategoryHelper.isAvailable else { return }
        let categoryAfterRules = category
        isRefiningCategory = true
        Task {
            let refinement = await categoryHelper.refine(text)
            isRefiningCategory = false
            // Only if these words are still the ones shown.
            guard let refinement, appliedEntry?.text == text else { return }
            var refined = entry
            refined.apply(refinement)
            withAnimation {
                // Keep a category or note the person changed in the meantime.
                if category == categoryAfterRules, let modelCategory = refined.category { category = modelCategory }
                if note == entry.note { note = refined.note }
                appliedEntry = refined
            }
        }
    }

    /// Fills the form from plain words. Only what the words say changes, and
    /// nothing is saved until the person taps Save.
    private func apply(_ entry: QuickEntry) {
        withAnimation {
            if let share = entry.amount { amount = share.amount }
            if let category = entry.category { self.category = category }
            if let day = entry.date { date = day }
            // Keep a note the person wrote themselves.
            if note.isEmpty || note == appliedEntry?.note || note == appliedDraft?.suggestedNote {
                note = entry.note
            }
            appliedEntry = entry
        }
        isQuickEntryFocused = false
        isInputActive = entry.amount == nil
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
            onSaved?(date)
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
                            .tint(.red)
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

/// What quick add filled in, and anything to check, under the words.
struct QuickEntrySummary: View {
    let entry: QuickEntry
    var isChoosingCategory = false
    let themeColor: Color

    private var filled: String {
        var parts: [String] = []
        if !entry.title.isEmpty { parts.append(entry.title) }
        if let amount = entry.amount {
            let text = amount.amount.formatted(.currency(code: L10n.currencyCode))
            if let count = entry.splitCount {
                parts.append(L10n.isZh ? "\(text)（\(count) 人平分）" : "\(text) (your share of \(count))")
            } else {
                parts.append(text)
            }
        }
        if let category = entry.category {
            parts.append(L10n.categoryName(category))
        }
        if let date = entry.date {
            parts.append(Calendar.current.isDateInToday(date)
                         ? (L10n.isZh ? "今天" : "Today")
                         : Calendar.current.isDateInYesterday(date)
                            ? (L10n.isZh ? "昨天" : "Yesterday")
                            : date.formatted(.dateTime.month().day()))
        }
        return parts.joined(separator: " · ")
    }

    private var warnings: [String] {
        entry.issues.map { issue in
            switch issue {
            case .noAmount:
                return L10n.isZh ? "没有找到金额，请在下方输入，或写上数字如“12.5”。" : "No amount found. Enter it below, or include one like “12.50”."
            case .addedAmounts(let count):
                let total = (entry.total ?? .zero).amount.formatted(.currency(code: L10n.currencyCode))
                return L10n.isZh ? "找到 \(count) 个金额，已相加为 \(total)。请核对金额。" : "Found \(count) amounts and added them up to \(total). Check the amount."
            case .splitWithoutCount:
                return L10n.isZh ? "要几个人平分？写上人数，如“3 人”。" : "How many people? Add the number, like “split 3”."
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !filled.isEmpty {
                Label(L10n.isZh ? "已填写：\(filled)" : "Filled in: \(filled)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(themeColor)
                    .accessibilityIdentifier("quick-entry-summary")
            }
            ForEach(warnings, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
            if isChoosingCategory {
                Label(L10n.isZh ? "正在挑选最合适的分类…" : "Choosing the best category…", systemImage: "sparkles")
                    .foregroundStyle(themeColor)
                    .symbolEffect(.pulse, options: .repeating)
                    .accessibilityIdentifier("quick-entry-choosing-category")
            }
            if entry.categoryIsFromModel {
                Text(L10n.isZh ? "分类由 Apple 智能在本机选择，可能出错。" : "Category chosen on this device by Apple Intelligence. AI can make mistakes.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
    }
}
