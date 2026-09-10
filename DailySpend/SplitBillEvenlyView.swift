import SwiftUI

struct SplitBillEvenlyView: View {
    var themeColor: Color
    @Binding var resetTrigger: Bool
    // 新增：完成后的回调，用于跳转回首页
    var onFinish: (() -> Void)?
    var onUpdateReceiptData: ((ReceiptData) -> Void)?
    var onRequestShare: (() -> Void)?
    var isPreparingShare = false
    
    // FIXED: Use String for TextField to avoid number formatting commit issues
    @State private var totalAmountText: String = ""
    @State private var peopleCount: Int = 2
    
    // Tip States
    @State private var tipSelection: Int = 15
    @State private var customTipPercentage: Int?
    @State private var customFixedTip: Double?
    
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isCustomTipFocused: Bool
    
    // New: Dedicated state for showing record sheet
    @State private var showRecordSheet: Bool = false
    
    // MARK: - Computed Values (derived from String input)
    
    private var totalAmount: Double {
        MoneyTextInput.parse(totalAmountText) ?? 0
    }

    private var totalAmountDisplayLength: Int {
        max(1, totalAmountText.count)
    }

    private var totalAmountFontSize: CGFloat {
        switch totalAmountDisplayLength {
        case ...6: 64
        case ...9: 50
        case ...12: 38
        default: 26
        }
    }

    private var totalAmountFieldWidth: CGFloat {
        min(270, max(48, CGFloat(totalAmountDisplayLength) * totalAmountFontSize * 0.64 + 8))
    }

    private var totalMoney: Money { Money(totalAmount) }

    private var tipMoney: Money {
        if tipSelection == -2 {
            return Money(customFixedTip ?? 0)
        }
        let percentage = tipSelection == -1 ? (customTipPercentage ?? 0) : tipSelection
        return totalMoney.applying(percent: percentage)
    }

    private var tipAmount: Double {
        tipMoney.amount
    }

    private var grandTotalMoney: Money { totalMoney + tipMoney }

    private var grandTotal: Double { grandTotalMoney.amount }

    private var allocatedAmounts: [Money] {
        Money.splitEvenly(grandTotalMoney, among: peopleCount)
    }

    private var perPerson: Double {
        allocatedAmounts.first?.amount ?? 0
    }

    private var hasUnevenRemainder: Bool {
        Set(allocatedAmounts.map(\.minorUnits)).count > 1
    }

    private var allocationSummary: String {
        let groups = Dictionary(grouping: allocatedAmounts, by: \.minorUnits)
            .map { (amount: $0.key, count: $0.value.count) }
            .sorted { $0.amount > $1.amount }

        guard groups.count > 1 else {
            return L10n.isZh
                ? "每人支付 \(perPerson.formatted(.currency(code: L10n.currencyCode)))"
                : "Each pays \(perPerson.formatted(.currency(code: L10n.currencyCode)))"
        }

        return groups.map { group in
            let formatted = Money(minorUnits: group.amount).amount.formatted(.currency(code: L10n.currencyCode))
            return L10n.isZh
                ? "\(group.count) 人支付 \(formatted)"
                : "\(group.count) pay \(formatted)"
        }.joined(separator: " • ")
    }

    private var canSettle: Bool {
        guard ExpenseInputValidator.isValidLineItemAmount(totalAmount) else { return false }
        if tipSelection == -2 {
            return customFixedTip.map(ExpenseInputValidator.isValidLineItemAmount) ?? false
        }
        return customTipPercentage.map { $0 >= 0 } ?? true
    }

