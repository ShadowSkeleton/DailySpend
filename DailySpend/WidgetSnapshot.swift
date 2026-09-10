import Foundation

/// A single, versioned value shared by the app and widget extension. Never
/// contains transactions, notes, or account identifiers. Money stays in cents.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let appGroup = "group.com.jackson.LoveLedger" // Keep installed widgets compatible.
    static let storageKey = "dailyspend.widget.snapshot.v1"
    static let legacyKeys = ["widget_total", "widget_budget", "widget_isBudgetEnabled", "widget_chartData", "widget_lastUpdated"]

    var version = 1
    let totalCents: Int64
    let budgetCents: Int64
    let isBudgetEnabled: Bool
    let chartCents: [Int64]
    let lastUpdated: Date
    let hasData: Bool
    let hidesAmounts: Bool

    var total: Double { Double(totalCents) / 100 }
    var budget: Double { Double(budgetCents) / 100 }
    var chartData: [Double] { chartCents.map { Double($0) / 100 } }

    static let empty = WidgetSnapshot(totalCents: 0, budgetCents: 0, isBudgetEnabled: false,
                                      chartCents: Array(repeating: 0, count: 7), lastUpdated: .distantPast,
                                      hasData: false, hidesAmounts: false)
    static var preview: WidgetSnapshot {
        WidgetSnapshot(totalCents: 9494, budgetCents: 65000, isBudgetEnabled: true,
                       chartCents: [800, 2200, 0, 3400, 1200, 1494, 400], lastUpdated: Date(),
                       hasData: true, hidesAmounts: false)
    }

    var isValid: Bool {
        version == 1 && totalCents >= 0 && budgetCents >= 0 && chartCents.count == 7 &&
        chartCents.allSatisfy { $0 >= 0 } && lastUpdated.timeIntervalSince1970.isFinite &&
        (!hidesAmounts || (totalCents == 0 && budgetCents == 0 && chartCents.allSatisfy { $0 == 0 } && !isBudgetEnabled))
    }

    func needsRefresh(at date: Date, calendar: Calendar = .current) -> Bool {
        !hasData || !calendar.isDate(lastUpdated, inSameDayAs: date)
    }

    static func load(from store: UserDefaults? = UserDefaults(suiteName: appGroup)) -> WidgetSnapshot {
        guard let data = store?.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data), snapshot.isValid else {
            // Do not revive old, potentially private or inconsistent scalar keys.
            // Opening the updated app safely republishes a complete snapshot.
            return .empty
        }
        return snapshot
    }

    @discardableResult
    func save(to store: UserDefaults) -> Bool {
        guard isValid, let data = try? JSONEncoder().encode(self) else { return false }
        store.set(data, forKey: Self.storageKey)
        for key in Self.legacyKeys { store.removeObject(forKey: key) }
        return true
    }
}
