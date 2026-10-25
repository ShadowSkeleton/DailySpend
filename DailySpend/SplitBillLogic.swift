import Foundation
import SwiftUI
import Combine

// MARK: - Receipt Value Type (NEW)
// Supports multiple display formats for receipt items

enum ReceiptValueType: Equatable {
    case currency(Double)
    case integer(Int)
    case text(String)
    
    var displayString: String {
        switch self {
        case .currency(let amount):
            return amount.formatted(.currency(code: L10n.currencyCode))
        case .integer(let value):
            return "\(value)"
        case .text(let str):
            return str
        }
    }
}

// MARK: - Receipt Item (NEW)

struct ReceiptItem: Equatable {
    enum Style: Equatable { case standard, sharedSubtotal, detail, personTotal }
    let label: String
    let value: ReceiptValueType
    var style: Style = .standard
    var subtitle: String? = nil
    var participants: [String] = []
    
    // Convenience initializers
    static func currency(_ label: String, _ amount: Double) -> ReceiptItem {
        ReceiptItem(label: label, value: .currency(amount))
    }
    
    static func integer(_ label: String, _ count: Int) -> ReceiptItem {
        ReceiptItem(label: label, value: .integer(count))
    }
    
    static func text(_ label: String, _ text: String) -> ReceiptItem {
        ReceiptItem(label: label, value: .text(text))
    }
}

nonisolated enum SplitNote {
    /// Recognize only the exact old generated equal-share templates. Arbitrary
    /// user text and unequal allocations stay verbatim; storage is untouched.
    static func readableLegacyNote(_ note: String) -> String {
        for (prefix, divider, repeated, heading) in [
            ("Split: Total ", "; my share ", ". Each pays ", "My share "),
            ("AA分账: 总额", "；我的份额 ", "。每人支付 ", "我的份额 ")
        ] {
            guard note.hasPrefix(prefix) else { continue }
            let parts = note.components(separatedBy: repeated)
            guard parts.count == 2 else { continue }
            let summary = parts[0].components(separatedBy: divider)
            guard summary.count == 2, summary[1] == parts[1], !summary[1].isEmpty else { continue }
            return "\(summary[0])\n\(heading)\(summary[1])"
        }
        return note
    }

    static func quick(total: Money, share: Money, people: Int) -> String {
        let totalText = total.amount.formatted(.currency(code: L10n.currencyCode))
        let shareText = share.amount.formatted(.currency(code: L10n.currencyCode))
        return L10n.isZh
            ? "\(people) 人分账 · 总额 \(totalText)\n我的份额 \(shareText)"
            : "Split · \(people) \(people == 1 ? "person" : "people") · Total \(totalText)\nMy share \(shareText)"
    }
}

nonisolated struct ItemShare: Identifiable {
    let id: UUID
    let name: String
    let total: Money
    let share: Money
    let peopleCount: Int
    let participantNames: [String]

    var isShared: Bool { peopleCount > 1 }
}

// MARK: - Shared Models

struct ReceiptData: Equatable {
    var title: String
    var items: [ReceiptItem]
    var subtotal: Double?
    var tax: Double?
    var tip: Double
    var total: Double
    var footer: String
}

/// One line on the bill. An item with one person is theirs alone; with
/// several people its price is divided between them to the cent.
struct SplitItem: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var price: Double
    var involvedPersonIDs: [UUID]
}

/// Tip choices shared by both split modes. Positive values are percentages.
nonisolated enum TipPreset {
    static let none = 0
    static let customPercentage = -1
    static let fixedAmount = -2
    static let percentages = [10, 15, 18, 20]

    /// Tipping is customary in the United States and Canada. Elsewhere a
    /// default tip would add money nobody intended to pay.
    static var defaultSelection: Int {
        ["US", "CA"].contains(Locale.current.region?.identifier ?? "") ? 15 : none
    }
}

