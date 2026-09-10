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

nonisolated struct SharedItemShare: Identifiable {
    let id: UUID
    let name: String
    let total: Money
    let share: Money
    let peopleCount: Int
    let participantNames: [String]
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

struct BasketItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var price: Double
}

struct SharedItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var price: Double
    var involvedPersonIDs: [UUID]
}

// These are UI-facing state containers, but their values and calculation
// helpers don't require actor isolation. Opting them out of the project's
// default MainActor isolation also avoids an iOS 26.3 runtime crash while
// tearing down @Published child objects in unit tests.
nonisolated class SplitPerson: Identifiable, ObservableObject {
    let id = UUID()
    @Published var name: String
    @Published var items: [BasketItem] = []
    
    var friendID: UUID?
    
    init(name: String, friendID: UUID? = nil) {
        self.name = name
        self.friendID = friendID
    }
    
    var personalSubtotal: Double {
        items.reduce(0) { $0 + $1.price }
    }
}

// MARK: - The Session Logic Engine

nonisolated class SplitSession: ObservableObject {
    @Published var people: [SplitPerson] = []
    @Published var sharedItems: [SharedItem] = []
    @Published var taxAmount: Double?
    
    @Published var tipSelection: Int = 15
    @Published var customTipPercentage: Int?
    @Published var customFixedTip: Double?
    
    init() {
        addPerson(name: NSLocalizedString("Me", comment: "Default user"))
    }
    
    // MARK: - Person Management
    
    func addPerson(name: String, friendID: UUID? = nil) {
        let newPerson = SplitPerson(name: name, friendID: friendID)
        people.append(newPerson)
        objectWillChange.send()
    }
    
    func removePerson(id: UUID) {
        // A bill always needs at least one participant. Keeping that invariant
        // prevents an accidental delete from making every total unrecordable.
        guard people.count > 1 else { return }
        people.removeAll { $0.id == id }
        for index in sharedItems.indices {
            sharedItems[index].involvedPersonIDs.removeAll { $0 == id }
        }
        objectWillChange.send()
    }
    
    // MARK: - Item Management
    
    func addPersonalItem(to personID: UUID, name: String, price: Double) {
        guard let person = people.first(where: { $0.id == personID }) else { return }
        let item = BasketItem(name: name, price: price)
        person.items.append(item)
        objectWillChange.send()
    }
    
    func removePersonalItem(from personID: UUID, itemID: UUID) {
        guard let person = people.first(where: { $0.id == personID }) else { return }
        person.items.removeAll { $0.id == itemID }
        objectWillChange.send()
    }
    
    func addSharedItem(name: String, price: Double) {
        let allIDs = people.map { $0.id }
        let item = SharedItem(name: name, price: price, involvedPersonIDs: allIDs)
        sharedItems.append(item)
        objectWillChange.send()
    }
    
    func removeSharedItem(id: UUID) {
        sharedItems.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    func togglePersonInSharedItem(itemID: UUID, personID: UUID) {
        guard let index = sharedItems.firstIndex(where: { $0.id == itemID }) else { return }
        var ids = sharedItems[index].involvedPersonIDs
        
        if ids.contains(personID) {
            ids.removeAll { $0 == personID }
        } else {
            ids.append(personID)
        }
        
        sharedItems[index].involvedPersonIDs = ids
        objectWillChange.send()
    }
    
    // MARK: - Robust Math Engine

    private func money(_ value: Double) -> Money {
        Money(value)
    }

    private func peopleIncluded(in item: SharedItem) -> [SplitPerson] {
        // Always use the visible people order so an unavoidable extra cent is
        // allocated predictably and the same on every redraw.
        people.filter { item.involvedPersonIDs.contains($0.id) }
    }

    var hasUnallocatedSharedItems: Bool {
        sharedItems.contains { peopleIncluded(in: $0).isEmpty }
    }

    var hasInvalidAmounts: Bool {
        taxAmount.map { !ExpenseInputValidator.isValidLineItemAmount($0) } ?? false
        || customFixedTip.map { !ExpenseInputValidator.isValidLineItemAmount($0) } ?? false
        || customTipPercentage.map { $0 < 0 } ?? false
        || people.flatMap(\.items).contains { !ExpenseInputValidator.isValidLineItemAmount($0.price) }
        || sharedItems.contains { !ExpenseInputValidator.isValidLineItemAmount($0.price) }
    }

    var settlementValidationMessage: String? {
        if people.isEmpty { return L10n.isZh ? "请至少保留一位参与者" : "Add at least one participant." }
        if hasInvalidAmounts { return L10n.isZh ? "请输入大于 0 的金额" : "Enter amounts greater than zero." }
        if hasUnallocatedSharedItems { return L10n.isZh ? "请为每个共享项目选择参与者" : "Choose people for every shared item." }
        if sessionSubtotalMoney <= .zero { return L10n.isZh ? "请先添加至少一项消费" : "Add at least one item before settling." }
        return nil
    }

    var isReadyToSettle: Bool {
        settlementValidationMessage == nil
    }

    var canRemovePerson: Bool {
        people.count > 1
    }

    func sharedItemShares(for personID: UUID) -> [SharedItemShare] {
        sharedItems.compactMap { item in
            let recipients = peopleIncluded(in: item)
            guard let index = recipients.firstIndex(where: { $0.id == personID }) else { return nil }
            let allocation = Money.splitEvenly(money(item.price), among: recipients.count)
            return SharedItemShare(id: item.id, name: item.name, total: money(item.price),
                                   share: allocation[index], peopleCount: recipients.count,
                                   participantNames: recipients.map(\.name))
        }
    }

    private func sharedPortionMoney(for personID: UUID) -> Money {
        sharedItemShares(for: personID).reduce(.zero) { $0 + $1.share }
    }

    func sharedPortion(for personID: UUID) -> Double {
        sharedPortionMoney(for: personID).amount
    }

    private func subtotalMoney(for person: SplitPerson) -> Money {
        let personal = person.items.reduce(.zero) { $0 + money($1.price) }
        return personal + sharedPortionMoney(for: person.id)
    }

    func subtotal(for person: SplitPerson) -> Double {
        subtotalMoney(for: person).amount
    }

    private var sessionSubtotalMoney: Money {
        let personal = people.flatMap(\.items).reduce(.zero) { $0 + money($1.price) }
        let shared = sharedItems.reduce(.zero) { $0 + money($1.price) }
        return personal + shared
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
        if tipSelection == -2 {
            return money(customFixedTip ?? 0)
        }

        let percentage = tipSelection == -1 ? (customTipPercentage ?? 0) : tipSelection
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
    
    func generateNote(for person: SplitPerson) -> String {
        let personalNames = person.items.map { $0.name }
        
        let sharedNames = sharedItems
            .filter { $0.involvedPersonIDs.contains(person.id) }
            .map { "1/\($0.involvedPersonIDs.count) \($0.name)" }
        
        let allItems = personalNames + sharedNames
        let itemsStr = allItems.joined(separator: ", ")
        
        let summary = SplitNote.quick(total: Money(grandTotal), share: Money(finalTotal(for: person)), people: people.count)
        return itemsStr.isEmpty ? summary : "\(summary)\n\(itemsStr)"
    }
    
    func reset() {
        people.removeAll()
        sharedItems.removeAll()
        addPerson(name: NSLocalizedString("Me", comment: ""))
        taxAmount = nil
        tipSelection = 15
        customTipPercentage = nil
        customFixedTip = nil
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
            for item in person.items {
                rows.append(.currency(item.name.isEmpty ? (L10n.isZh ? "个人项目" : "Personal item") : item.name, item.price))
            }
            let shares = sharedItemShares(for: person.id)
            if !shares.isEmpty {
                rows.append(ReceiptItem(label: L10n.isZh ? "共享分摊" : "Shared portion",
                                        value: .currency(sharedPortion(for: person.id)),
                                        style: .sharedSubtotal))
                for item in shares {
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
        return ReceiptData(title: L10n.isZh ? "按人分配" : "Split by Person", items: rows,
                           subtotal: sessionSubtotal, tax: totalTaxAmount, tip: totalTipAmount,
                           total: grandTotal, footer: "Generated by DailySpend")
    }
}
