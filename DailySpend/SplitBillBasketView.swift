import SwiftUI
import Combine

// Global Enum
enum SplitBasketFocusField: Hashable {
    case sharedName, sharedPrice
    case personName(UUID), personPrice(UUID)
}

struct SplitBillBasketView: View {
    var themeColor: Color
    @Binding var resetTrigger: Bool
    var onUpdateReceiptData: ((ReceiptData) -> Void)?
    var onRequestShare: (() -> Void)?
    var isPreparingShare = false
    
    @StateObject private var session = SplitSession()
    
    // UI State
    @State private var editingPersonID: UUID?
    @State private var isSharedSectionExpanded = true
    
    // New Item Input State (Shared)
    @State private var newSharedName = ""
    @State private var newSharedPrice: Double?
    @FocusState private var focusedField: SplitBasketFocusField?
    
    // Added state to track which person is currently recording
    @State private var recordingPerson: SplitPerson?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Removed Quick Add Section
                
                sharedPoolSection
                    .padding(.top, 20) // Added top padding since Quick Add is gone
                
                peopleListSection
                totalsSection
                exportSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                KeyboardDismissButton { focusedField = nil }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // Sheet for recording expense per person
        .sheet(item: $recordingPerson) { person in
            AddExpenseView(
                themeColor: themeColor,
                prefilledAmount: session.finalTotal(for: person),
                prefilledNote: session.generateNote(for: person),
                prefilledCategory: "Food",
                onSave: {
                    recordingPerson = nil
                }
            )
        }
        .onChange(of: resetTrigger) { _, shouldReset in
            if shouldReset {
                withAnimation {
                    session.reset()
                    updateReceipt()
                }
                resetTrigger = false
            }
        }
        .onAppear {
            updateReceipt()
        }
        .onChange(of: session.taxAmount) { _, _ in updateReceipt() }
        .onReceive(session.objectWillChange) { _ in
            DispatchQueue.main.async { updateReceipt() }
        }
    }
    
    // MARK: - Sections
    
    private var sharedPoolSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { isSharedSectionExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "person.3.sequence.fill")
                        .foregroundStyle(themeColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.isZh ? "共享项目" : "Shared Items")
                            .font(.headline).foregroundStyle(.primary)
                        Text(L10n.isZh ? "选择谁参与分摊每一项" : "Choose who shares each item.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isSharedSectionExpanded ? 90 : 0))
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .accessibilityLabel(L10n.isZh ? "共享项目" : "Shared items")
            .accessibilityHint(L10n.isZh ? "展开后可添加项目并选择参与者" : "Expand to add items and choose participants.")
            
            if isSharedSectionExpanded {
                Divider()
                VStack(spacing: 0) {
                    ForEach(session.sharedItems) { item in
                        SharedItemRow(item: item, session: session, people: session.people, themeColor: themeColor) {
                            session.removeSharedItem(id: item.id)
                            updateReceipt()
                        } updateReceipt: {
                            updateReceipt()
                        }
                        Divider().padding(.leading, 16)
                    }
                    
                    // Add Shared Item Input
                    HStack(spacing: 12) {
                        TextField(L10n.isZh ? "共享菜品名" : "Shared Item Name", text: $newSharedName)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .sharedName)
                            .onSubmit { focusedField = .sharedPrice }
                        
                        HStack(spacing: 2) {
                            Text(L10n.currencySymbol).font(.caption).foregroundStyle(.secondary)
                            TextField("0", value: $newSharedPrice, format: .number)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .sharedPrice)
                                .frame(width: 60)
                        }
                        .padding(8)
                        .background(Color(uiColor: .systemBackground))
                        .cornerRadius(8)
                        
                        Button(action: addSharedItem) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                                .foregroundStyle(themeColor)
                        }
                        .disabled(newSharedPrice.map { !ExpenseInputValidator.isValidLineItemAmount($0) } ?? true)
                        .accessibilityLabel(L10n.isZh ? "添加共享项目" : "Add shared item")
                    }
                    .padding()
                    .background(Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.3))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemGroupedBackground)).shadow(color: .black.opacity(0.05), radius: 5))
        .padding(.horizontal)
    }
    
    private var peopleListSection: some View {
        VStack(spacing: 16) {
            ForEach(session.people) { person in
                PersonBasketCard(
                    person: person,
                    session: session,
                    isEditing: editingPersonID == person.id,
                    themeColor: themeColor,
                    focusedField: $focusedField,
                    onToggleEdit: {
                        withAnimation {
                            editingPersonID = (editingPersonID == person.id) ? nil : person.id
                        }
                    },
                    onAddItem: { name, price in
                        session.addPersonalItem(to: person.id, name: name, price: price)
                        updateReceipt()
                    },
                    onRemoveItem: { itemID in
                        session.removePersonalItem(from: person.id, itemID: itemID)
                        updateReceipt()
                    },
                    onDeletePerson: {
                        withAnimation {
                            session.removePerson(id: person.id)
                            updateReceipt()
                        }
                    },
                    onRecord: {
                        // Directly assign recordingPerson to present the AddExpenseView sheet with fresh data
                        recordingPerson = person
                    },
                    canDeletePerson: session.canRemovePerson,
                    canRecord: session.isReadyToSettle
                )
            }
            
            Button(action: {
                withAnimation {
                    session.addPerson(name: "")
                    updateReceipt()
                    if let last = session.people.last { editingPersonID = last.id }
                }
            }) {
                HStack {
                    Image(systemName: "person.badge.plus")
                    Text(L10n.isZh ? "添加参与者" : "Add Person to Bill")
                }
                .font(.headline)
                .foregroundStyle(themeColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
            }
        }
        .padding(.horizontal)
    }
    
    private var totalsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Label(L10n.isZh ? "税费" : "Tax", systemImage: "building.columns.fill")
                    .font(.headline)
                Spacer()
                TextField("0", value: $session.taxAmount, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 50)
                    .padding(8)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .cornerRadius(8)
            }
            
            Divider()
            
            // Tip Selector UI
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(L10n.isZh ? "小费" : "Tip", systemImage: "heart.fill")
                        .font(.headline)
                    Spacer()
                    Text(session.totalTipAmount.formatted(.currency(code: L10n.currencyCode)))
                        .foregroundStyle(themeColor)
                        .fontWeight(.bold)
                }
                
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach([10, 15, 18, 20], id: \.self) { pct in
                        TipOptionButton(text: "\(pct)%", isSelected: session.tipSelection == pct, color: themeColor) {
                            session.tipSelection = pct; updateReceipt()
                        }
                    }
                    TipOptionButton(text: L10n.isZh ? "自定比例" : "Custom %", isSelected: session.tipSelection == -1, color: themeColor) {
                        session.tipSelection = -1; updateReceipt()
                    }
                    TipOptionButton(text: L10n.isZh ? "固定金额" : "Fixed \(L10n.currencySymbol)", isSelected: session.tipSelection == -2, color: themeColor) {
                        session.tipSelection = -2; updateReceipt()
                    }
                }
                
                // Custom Inputs
                if session.tipSelection == -1 {
                    HStack {
                        Text(L10n.isZh ? "输入比例" : "Enter %").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        TextField("20", value: $session.customTipPercentage, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .padding(8)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .cornerRadius(8)
                        Text("%")
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else if session.tipSelection == -2 {
                    HStack {
                        Text(L10n.isZh ? "输入金额" : "Enter Amount").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 2) {
                            Text(L10n.currencySymbol).foregroundStyle(.secondary)
                            TextField("5.00", value: $session.customFixedTip, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        .padding(8)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .cornerRadius(8)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            
            Divider()

            if let message = session.settlementValidationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(message)
            }
            
            HStack {
                Text(L10n.isZh ? "总计" : "Grand Total")
                    .font(.title3).fontWeight(.bold)
                Spacer()
                Text(session.grandTotal.formatted(.currency(code: L10n.currencyCode)))
                    .font(.title2).fontWeight(.heavy)
                    .foregroundStyle(themeColor)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    private var exportSection: some View {
        Button(action: { onRequestShare?() }) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text(L10n.isZh ? "导出收据" : "Share Receipt")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(themeColor)
        .disabled(!session.isReadyToSettle || isPreparingShare)
        .opacity(session.isReadyToSettle && !isPreparingShare ? 1 : 0.45)
        .accessibilityLabel(L10n.isZh ? "分享分账收据" : "Share split receipt")
        .accessibilityHint(isPreparingShare
            ? (L10n.isZh ? "正在准备收据" : "Preparing receipt")
            : (session.settlementValidationMessage ?? "Shares the completed receipt."))
        .padding(.horizontal, 24)
        .padding(.bottom, 50)
    }
    
    // MARK: - Logic Methods
    
    private func addSharedItem() {
        guard let price = newSharedPrice,
              ExpenseInputValidator.isValidLineItemAmount(price) else { return }
        session.addSharedItem(name: newSharedName, price: price)
        newSharedName = ""
        newSharedPrice = nil
        focusedField = .sharedName
        updateReceipt()
    }
    
    // MARK: - Receipt Update (Detailed Version)
    
    private func updateReceipt() {
        onUpdateReceiptData?(session.makeReceiptData())
    }
}

// MARK: - Subcomponents

struct SharedItemRow: View {
    let item: SharedItem
    @ObservedObject var session: SplitSession
    let people: [SplitPerson]
    let themeColor: Color
    var onDelete: () -> Void
    var updateReceipt: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(item.name.isEmpty ? "Shared Item" : item.name)
                        .fontWeight(.medium)
                    Text(item.price.formatted(.currency(code: L10n.currencyCode)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.6))
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            // Avatar Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(people) { person in
                        let isSelected = item.involvedPersonIDs.contains(person.id)
                        Button(action: {
                            session.togglePersonInSharedItem(itemID: item.id, personID: person.id)
                            updateReceipt()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? themeColor : Color.gray.opacity(0.2))
                                    .frame(width: 32, height: 32)
                                Text(String(person.name.prefix(1)).uppercased())
                                    .font(.caption2).fontWeight(.bold)
                                    .foregroundStyle(isSelected ? .white : .gray)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
}

struct PersonBasketCard: View {
    @ObservedObject var person: SplitPerson
    @ObservedObject var session: SplitSession
    var isEditing: Bool
    var themeColor: Color
    var focusedField: FocusState<SplitBasketFocusField?>.Binding
    var onToggleEdit: () -> Void
    var onAddItem: (String, Double) -> Void
    var onRemoveItem: (UUID) -> Void
    var onDeletePerson: () -> Void
    var onRecord: () -> Void
    var canDeletePerson: Bool
    var canRecord: Bool
    
    @State private var newItemName = ""
    @State private var newItemPrice: Double?
    
    var sharedPortion: Double {
        session.sharedPortion(for: person.id)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggleEdit) {
                HStack(spacing: 12) {
                    Text(String(person.name.prefix(1)).uppercased())
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(themeColor.opacity(0.8))
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if isEditing {
                            TextField("Name", text: $person.name).font(.headline)
                        } else {
                            Text(person.name.isEmpty ? "Guest" : person.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(session.finalTotal(for: person).formatted(.currency(code: L10n.currencyCode)))
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        let count = person.items.count
                        let share = sharedPortion
                        if count > 0 || share > 0 {
                            Text("\(count) items" + (share > 0 ? " + shared" : ""))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isEditing ? 90 : 0))
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
            }
            
            // Expanded
            if isEditing {
                Divider()
                VStack(spacing: 0) {
                    // 1. Personal Items
                    if person.items.isEmpty && sharedPortion == 0 {
                        Text(L10n.isZh ? "暂无消费" : "No items")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(person.items) { item in
                            HStack {
                                Text(item.name.isEmpty ? "Item" : item.name).font(.subheadline)
                                Spacer()
                                Text(item.price.formatted(.currency(code: L10n.currencyCode)))
                                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                Button(action: { onRemoveItem(item.id) }) {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.4))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            Divider().padding(.leading, 16)
                        }
                        
                        if sharedPortion > 0 {
                            HStack {
                                Text(L10n.isZh ? "共享分摊" : "Shared Portion")
                                    .font(.subheadline).italic()
                                    .foregroundStyle(themeColor)
                                Spacer()
                                Text(sharedPortion.formatted(.currency(code: L10n.currencyCode)))
                                    .font(.subheadline).monospacedDigit().foregroundStyle(themeColor)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(themeColor.opacity(0.05))
                            Divider()
                        }
                    }
                    
                    // 2. Add Personal Item
                    HStack(spacing: 12) {
                        TextField(L10n.isZh ? "个人菜品" : "Personal Item", text: $newItemName)
                            .font(.subheadline)
                            .submitLabel(.next)
                            .focused(focusedField, equals: .personName(person.id))
                            .onSubmit { focusedField.wrappedValue = .personPrice(person.id) }
                        
                        HStack(spacing: 2) {
                            Text(L10n.currencySymbol).font(.caption).foregroundStyle(.secondary)
                            TextField("0", value: $newItemPrice, format: .number)
                                .keyboardType(.decimalPad)
                                .focused(focusedField, equals: .personPrice(person.id))
                                .frame(width: 60)
                        }
                        .padding(6)
                        .background(Color(uiColor: .systemBackground))
                        .cornerRadius(6)
                        
                        Button(action: {
                            if let price = newItemPrice,
                               ExpenseInputValidator.isValidLineItemAmount(price) {
                                onAddItem(newItemName, price)
                                newItemName = ""
                                newItemPrice = nil
                                focusedField.wrappedValue = .personName(person.id)
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(themeColor)
                        }
                        .disabled(newItemPrice.map { !ExpenseInputValidator.isValidLineItemAmount($0) } ?? true)
                    }
                    .padding(16)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.3))
                    
                    Divider()
                    
                    // 3. Actions Row
                    HStack {
                        Button(action: onDeletePerson) {
                            HStack {
                                Image(systemName: "trash")
                                Text(L10n.isZh ? "删除" : "Delete")
                            }
                            .font(.caption).foregroundStyle(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.1)).clipShape(Capsule())
                        }
                        .disabled(!canDeletePerson)
                        .opacity(canDeletePerson ? 1 : 0.4)
                        
                        Spacer()
                        
                        Button(action: {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                // Use freshest computed value at the moment of record button tap
                                onRecord()
                            }
                        }) {
                            HStack {
                                Image(systemName: "square.and.pencil")
                                Text(L10n.isZh ? "记录" : "Record")
                            }
                            .font(.caption).fontWeight(.bold)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(themeColor.opacity(0.1))
                            .foregroundStyle(themeColor)
                            .clipShape(Capsule())
                        }
                        .disabled(!canRecord)
                        .opacity(canRecord ? 1 : 0.4)
                    }
                    .padding(12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemGroupedBackground)).shadow(color: .black.opacity(0.05), radius: 5))
    }
}

// Shared tip-control design for both split modes. Equal tiles keep choices
// immediately visible and prevent short labels from collapsing into circles.
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
