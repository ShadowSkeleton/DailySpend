import SwiftUI
import Combine

enum SplitBasketFocusField: Hashable {
    case itemName, itemPrice, tax
}

/// Splits a bill item by item. Everyone's items live in one list; tapping
/// names on an item chooses who shares it, so a personal item is simply an
/// item with one name selected.
struct SplitBillBasketView: View {
    var themeColor: Color
    @Binding var resetTrigger: Bool
    var onUpdateReceiptData: ((ReceiptData) -> Void)?
    var onRequestShare: (() -> Void)?
    var isPreparingShare = false

    @StateObject private var session = SplitSession()
    @State private var scanner = ReceiptScanController()
    @State private var scanStatus = ReceiptIntelligenceStatus.current
    @State private var scannedDraft: ReceiptDraft?
    @State private var draftAwaitingChoice: ReceiptDraft?

    // UI State
    @State private var expandedPersonID: UUID?
    @State private var personEditor: PersonEditor?
    @State private var personNameDraft = ""

    // New Item Input State
    @State private var newItemName = ""
    @State private var newItemPrice: Double?
    @FocusState private var focusedField: SplitBasketFocusField?

    // Added state to track which person is currently recording
    @State private var recordingPerson: SplitPerson?

    private enum PersonEditor: Identifiable {
        case add
        case rename(SplitPerson)