// These are UI-facing state containers, but their values and calculation
// helpers don't require actor isolation. Opting them out of the project's
// default MainActor isolation also avoids an iOS 26.3 runtime crash while
// tearing down @Published child objects in unit tests.
nonisolated class SplitPerson: Identifiable, ObservableObject {
    let id = UUID()
    @Published var name: String
    
    var friendID: UUID?
    
    init(name: String, friendID: UUID? = nil) {
        self.name = name
        self.friendID = friendID
    }
}

// MARK: - The Session Logic Engine

nonisolated class SplitSession: ObservableObject {
    @Published var people: [SplitPerson] = []
    @Published var items: [SplitItem] = []
    @Published var taxAmount: Double?
    
    @Published var tipSelection: Int = TipPreset.defaultSelection
    @Published var customTipPercentage: Int?
    @Published var customFixedTip: Double?

    /// The store name from a scanned receipt, used in notes and the export.
    @Published var merchant: String?
    
    init() {
        addPerson(name: Self.defaultFirstPersonName)
    }

    static var defaultFirstPersonName: String {
        L10n.isZh ? "我" : "Me"
    }
    
    // MARK: - Person Management
    
    func addPerson(name: String, friendID: UUID? = nil) {
        let newPerson = SplitPerson(name: name, friendID: friendID)
        // Items shared by everyone stay shared by everyone, so people can be
        // added after scanning without reassigning every line.
        let everyone = Set(people.map(\.id))
        for index in items.indices where !everyone.isEmpty && Set(items[index].involvedPersonIDs) == everyone {
            items[index].involvedPersonIDs.append(newPerson.id)
        }
        people.append(newPerson)
        objectWillChange.send()
    }

    /// A placeholder that still tells people apart when no name is typed.
    var nextPersonPlaceholder: String {
        L10n.isZh ? "第 \(people.count + 1) 人" : "Person \(people.count + 1)"
    }

    func renamePerson(id: UUID, to name: String) {
        guard let person = people.first(where: { $0.id == id }) else { return }
        person.name = name
        objectWillChange.send()
    }
    
    func removePerson(id: UUID) {
        // A bill always needs at least one participant. Keeping that invariant
        // prevents an accidental delete from making every total unrecordable.
        guard people.count > 1 else { return }
        people.removeAll { $0.id == id }
        for index in items.indices {
            items[index].involvedPersonIDs.removeAll { $0 == id }
        }
        objectWillChange.send()
    }
    
    // MARK: - Item Management

    /// Adds an item shared by everyone unless specific people are given.
    func addItem(name: String, price: Double, assignedTo personIDs: [UUID]? = nil) {
        items.append(SplitItem(name: name, price: price, involvedPersonIDs: personIDs ?? people.map(\.id)))
        objectWillChange.send()
    }
    
    func addPersonalItem(to personID: UUID, name: String, price: Double) {
        guard people.contains(where: { $0.id == personID }) else { return }
        addItem(name: name, price: price, assignedTo: [personID])
    }
    
    func addSharedItem(name: String, price: Double) {
        addItem(name: name, price: price)
    }
    
    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    func togglePerson(_ personID: UUID, inItem itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var ids = items[index].involvedPersonIDs
        
        if ids.contains(personID) {
            ids.removeAll { $0 == personID }
        } else {
            ids.append(personID)
        }
        
        items[index].involvedPersonIDs = ids
        objectWillChange.send()
    }

    func isEveryoneIncluded(in item: SplitItem) -> Bool {
        peopleIncluded(in: item).count == people.count
    }

    /// Selects everyone, or clears the item when everyone was already chosen.
    func toggleEveryone(inItem itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].involvedPersonIDs = isEveryoneIncluded(in: items[index]) ? [] : people.map(\.id)
        objectWillChange.send()
    }

    /// Fills the bill from a scanned receipt. Items start shared by everyone;
    /// a printed tip becomes a fixed tip so nothing is counted twice.
    func apply(_ draft: ReceiptDraft, replacingItems: Bool) {
        let everyone = people.map(\.id)
        let newItems = draft.itemsForSplit().map {
            SplitItem(name: $0.name, price: $0.price.amount, involvedPersonIDs: everyone)
        }
        let scannedTax = draft.taxForSplit ?? .zero
        if replacingItems {
            items = newItems
            taxAmount = scannedTax > .zero ? scannedTax.amount : nil
        } else {
            items += newItems
            let combined = money(taxAmount ?? 0) + scannedTax
            taxAmount = combined > .zero ? combined.amount : nil
        }
        if let tip = draft.tip, tip > .zero {
            let combined = replacingItems || tipSelection != TipPreset.fixedAmount
                ? tip : money(customFixedTip ?? 0) + tip
            tipSelection = TipPreset.fixedAmount
            customFixedTip = combined.amount
        } else if replacingItems && draft.expectsNoTip {
            tipSelection = TipPreset.none
        }
        if replacingItems || merchant == nil { merchant = draft.merchant }
        objectWillChange.send()
    }
    
    // MARK: - Robust Math Engine

    private func money(_ value: Double) -> Money {
        Money(value)
    }

    func peopleIncluded(in item: SplitItem) -> [SplitPerson] {
        // Always use the visible people order so an unavoidable extra cent is
        // allocated predictably and the same on every redraw.
        people.filter { item.involvedPersonIDs.contains($0.id) }
    }

    var hasUnallocatedItems: Bool {
        items.contains { peopleIncluded(in: $0).isEmpty }
    }

    var hasInvalidAmounts: Bool {
        taxAmount.map { !ExpenseInputValidator.isValidLineItemAmount($0) } ?? false
        || customFixedTip.map { !ExpenseInputValidator.isValidLineItemAmount($0) } ?? false
        || customTipPercentage.map { $0 < 0 } ?? false
        || items.contains { !ExpenseInputValidator.isValidLineItemAmount($0.price) }
    }

    var settlementValidationMessage: String? {
        if people.isEmpty { return L10n.isZh ? "请至少保留一位参与者" : "Add at least one participant." }
        if hasInvalidAmounts { return L10n.isZh ? "请输入大于 0 的金额" : "Enter amounts greater than zero." }
        if hasUnallocatedItems { return L10n.isZh ? "请为每个项目选择参与者" : "Choose who shares every item." }
        if sessionSubtotalMoney <= .zero { return L10n.isZh ? "请先添加至少一项消费" : "Add at least one item before settling." }
        return nil
    }

    var isReadyToSettle: Bool {
        settlementValidationMessage == nil
    }

    var canRemovePerson: Bool {
        people.count > 1
    }

    /// Every item this person takes part in, with their exact share.
    func itemShares(for personID: UUID) -> [ItemShare] {
        items.compactMap { item in
            let recipients = peopleIncluded(in: item)
            guard let index = recipients.firstIndex(where: { $0.id == personID }) else { return nil }
            let allocation = Money.splitEvenly(money(item.price), among: recipients.count)
            return ItemShare(id: item.id, name: item.name, total: money(item.price),
                             share: allocation[index], peopleCount: recipients.count,
                             participantNames: recipients.map(\.name))
        }
    }

    /// The part of this person's subtotal that comes from shared items.
    func sharedPortion(for personID: UUID) -> Double {
        itemShares(for: personID).filter(\.isShared).reduce(Money.zero) { $0 + $1.share }.amount
    }

    private func subtotalMoney(for person: SplitPerson) -> Money {
        itemShares(for: person.id).reduce(.zero) { $0 + $1.share }
    }

    func subtotal(for person: SplitPerson) -> Double {
        subtotalMoney(for: person).amount
    }

    private var sessionSubtotalMoney: Money {
        items.reduce(.zero) { $0 + money($1.price) }
    }

    var sessionSubtotal: Double {
        sessionSubtotalMoney.amount
    }

    private var totalTaxMoney: Money {
        money(taxAmount ?? 0)
    }

    var totalTaxAmount: Double {
        totalTaxMoney.amount
    }

    private var totalTipMoney: Money {
        if tipSelection == TipPreset.fixedAmount {
            return money(customFixedTip ?? 0)
        }

        let percentage = tipSelection == TipPreset.customPercentage ? (customTipPercentage ?? 0) : tipSelection
        return sessionSubtotalMoney.applying(percent: percentage)
    }

    var totalTipAmount: Double {
        totalTipMoney.amount
    }

    private var sharedCostsMoney: Money {
        totalTaxMoney + totalTipMoney
    }

    var sharedCosts: Double {
        sharedCostsMoney.amount
    }

    var grandTotal: Double {
        (sessionSubtotalMoney + sharedCostsMoney).amount
    }

    private var sharedCostAllocations: [UUID: Money] {
        let weights = people.map { max(0, subtotalMoney(for: $0).minorUnits) }
        let allocations = Money.allocate(sharedCostsMoney, by: weights)
        return Dictionary(uniqueKeysWithValues: zip(people.map(\.id), allocations))
    }

    func finalTotal(for person: SplitPerson) -> Double {
        guard sessionSubtotalMoney > .zero else { return 0 }
        return (subtotalMoney(for: person) + (sharedCostAllocations[person.id] ?? .zero)).amount
    }

    /// Tax and tip allocated to this person in proportion to their items.
    func taxAndTip(for person: SplitPerson) -> Double {
        (Money(finalTotal(for: person)) - subtotalMoney(for: person)).amount
    }
    
    func generateNote(for person: SplitPerson) -> String {
        let itemNames = itemShares(for: person.id).map { share in
            share.isShared ? "1/\(share.peopleCount) \(share.name)" : share.name
        }
        let itemsStr = itemNames.joined(separator: ", ")
        
        var summary = SplitNote.quick(total: Money(grandTotal), share: Money(finalTotal(for: person)), people: people.count)
        if let merchant, !merchant.isEmpty { summary = "\(merchant)\n\(summary)" }
        return itemsStr.isEmpty ? summary : "\(summary)\n\(itemsStr)"
    }
    
    func reset() {
        people.removeAll()
        items.removeAll()
        addPerson(name: Self.defaultFirstPersonName)
        taxAmount = nil
        tipSelection = TipPreset.defaultSelection
        customTipPercentage = nil
        customFixedTip = nil
        merchant = nil
    }
}

