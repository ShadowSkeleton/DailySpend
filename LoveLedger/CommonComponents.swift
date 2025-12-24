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
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(expense.color.opacity(0.15)).frame(width: 48, height: 48)
                Image(systemName: expense.icon).foregroundStyle(expense.color).font(.title3)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(L10n.categoryName(expense.category)).font(.body).fontWeight(.semibold)
                    
                    // ✨ 修复：使用 safeFrequency 安全访问
                    if expense.safeFrequency != .none {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.blue)
                            .padding(5)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                
                HStack(spacing: 6) {
                    if isCurrentYear {
                        Text(expense.date.formatted(.dateTime.day().month()))
                    } else {
                        Text(expense.date.formatted(.dateTime.year().month().day()))
                            .foregroundStyle(.orange)
                    }
                    if !expense.note.isEmpty { Text("·"); Text(expense.note).lineLimit(1) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("-\(expense.amount.formatted(.currency(code: L10n.currencyCode)))").roundedNumFont(size: 18, weight: .bold).foregroundStyle(.primary)
        }.padding(16)
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