        var id: String {
            switch self {
            case .add: "add"
            case .rename(let person): person.id.uuidString
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                scanSection
                peopleSection
                itemsSection
                totalsSection
                summarySection
                exportSection
            }
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                KeyboardDismissButton {
                    focusedField = nil
                    UIApplication.dismissKeyboard()
                }
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
                prefilledDate: scannedDraft?.date,
                onSave: {
                    recordingPerson = nil
                }
            )
        }
        .receiptScanning(scanner, themeColor: themeColor)
        .confirmationDialog(
            L10n.isZh ? "已有项目" : "This bill already has items",
            isPresented: Binding(get: { draftAwaitingChoice != nil }, set: { if !$0 { draftAwaitingChoice = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.isZh ? "替换现有项目" : "Replace Items", role: .destructive) {
                if let draft = draftAwaitingChoice { apply(draft, replacingItems: true) }
            }
            Button(L10n.isZh ? "添加到现有项目" : "Add to Items") {
                if let draft = draftAwaitingChoice { apply(draft, replacingItems: false) }
            }
            Button(L10n.cancel, role: .cancel) { draftAwaitingChoice = nil }
        } message: {
            Text(L10n.isZh ? "要用收据中的项目替换现有项目，还是添加到列表中？" : "Replace the current items with this receipt, or add its items to the list?")
        }
        .alert(personEditorTitle, isPresented: Binding(get: { personEditor != nil }, set: { if !$0 { personEditor = nil } })) {
            TextField(L10n.isZh ? "名字" : "Name", text: $personNameDraft)
                .textInputAutocapitalization(.words)
            Button(L10n.cancel, role: .cancel) { personEditor = nil }
            Button(L10n.save) { commitPersonEditor() }
        }
        .onChange(of: resetTrigger) { _, shouldReset in
            if shouldReset {
                withAnimation {
                    session.reset()
                    scannedDraft = nil
                    expandedPersonID = nil
                    updateReceipt()
                }
                resetTrigger = false
            }
        }
        .onAppear {
            scanStatus = .current
            scanner.onDraft = handleScannedDraft
            updateReceipt()
        }
        .onChange(of: session.taxAmount) { _, _ in updateReceipt() }
        .onReceive(session.objectWillChange) { _ in
            DispatchQueue.main.async { updateReceipt() }
        }
    }

    // MARK: - Sections

    private var cardBackground: some ShapeStyle {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    @ViewBuilder
    private var scanSection: some View {
        if let draft = scannedDraft {
            ReceiptDraftBanner(draft: draft, context: .split, themeColor: themeColor) {
                withAnimation { scannedDraft = nil }
            }
            .padding(.horizontal)
        } else if scanStatus.canReadItems {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(themeColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.isZh ? "扫描收据" : "Scan a receipt")
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.isZh ? "自动填写项目、税和小费" : "Fill in items, tax, and tip automatically")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ReceiptScanButton(controller: scanner, themeColor: themeColor, title: L10n.isZh ? "扫描" : "Scan")
            }
            .padding(16)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        } else if scanStatus == .appleIntelligenceOff || scanStatus == .modelDownloading {
            Label(scanStatus == .appleIntelligenceOff
                  ? (L10n.isZh ? "开启 Apple 智能后，可扫描收据自动填写项目。" : "Turn on Apple Intelligence to scan receipts into items.")
                  : (L10n.isZh ? "Apple 智能下载完成后，即可扫描收据。" : "Receipt scanning will be ready when Apple Intelligence finishes downloading."),
                  systemImage: "sparkles")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.isZh ? "参与者" : "People", systemImage: "person.2.fill")
                    .font(.headline)
                Spacer()
                Text("\(session.people.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            FlowLayout(spacing: 8) {
                ForEach(session.people) { person in
                    PersonMenuChip(person: person, themeColor: themeColor, canRemove: session.canRemovePerson,
                                   onRename: {
                                       personNameDraft = person.name
                                       personEditor = .rename(person)
                                   },
                                   onRemove: {
                                       withAnimation { session.removePerson(id: person.id) }
                                   })
                }
                Button {
                    personNameDraft = ""
                    personEditor = .add
                } label: {
                    Label(L10n.isZh ? "添加" : "Add", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(themeColor)
                        .overlay(Capsule().strokeBorder(themeColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4])))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.isZh ? "添加参与者" : "Add person")
                .accessibilityIdentifier("split-add-person")
            }
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(L10n.isZh ? "项目" : "Items", systemImage: "list.bullet.rectangle.portrait.fill")
                        .font(.headline)
                    Spacer()
                    if !session.items.isEmpty {
                        Text(session.sessionSubtotal.formatted(.currency(code: L10n.currencyCode)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(L10n.isZh ? "点选名字来选择谁分摊每一项。只选一人即为个人项目。" : "Tap names to choose who shares each item. One name makes it personal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            ForEach(session.items) { item in
                Divider().padding(.leading, 16)
                SplitItemRow(item: item, session: session, themeColor: themeColor) {
                    withAnimation { session.removeItem(id: item.id) }
                }
            }

            Divider()
            // Add Item Input
            HStack(spacing: 12) {
                TextField(L10n.isZh ? "项目名称" : "Item name", text: $newItemName)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .itemName)
                    .onSubmit { focusedField = .itemPrice }
                    .accessibilityIdentifier("split-item-name")

                HStack(spacing: 2) {
                    Text(L10n.currencySymbol).font(.caption).foregroundStyle(.secondary)
                    TextField("0", value: $newItemPrice, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .itemPrice)
                        .frame(width: 64)
                        .accessibilityLabel(L10n.isZh ? "项目价格" : "Item price")
                        .accessibilityIdentifier("split-item-price")
                }
                .padding(8)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 8))

                Button(action: addItem) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundStyle(themeColor)
                }
                .disabled(newItemPrice.map { !ExpenseInputValidator.isValidLineItemAmount($0) } ?? true)
                .accessibilityLabel(L10n.isZh ? "添加项目" : "Add item")
                .accessibilityIdentifier("split-add-item")
            }
            .padding(16)
            .background(Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.3))
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var totalsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Label(L10n.isZh ? "税费" : "Tax", systemImage: "building.columns.fill")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Text(L10n.currencySymbol).foregroundStyle(.secondary)
                    TextField("0", value: $session.taxAmount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .tax)
                        .accessibilityLabel(L10n.isZh ? "税费金额" : "Tax amount")
                }
                .frame(width: 110)
                .padding(8)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            TipSelector(selection: $session.tipSelection,
                        customPercentage: $session.customTipPercentage,
                        fixedAmount: $session.customFixedTip,
                        tipAmount: session.totalTipAmount,
                        themeColor: themeColor)

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
                    .contentTransition(.numericText())
            }
        }
        .padding(20)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.isZh ? "每人应付" : "Each Person Pays")
                .font(.headline)
                .padding(.horizontal, 4)
            ForEach(session.people) { person in
                PersonTotalCard(
                    person: person,
                    session: session,
                    isExpanded: expandedPersonID == person.id,
                    themeColor: themeColor,
                    canRecord: session.isReadyToSettle,
                    onToggle: {
                        withAnimation(.snappy) {
                            expandedPersonID = expandedPersonID == person.id ? nil : person.id
                        }
                    },
                    onRecord: {
                        UIApplication.dismissKeyboard()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            // Use the freshest computed value when the sheet opens.
                            recordingPerson = person
                        }
                    }
                )
            }
        }
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

    private func addItem() {
        guard let price = newItemPrice,
              ExpenseInputValidator.isValidLineItemAmount(price) else { return }
        withAnimation { session.addItem(name: newItemName, price: price) }
        newItemName = ""
        newItemPrice = nil
        focusedField = .itemName
    }

    private var personEditorTitle: String {
        switch personEditor {
        case .rename: L10n.isZh ? "修改名字" : "Rename"
        default: L10n.isZh ? "添加参与者" : "Add Person"
        }
    }

    private func commitPersonEditor() {
        let name = personNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch personEditor {
        case .add:
            withAnimation { session.addPerson(name: name.isEmpty ? session.nextPersonPlaceholder : name) }
        case .rename(let person):
            if !name.isEmpty { session.renamePerson(id: person.id, to: name) }
        case nil:
            break
        }
        personEditor = nil
    }

    private func handleScannedDraft(_ draft: ReceiptDraft) {
        guard !draft.items.isEmpty else {
            scanner.errorMessage = L10n.isZh
                ? "没能从这张收据中读取项目。你可以用“快速平分”按总额分账，或手动添加项目。"
                : "Items couldn’t be read from this receipt. Use Quick Split with the total, or add items yourself."
            return
        }
        if session.items.isEmpty {
            apply(draft, replacingItems: true)
        } else {
            draftAwaitingChoice = draft
        }
    }

    private func apply(_ draft: ReceiptDraft, replacingItems: Bool) {
        withAnimation {
            session.apply(draft, replacingItems: replacingItems)
            scannedDraft = draft
        }
        draftAwaitingChoice = nil
    }

    // MARK: - Receipt Update (Detailed Version)

    private func updateReceipt() {
        onUpdateReceiptData?(session.makeReceiptData())
    }
}

