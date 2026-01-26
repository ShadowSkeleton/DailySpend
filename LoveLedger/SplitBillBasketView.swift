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
    var onRecord: ((Double, String) -> Void)?
    var onUpdateReceiptData: ((ReceiptData) -> Void)?
    var onRequestShare: (() -> Void)?
    
    @StateObject private var session = SplitSession()
    
    // UI State
    @State private var editingPersonID: UUID?
    @State private var isSharedSectionExpanded = true
    @State private var showResetAlert = false
    
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
        .background(Color(uiColor: .systemGroupedBackground))
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
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
        .onChange(of: resetTrigger) { newValue in
            if newValue {
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
                    Text(L10n.isZh ? "共享菜品 (全员平分)" : "Shared Items (Split by All)")
                        .font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isSharedSectionExpanded ? 90 : 0))
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
            }
            
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
                        .disabled(newSharedPrice == nil)
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
                    }
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
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach([10, 15, 18, 20], id: \.self) { pct in
                            TipCapsule(text: "\(pct)%", isSelected: session.tipSelection == pct, color: themeColor) {
                                session.tipSelection = pct; updateReceipt()
                            }
                        }
                        TipCapsule(text: "Custom %", isSelected: session.tipSelection == -1, color: themeColor) {
                            session.tipSelection = -1; updateReceipt()
                        }
                        TipCapsule(text: "Fixed $", isSelected: session.tipSelection == -2, color: themeColor) {
                            session.tipSelection = -2; updateReceipt()
                        }
                    }
                    .padding(.vertical, 4)
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
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(themeColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: themeColor.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 50)
    }
    
    // MARK: - Logic Methods
    
    private func addSharedItem() {
        guard let price = newSharedPrice else { return }
        session.addSharedItem(name: newSharedName, price: price)
        newSharedName = ""
        newSharedPrice = nil
        focusedField = .sharedName
        updateReceipt()
    }
    
    // MARK: - Receipt Update (Detailed Version)
    
    private func updateReceipt() {
        var items: [ReceiptItem] = []
        
        for person in session.people {
            let displayName = person.name.isEmpty ? (L10n.isZh ? "未命名" : "Guest") : person.name
            
            // 1. Header (Person Name)
            // By passing empty string as value, ReceiptView will treat this as a Header
            items.append(.text(displayName.uppercased(), ""))
            
            // 2. Personal Items
            for item in person.items {
                let itemName = item.name.isEmpty ? "Item" : item.name
                items.append(.currency("  • \(itemName)", item.price))
            }
            
            // 3. Shared Portion
            let shared = session.sharedPortion(for: person.id)
            if shared > 0 {
                items.append(.currency(L10n.isZh ? "  • 共享分摊" : "  • Shared Portion", shared))
            }
            
            // 4. Tax & Tip Share (Calculated)
            let subtotal = session.subtotal(for: person)
            let final = session.finalTotal(for: person)
            let taxAndTip = final - subtotal
            
            if taxAndTip > 0.01 {
                items.append(.currency(L10n.isZh ? "  • 税费与小费" : "  • Tax & Tip", taxAndTip))
            }
            
            // 5. Total
            items.append(.currency(L10n.isZh ? "  总计" : "  Total", final))
            
            // Note: We don't add an explicit separator here because the Header padding
            // in ReceiptView will handle the visual separation naturally.
        }

        let data = ReceiptData(
            title: L10n.isZh ? "按人分配" : "Split by Person",
            items: items,
            subtotal: session.sessionSubtotal,
            tax: session.totalTaxAmount,
            tip: session.totalTipAmount,
            total: session.grandTotal,
            footer: "Generated by LoveLedger"
        )
        onUpdateReceiptData?(data)
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
                            if let price = newItemPrice {
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
                        .disabled(newItemPrice == nil)
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
                    }
                    .padding(12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemGroupedBackground)).shadow(color: .black.opacity(0.05), radius: 5))
    }
}

// TipCapsule (shared component)
struct TipCapsule: View {
    let text: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? color : Color(uiColor: .tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? color : Color.clear, lineWidth: 1)
                )
        }
        .animation(.snappy, value: isSelected)
    }
}