    private var validationMessage: String? {
        guard totalAmountText.isEmpty || ExpenseInputValidator.isValidLineItemAmount(totalAmount) else {
            return L10n.isZh ? "请输入大于 0 的账单总额" : "Enter a bill total greater than zero."
        }
        if tipSelection == -2, !(customFixedTip.map(ExpenseInputValidator.isValidLineItemAmount) ?? false) {
            return L10n.isZh ? "请输入大于 0 的固定小费" : "Enter a fixed tip greater than zero."
        }
        if customTipPercentage.map({ $0 < 0 }) == true {
            return L10n.isZh ? "小费比例不能为负数" : "Tip percentage can’t be negative."
        }
        return nil
    }

    // New computed properties for record amount and note
    private var recordAmount: Double {
        allocatedAmounts.first?.amount ?? 0
    }
    
    private var recordNote: String {
        SplitNote.quick(total: grandTotalMoney, share: Money(recordAmount), people: peopleCount)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                totalInputSection
                controlsSection
                resultSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                KeyboardDismissButton {
                    isAmountFocused = false
                    isCustomTipFocused = false
                }
            }
        }
        .onChange(of: resetTrigger) { _, shouldReset in
            if shouldReset {
                withAnimation {
                    totalAmountText = ""
                    peopleCount = 2
                    tipSelection = 15
                    customTipPercentage = nil
                    customFixedTip = nil
                    updateReceipt()
                }
                resetTrigger = false
            }
        }
        .onChange(of: tipSelection) { _, _ in updateReceipt() }
        .onAppear { updateReceipt() }
    }
    
    // MARK: - Subviews (Broken out to fix compiler timeout)
    
    private var totalInputSection: some View {
        VStack(spacing: 16) {
            Text(L10n.isZh ? "账单总额" : "TOTAL BILL")
                .font(.caption).fontWeight(.bold).foregroundStyle(.secondary).tracking(2)
            
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(L10n.currencySymbol)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("total-bill-currency")
                
                TextField("0", text: $totalAmountText)
                    .font(.system(size: totalAmountFontSize, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .frame(width: totalAmountFieldWidth, alignment: .leading)
                    .keyboardType(.decimalPad)
                    .focused($isAmountFocused)
                    .foregroundStyle(themeColor)
                    .accessibilityLabel(L10n.isZh ? "账单总额" : "Total bill amount")
                    .accessibilityIdentifier("total-bill-amount")
                    .onChange(of: totalAmountText) { _, _ in
                        updateReceipt()
                    }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
        .padding(.horizontal)
    }
    
    private var controlsSection: some View {
        VStack(spacing: 24) {
            // People Count
            HStack {
                Label(L10n.isZh ? "参与人数" : "People", systemImage: "person.2.fill")
                    .font(.headline)
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: {
                        if peopleCount > 1 { peopleCount -= 1; updateReceipt() }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(peopleCount > 1 ? .secondary : .tertiary)
                    }
                    .disabled(peopleCount <= 1)
                    .accessibilityLabel(L10n.isZh ? "减少参与者" : "Remove person")
                    
                    Text("\(peopleCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .frame(minWidth: 30)
                    
                    Button(action: {
                        peopleCount += 1; updateReceipt()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(L10n.isZh ? "增加参与者" : "Add person")
                }
                .padding(8)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .cornerRadius(12)
            }
            
            Divider()
            
            // Tip Selector
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(L10n.isZh ? "小费" : "Tip", systemImage: "heart.circle.fill")
                        .font(.headline)
                    Spacer()
                    Text(tipAmount.formatted(.currency(code: L10n.currencyCode)))
                        .foregroundStyle(themeColor)
                        .fontWeight(.bold)
                }
                
                // A compact grid keeps every choice visible on a phone. The former
                // horizontal row hid the custom choices off-screen at first glance.
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach([10, 15, 18, 20], id: \.self) { pct in
                        TipOptionButton(text: "\(pct)%", isSelected: tipSelection == pct, color: themeColor) {
                            tipSelection = pct; updateReceipt()
                        }
                    }
                    TipOptionButton(text: L10n.isZh ? "自定比例" : "Custom %", isSelected: tipSelection == -1, color: themeColor) {
                        tipSelection = -1; updateReceipt()
                    }
                    TipOptionButton(text: L10n.isZh ? "固定金额" : "Fixed \(L10n.currencySymbol)", isSelected: tipSelection == -2, color: themeColor) {
                        tipSelection = -2; updateReceipt()
                    }
                }
                
                // Custom Tip Inputs
                if tipSelection == -1 {
                    HStack {
                        Text(L10n.isZh ? "输入比例" : "Enter %").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        TextField("20", value: $customTipPercentage, format: .number)
                            .keyboardType(.numberPad)
                            .focused($isCustomTipFocused)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .padding(8)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .cornerRadius(8)
                            .onChange(of: customTipPercentage) { _, _ in updateReceipt() }
                        Text("%")
                    }
                } else if tipSelection == -2 {
                    HStack {
                        Text(L10n.isZh ? "输入金额" : "Enter Amount").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(L10n.currencySymbol).foregroundStyle(.secondary)
                            TextField("5.00", value: $customFixedTip, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .onChange(of: customFixedTip) { _, _ in updateReceipt() }
                        }
                        .padding(8)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(24)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(24)
        .padding(.horizontal)
    }
    
    private var resultSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(hasUnevenRemainder ? (L10n.isZh ? "我的份额" : "YOUR SHARE") : (L10n.isZh ? "每人支付" : "PER PERSON"))
                    .font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
                
                Text(perPerson.formatted(.currency(code: L10n.currencyCode)))
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .contentTransition(.numericText())

                Text(allocationSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Action Buttons
            HStack(spacing: 16) {
                // Share Button
                Button(action: { onRequestShare?() }) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 60, height: 56)
                }
                .buttonStyle(.bordered)
                .tint(themeColor)
                .disabled(!canSettle || isPreparingShare)
                .opacity(canSettle && !isPreparingShare ? 1 : 0.45)
                .accessibilityLabel(L10n.isZh ? "分享分账收据" : "Share split receipt")
                .accessibilityHint(isPreparingShare
                    ? (L10n.isZh ? "正在准备收据" : "Preparing receipt")
                    : (L10n.isZh ? "分享完整分账收据" : "Shares the completed split receipt."))
                
                // Record Button - opens the dedicated sheet
                Button(action: {
                    showRecordSheet = true
                }) {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text(L10n.isZh ? "记录我的份额" : "Record My Share")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(themeColor)
                .disabled(!canSettle)
                .opacity(canSettle ? 1 : 0.45)
                .sheet(isPresented: $showRecordSheet) {
                    AddExpenseView(
                        themeColor: themeColor,
                        prefilledAmount: recordAmount,
                        prefilledNote: recordNote,
                        prefilledCategory: "Food",
                        onSave: {
                            // 1. 立刻关闭 Sheet
                            showRecordSheet = false
                            
                            // 2. 几乎立刻跳转回主页 (0.1秒只是为了等待Sheet关闭动画开始)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                onFinish?()
                            }
                            
                            // 3. 在跳转完成后（0.6秒后），在后台默默清空表单
                            // 这样用户就完全看不到数字归零的过程了
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                resetTrigger = true
                            }
                        }
                    )
                }
            }
        }
        .padding(24)
        .padding(.bottom, 50)
    }
    
    private func updateReceipt() {
        let items: [ReceiptItem] = [
            .text(L10n.isZh ? "分摊" : "Split", allocationSummary),
            .integer(L10n.isZh ? "人数" : "People", peopleCount)
        ]
        
        let data = ReceiptData(
            title: L10n.isZh ? "平摊模式" : "Evenly Split",
            items: items,
            subtotal: totalAmount > 0 ? totalAmount : nil,
            tax: 0,
            tip: tipAmount,
            total: grandTotal,
            footer: "Split by \(peopleCount) • Generated by DailySpend"
        )
        onUpdateReceiptData?(data)
    }
}