// MARK: - Subcomponents

private struct PersonMenuChip: View {
    @ObservedObject var person: SplitPerson
    let themeColor: Color
    let canRemove: Bool
    let onRename: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Menu {
            Button(action: onRename) {
                Label(L10n.isZh ? "修改名字" : "Rename", systemImage: "pencil")
            }
            Button(role: .destructive, action: onRemove) {
                Label(L10n.isZh ? "移除" : "Remove", systemImage: "person.badge.minus")
            }
            .disabled(!canRemove)
        } label: {
            HStack(spacing: 6) {
                PersonAvatar(name: displayName, color: themeColor.opacity(0.85), size: 22)
                Text(displayName)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .tint(.primary)
        .accessibilityLabel(displayName)
        .accessibilityHint(L10n.isZh ? "修改名字或移除" : "Rename or remove")
    }

    private var displayName: String {
        let trimmed = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (L10n.isZh ? "未命名" : "Guest") : trimmed
    }
}

struct SplitItemRow: View {
    let item: SplitItem
    @ObservedObject var session: SplitSession
    let themeColor: Color
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.isEmpty ? (L10n.isZh ? "项目" : "Item") : item.name)
                        .fontWeight(.medium)
                    Text(priceCaption)
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.6))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.isZh ? "删除项目" : "Delete item")
            }

            FlowLayout(spacing: 6) {
                if session.people.count > 1 {
                    PersonToggleChip(title: L10n.isZh ? "所有人" : "Everyone",
                                     isSelected: session.isEveryoneIncluded(in: item),
                                     themeColor: themeColor) {
                        session.toggleEveryone(inItem: item.id)
                    }
                }
                ForEach(session.people) { person in
                    PersonToggleChip(title: displayName(person),
                                     isSelected: item.involvedPersonIDs.contains(person.id),
                                     themeColor: themeColor) {
                        session.togglePerson(person.id, inItem: item.id)
                    }
                }
            }
        }
        .padding(16)
    }

    private var priceCaption: String {
        let price = item.price.formatted(.currency(code: L10n.currencyCode))
        let count = session.peopleIncluded(in: item).count
        guard count > 1 else { return price }
        let shares = Money.splitEvenly(Money(item.price), among: count)
        let each = shares[0].amount.formatted(.currency(code: L10n.currencyCode))
        // When cents don't divide evenly the first share is one cent larger.
        let prefix = shares.first == shares.last ? "" : "~"
        return L10n.isZh ? "\(price) · 每人 \(prefix)\(each)" : "\(price) · \(prefix)\(each) each"
    }

    private func displayName(_ person: SplitPerson) -> String {
        let trimmed = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (L10n.isZh ? "未命名" : "Guest") : trimmed
    }
}

