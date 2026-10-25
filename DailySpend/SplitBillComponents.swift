import SwiftUI
import UIKit

// MARK: - Tip

/// The tip control shared by both split modes. "Custom" holds both a custom
/// percentage and a fixed amount, which keeps the choices on two short rows.
struct TipSelector: View {
    @Binding var selection: Int
    @Binding var customPercentage: Int?
    @Binding var fixedAmount: Double?
    let tipAmount: Double
    let themeColor: Color

    private var isCustom: Bool {
        selection == TipPreset.customPercentage || selection == TipPreset.fixedAmount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.isZh ? "小费" : "Tip", systemImage: "heart.circle.fill")
                    .font(.headline)
                Spacer()
                Text(tipAmount.formatted(.currency(code: L10n.currencyCode)))
                    .foregroundStyle(themeColor)
                    .fontWeight(.bold)
                    .contentTransition(.numericText())
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                TipOptionButton(text: L10n.isZh ? "不加" : "None", isSelected: selection == TipPreset.none, color: themeColor) {
                    selection = TipPreset.none
                }
                .accessibilityIdentifier("tip-none")
                ForEach(TipPreset.percentages, id: \.self) { percentage in
                    TipOptionButton(text: "\(percentage)%", isSelected: selection == percentage, color: themeColor) {
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
        }
        .animation(.snappy, value: isCustom)
    }
}

// Equal tiles keep choices immediately visible and prevent short labels from
// collapsing into circles.
struct TipOptionButton: View {
    let text: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .accessibilityLabel(text)
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
            .background(isSelected ? themeColor : Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
