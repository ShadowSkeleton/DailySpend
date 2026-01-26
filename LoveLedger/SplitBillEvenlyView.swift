import SwiftUI

struct SplitBillEvenlyView: View {
    var themeColor: Color
    @Binding var resetTrigger: Bool
    // 新增：完成后的回调，用于跳转回首页
    var onFinish: (() -> Void)?
    var onUpdateReceiptData: ((ReceiptData) -> Void)?
    var onRequestShare: (() -> Void)?
    
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
    
    private func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
    
    private var totalAmount: Double {
        Double(totalAmountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }
    
    private var tipAmount: Double {
        if tipSelection == -2 {
            return customFixedTip ?? 0
        } else {
            let percentage = Double(tipSelection == -1 ? (customTipPercentage ?? 0) : tipSelection)
            return round2(totalAmount * percentage / 100.0)
        }
    }
    
    private var grandTotal: Double { round2(totalAmount + tipAmount) }
    
    private var perPerson: Double {
        guard peopleCount > 0 else { return 0 }
        return round2(grandTotal / Double(peopleCount))
    }
    
    // New computed properties for record amount and note
    private var recordAmount: Double {
        perPerson
    }
    
    private var recordNote: String {
        let totalF = grandTotal.formatted(.currency(code: L10n.currencyCode))
        let perPersonF = perPerson.formatted(.currency(code: L10n.currencyCode))
        
        return L10n.isZh
            ? "AA分账: 总额\(totalF) ÷ \(peopleCount)人 = \(perPersonF)/人"
            : "Split: Total \(totalF) ÷ \(peopleCount) ppl = \(perPersonF)/ea"
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
        .onTapGesture {
            isAmountFocused = false
            isCustomTipFocused = false
        }
        .onChange(of: resetTrigger) { newValue in
            if newValue {
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
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(L10n.currencySymbol)
                    .font(.largeTitle).foregroundStyle(.secondary)
                
                TextField("0", text: $totalAmountText)
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused($isAmountFocused)
                    .foregroundStyle(themeColor)
                    .onChange(of: totalAmountText) { _, _ in
                        updateReceipt()
                    }
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 5)
        )
        .padding(.horizontal)
        .onTapGesture { isAmountFocused = true }
    }
    
    private var controlsSection: some View {
        VStack(spacing: 24) {
            // People Count
            HStack {
                Label(L10n.isZh ? "人数" : "Split by", systemImage: "person.2.fill")
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
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach([10, 15, 18, 20], id: \.self) { pct in
                            TipCapsule(text: "\(pct)%", isSelected: tipSelection == pct, color: themeColor) {
                                tipSelection = pct; updateReceipt()
                            }
                        }
                        TipCapsule(text: "Custom %", isSelected: tipSelection == -1, color: themeColor) {
                            tipSelection = -1; updateReceipt()
                        }
                        TipCapsule(text: "Fixed $", isSelected: tipSelection == -2, color: themeColor) {
                            tipSelection = -2; updateReceipt()
                        }
                    }
                    .padding(.vertical, 4)
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
                Text(L10n.isZh ? "每人支付" : "PER PERSON")
                    .font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
                
                Text(perPerson.formatted(.currency(code: L10n.currencyCode)))
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .contentTransition(.numericText())
            }
            
            // Action Buttons
            HStack(spacing: 16) {
                // Share Button
                Button(action: { onRequestShare?() }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 56)
                        .background(themeColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: themeColor.opacity(0.3), radius: 5, x: 0, y: 3)
                }
                
                // Record Button - opens the dedicated sheet
                Button(action: {
                    showRecordSheet = true
                }) {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text(L10n.isZh ? "记录我的份额" : "Record My Share")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(themeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: themeColor.opacity(0.3), radius: 5, x: 0, y: 3)
                }
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
            .currency(L10n.isZh ? "每人" : "Per Person", perPerson),
            .integer(L10n.isZh ? "人数" : "People", peopleCount)
        ]
        
        let data = ReceiptData(
            title: L10n.isZh ? "平摊模式" : "Evenly Split",
            items: items,
            subtotal: totalAmount > 0 ? totalAmount : nil,
            tax: 0,
            tip: tipAmount,
            total: grandTotal,
            footer: "Split by \(peopleCount) • Generated by LoveLedger"
        )
        onUpdateReceiptData?(data)
    }
}