struct PersonTotalCard: View {
    @ObservedObject var person: SplitPerson
    @ObservedObject var session: SplitSession
    var isExpanded: Bool
    var themeColor: Color
    var canRecord: Bool
    var onToggle: () -> Void
    var onRecord: () -> Void

    var body: some View {
        let shares = session.itemShares(for: person.id)
        VStack(spacing: 0) {
            // Header
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    PersonAvatar(name: displayName, color: themeColor.opacity(0.85), size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(shares.isEmpty
                             ? (L10n.isZh ? "暂无项目" : "No items yet")
                             : (L10n.isZh ? "\(shares.count) 项" : "\(shares.count) \(shares.count == 1 ? "item" : "items")"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(session.finalTotal(for: person).formatted(.currency(code: L10n.currencyCode)))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.isZh ? "显示明细" : "Shows this person’s items")

            // Expanded
            if isExpanded {
                Divider()
                VStack(spacing: 0) {
                    ForEach(shares) { share in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(share.name.isEmpty ? (L10n.isZh ? "项目" : "Item") : share.name)
                                    .font(.subheadline)
                                if share.isShared {
                                    Text(L10n.isZh ? "\(share.peopleCount) 人分摊" : "Shared by \(share.peopleCount)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(share.share.amount.formatted(.currency(code: L10n.currencyCode)))
                                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    let extras = session.taxAndTip(for: person)
                    if extras > 0 {
                        HStack {
                            Text(L10n.isZh ? "税费与小费" : "Tax & tip")
                                .font(.subheadline).italic()
                                .foregroundStyle(themeColor)
                            Spacer()
                            Text(extras.formatted(.currency(code: L10n.currencyCode)))
                                .font(.subheadline).monospacedDigit().foregroundStyle(themeColor)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    Divider().padding(.top, 4)

                    HStack {
                        Spacer()
                        Button(action: onRecord) {
                            HStack {
                                Image(systemName: "square.and.pencil")
                                Text(L10n.isZh ? "记录为支出" : "Record as Expense")
                            }
                            .font(.subheadline).fontWeight(.bold)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(themeColor.opacity(0.1))
                            .foregroundStyle(themeColor)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canRecord)
                        .opacity(canRecord ? 1 : 0.4)
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var displayName: String {
        let trimmed = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (L10n.isZh ? "未命名" : "Guest") : trimmed
    }
}
