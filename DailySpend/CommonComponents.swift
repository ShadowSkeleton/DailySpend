import SwiftUI

// MARK: - Expense Row Card
struct ExpenseRowCard: View {
    let expense: Expense
    let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    
    // 辅助计算属性：检查是否是当前年份
    var isCurrentYear: Bool {
        Calendar.current.component(.year, from: expense.date) == Calendar.current.component(.year, from: Date())
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(expense.color.opacity(0.15)).frame(width: 48, height: 48)
                Image(systemName: expense.icon).foregroundStyle(expense.color).font(.title3)
            }
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(L10n.categoryName(expense.category)).font(.body.weight(.semibold))
                        Spacer(minLength: 0)
                        amountLabel.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.categoryName(expense.category)).font(.body).fontWeight(.semibold)
                        amountLabel
                    }
                }

                Text(expense.date.formatted(isCurrentYear
                    ? .dateTime.day().month() : .dateTime.year().month().day()))
                    .font(.caption).foregroundStyle(.secondary)
                if expense.safeFrequency != .none || expense.isRecurringChild {
                    Label(L10n.isZh ? "定期支出" : "Recurring", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if !expense.displayNote.isEmpty {
                    Text(expense.displayNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .contentShape(Rectangle())
    }

    private var amountLabel: some View {
        Text("-\(expense.normalizedAmount.formatted(.currency(code: L10n.currencyCode)))")
            .font(.system(.headline, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.primary)
    }
}

// MARK: - Category Button
struct CategoryButton: View {
    let item: (name: String, icon: String, color: Color)
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: { action(); UISelectionFeedbackGenerator().selectionChanged() }) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(isSelected ? item.color : Color(uiColor: .tertiarySystemGroupedBackground)).frame(width: 64, height: 64).shadow(color: isSelected ? item.color.opacity(0.4) : .black.opacity(0.05), radius: isSelected ? 8 : 2, y: isSelected ? 4 : 1)
                    Image(systemName: item.icon).font(.title2).fontWeight(.semibold).foregroundStyle(isSelected ? .white : .gray)
                }
                Text(L10n.categoryName(item.name)).font(.caption).fontWeight(.medium).foregroundStyle(isSelected ? item.color : .secondary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}
