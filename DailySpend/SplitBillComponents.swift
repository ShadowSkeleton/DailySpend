import SwiftUI
import UIKit

// MARK: - Tip

/// The tip control shared by both split modes. When a scanned receipt prints
/// a tip guide, its own choices and amounts replace the usual percentages,
/// like the tip screen on a card reader. "Custom" holds both a custom
/// percentage and a fixed amount. Where tipping isn't customary the choices
/// stay folded behind "Add Tip", one tap away when traveling.
struct TipSelector: View {
    @Binding var selection: Int
    @Binding var customPercentage: Int?
    @Binding var fixedAmount: Double?
    let tipAmount: Double
    let themeColor: Color
    /// How percentages are figured, when the bill's tax or tip guide is known.
    var calculator: TipCalculator? = nil
    var tippingIsCustomary = TipPreset.isCustomary

    @State private var isUnfolded = false

    private var percentages: [Int] { calculator?.percentages ?? TipPreset.percentages }

    private var isCustom: Bool {
        selection == TipPreset.customPercentage || selection == TipPreset.fixedAmount
    }

    private var isUndecided: Bool { selection == TipPreset.undecided }

    private var showsChoices: Bool {
        tippingIsCustomary || isUnfolded || selection != TipPreset.none
    }

    private var usesReceiptGuide: Bool { !(calculator?.suggestions.isEmpty ?? true) }

    private func currency(_ money: Money) -> String {
        money.amount.formatted(.currency(code: L10n.currencyCode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.isZh ? "小费" : "Tip", systemImage: "heart.circle.fill")
                    .font(.headline)
                Spacer()
                if showsChoices {
                    Text(isUndecided ? (L10n.isZh ? "待选择" : "Not chosen") : tipAmount.formatted(.currency(code: L10n.currencyCode)))
                        .foregroundStyle(isUndecided ? Color.secondary : themeColor)
                        .fontWeight(.bold)
                        .contentTransition(.numericText())
                } else {
                    Button {
                        isUnfolded = true
                    } label: {
                        Label(L10n.isZh ? "添加小费" : "Add Tip", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(themeColor)
                            .background(themeColor.opacity(0.12), in: Capsule())
                    }
                    .accessibilityIdentifier("tip-add")
                }
            }

            if showsChoices {
                choices
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: showsChoices)
        .animation(.snappy, value: isCustom)
        .animation(.snappy, value: isUndecided)
        .animation(.snappy, value: percentages)
        .onAppear(perform: keepSelectionVisible)
        .onChange(of: percentages) { _, _ in keepSelectionVisible() }
    }

    /// A percentage that is no longer offered, such as the receipt's 22%
    /// after its items are edited, stays chosen as a custom percentage.
    private func keepSelectionVisible() {
        guard selection > 0, !percentages.contains(selection) else { return }
        customPercentage = selection
        selection = TipPreset.customPercentage
    }

    @ViewBuilder
    private var choices: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isUndecided {
                Label(L10n.isZh ? "收据上还没有小费。选择一项，算进每个人的金额。"
                                : "This bill leaves the tip to you. Choose one to include it in everyone’s share.",
                      systemImage: "hand.tap.fill")
                    .font(.footnote)
                    .foregroundStyle(themeColor)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(themeColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("tip-undecided-hint")
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                TipOptionButton(text: L10n.isZh ? "不加" : "None", isSelected: selection == TipPreset.none, color: themeColor) {
                    selection = TipPreset.none
                }
                .accessibilityIdentifier("tip-none")
                ForEach(percentages, id: \.self) { percentage in
                    TipOptionButton(text: "\(percentage)%",
                                    detail: usesReceiptGuide ? calculator?.printedTip(percent: percentage).map(currency) : nil,
                                    isSelected: selection == percentage, color: themeColor) {
                        selection = percentage
                    }
                }
                TipOptionButton(text: L10n.isZh ? "自定义" : "Custom", isSelected: isCustom, color: themeColor) {
                    if !isCustom { selection = TipPreset.customPercentage }
                }
                .accessibilityIdentifier("tip-custom")
            }

            if isCustom {
                HStack(spacing: 12) {
                    Picker(L10n.isZh ? "自定义小费方式" : "Custom tip type", selection: $selection) {
                        Text("%").tag(TipPreset.customPercentage)
                        Text(L10n.currencySymbol).tag(TipPreset.fixedAmount)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                    .accessibilityIdentifier("custom-tip-type")

                    Spacer()

                    if selection == TipPreset.customPercentage {
                        HStack(spacing: 4) {
                            TextField("20", value: $customPercentage, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel(L10n.isZh ? "小费比例" : "Tip percentage")
                            Text("%").foregroundStyle(.secondary)
                        }
                        .frame(width: 96)
                        .padding(8)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        HStack(spacing: 4) {
                            Text(L10n.currencySymbol).foregroundStyle(.secondary)
                            TextField("5.00", value: $fixedAmount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel(L10n.isZh ? "固定小费金额" : "Fixed tip amount")
                        }
                        .frame(width: 96)
                        .padding(8)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tip-basis-note")
            }
        }
    }

    /// One quiet line saying where the tip choices come from. Nothing to decide.
    private var note: String? {
        guard let calculator else { return nil }
        if usesReceiptGuide {
            return L10n.isZh ? "来自收据上的小费建议" : "From the receipt’s tip guide"
        }
        let isPercentage = selection > 0 || selection == TipPreset.customPercentage
        guard isPercentage, calculator.hasSeparateTax else { return nil }
        return calculator.basis == .beforeTax
            ? (L10n.isZh ? "按税前 \(currency(calculator.base)) 计算" : "Figured on \(currency(calculator.base)) before tax")
            : (L10n.isZh ? "按税后 \(currency(calculator.base)) 计算，与收据一致" : "Figured on \(currency(calculator.base)) after tax, like this receipt")
    }
}

// Equal tiles keep choices immediately visible and prevent short labels from
// collapsing into circles.
struct TipOptionButton: View {
    let text: String
    /// A second line, such as the tip amount a receipt printed for this choice.
    var detail: String? = nil
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                HStack(spacing: 6) {
                    Text(text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .accessibilityHidden(true)
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(isSelected ? 0.9 : 0.6)
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? color : Color(uiColor: .tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? color : Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(detail.map { "\(text), \($0)" } ?? text)
        .accessibilityValue(isSelected ? (L10n.isZh ? "已选择" : "Selected") : (L10n.isZh ? "未选择" : "Not selected"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.snappy, value: isSelected)
    }
}

// MARK: - People

/// Lays chips out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, maxWidth)
            if origin.x > 0, origin.x + width > maxWidth {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            origin.x += width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, origin.x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: origin.y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, bounds.width)
            if origin.x > bounds.minX, origin.x + width > bounds.maxX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: ProposedViewSize(width: width, height: size.height))
            origin.x += width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A person's initial in a circle, used on chips and summary cards.
struct PersonAvatar: View {
    let name: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }
}

/// A selectable name used to choose who shares an item.
struct PersonToggleChip: View {
    let title: String
    let isSelected: Bool
    let themeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .background(isSelected ? themeColor : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color(uiColor: .separator), lineWidth: 1))
            .contentShape(Capsule())
            .animation(.snappy(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("share-chip-\(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension UIApplication {
    /// Ends editing in whichever field is focused, including fields owned by
    /// shared subviews that a parent's focus state can't see.
    static func dismissKeyboard() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