extension SplitSession {
    @MainActor
    func makeReceiptData() -> ReceiptData {
        func displayName(_ name: String) -> String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? (L10n.isZh ? "未命名" : "Guest") : trimmed
        }
        var rows: [ReceiptItem] = []
        for person in people {
            let name = displayName(person.name)
            rows.append(.text(name, ""))
            let shares = itemShares(for: person.id)
            for item in shares where !item.isShared {
                rows.append(.currency(item.name.isEmpty ? (L10n.isZh ? "个人项目" : "Personal item") : item.name, item.share.amount))
            }
            let sharedItems = shares.filter(\.isShared)
            if !sharedItems.isEmpty {
                rows.append(ReceiptItem(label: L10n.isZh ? "共享分摊" : "Shared portion",
                                        value: .currency(sharedPortion(for: person.id)),
                                        style: .sharedSubtotal))
                for item in sharedItems {
                    rows.append(ReceiptItem(
                        label: item.name.isEmpty ? (L10n.isZh ? "共享项目" : "Shared item") : item.name,
                        value: .currency(item.share.amount), style: .detail,
                        participants: item.participantNames.map(displayName)))
                }
            }
            let final = Money(finalTotal(for: person))
            let extras = final - Money(subtotal(for: person))
            if extras > .zero {
                rows.append(.currency(L10n.isZh ? "税费与小费" : "Tax & tip", extras.amount))
            }
            rows.append(ReceiptItem(label: L10n.isZh ? "个人总计" : "Person total",
                                    value: .currency(final.amount), style: .personTotal))
        }
        let title = merchant.flatMap { $0.isEmpty ? nil : $0 } ?? (L10n.isZh ? "按人分配" : "Split by Person")
        return ReceiptData(title: title, items: rows,
                           subtotal: sessionSubtotal, tax: totalTaxAmount, tip: totalTipAmount,
                           total: grandTotal, footer: "Generated by DailySpend")
    }
}
