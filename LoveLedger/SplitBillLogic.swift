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
    let label: String
    let value: ReceiptValueType
    
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

class SplitPerson: Identifiable, ObservableObject {
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

class SplitSession: ObservableObject {
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
    
    private func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
    
    func sharedPortion(for personID: UUID) -> Double {
        var totalShare: Double = 0
        
        for item in sharedItems {
            if item.involvedPersonIDs.contains(personID) {
                let count = Double(item.involvedPersonIDs.count)
                if count > 0 {
                    totalShare += round2(item.price / count)
                }
            }
        }
        return totalShare
    }
    
    func subtotal(for person: SplitPerson) -> Double {
        round2(person.personalSubtotal + sharedPortion(for: person.id))
    }
    
    var sessionSubtotal: Double {
        round2(people.reduce(0) { $0 + subtotal(for: $1) })
    }
    
    var totalTaxAmount: Double {
        taxAmount ?? 0
    }
    
    var totalTipAmount: Double {
        if tipSelection == -2 {
            return customFixedTip ?? 0
        } else {
            let percentage = Double(tipSelection == -1 ? (customTipPercentage ?? 0) : tipSelection)
            return round2(sessionSubtotal * percentage / 100.0)
        }
    }
    
    var sharedCosts: Double {
        totalTaxAmount + totalTipAmount
    }
    
    var grandTotal: Double {
        sessionSubtotal + sharedCosts
    }
    
    func finalTotal(for person: SplitPerson) -> Double {
        guard sessionSubtotal > 0 else { return 0 }
        
        let personSub = subtotal(for: person)
        let ratio = personSub / sessionSubtotal
        let personTaxTip = sharedCosts * ratio
        
        return round2(personSub + personTaxTip)
    }
    
    func generateNote(for person: SplitPerson) -> String {
        let personalNames = person.items.map { $0.name }
        
        let sharedNames = sharedItems
            .filter { $0.involvedPersonIDs.contains(person.id) }
            .map { "1/\($0.involvedPersonIDs.count) \($0.name)" }
        
        let allItems = personalNames + sharedNames
        let itemsStr = allItems.joined(separator: ", ")
        
        let base = subtotal(for: person)
        return "Split: \(itemsStr.isEmpty ? "Items" : itemsStr) (\(String(format: "%.2f", base)) + tax/tip)"
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
