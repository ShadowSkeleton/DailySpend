import Foundation

/// A small, value-type currency helper used for calculations only.
///
/// Expenses continue to persist their existing `Double` amounts so this change
/// doesn't alter the shipped SwiftData schema. All new calculations convert to
/// minor units first, which keeps split totals stable and reconcilable.
struct Money: Equatable, Comparable, Hashable, Sendable {
    nonisolated static let zero = Money(minorUnits: 0)

    nonisolated let minorUnits: Int64

    nonisolated init(minorUnits: Int64) {
        self.minorUnits = minorUnits
    }

    nonisolated init(_ amount: Double) {
        guard amount.isFinite else {
            self = .zero
            return
        }

        var value = Decimal(amount)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        self.minorUnits = Self.minorUnits(from: rounded * 100)
    }

    nonisolated var amount: Double {
        Double(minorUnits) / 100
    }

    nonisolated static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.minorUnits < rhs.minorUnits
    }

    nonisolated static func + (lhs: Money, rhs: Money) -> Money {
        let (sum, overflow) = lhs.minorUnits.addingReportingOverflow(rhs.minorUnits)
        guard overflow else { return Money(minorUnits: sum) }
        return Money(minorUnits: lhs.minorUnits >= 0 ? .max : .min)
    }

    nonisolated static func - (lhs: Money, rhs: Money) -> Money {
        let (difference, overflow) = lhs.minorUnits.subtractingReportingOverflow(rhs.minorUnits)
        guard overflow else { return Money(minorUnits: difference) }
        return Money(minorUnits: lhs.minorUnits >= 0 ? .max : .min)
    }

    nonisolated static func splitEvenly(_ total: Money, among count: Int) -> [Money] {
        guard count > 0 else { return [] }

        let divisor = Int64(count)
        let base = total.minorUnits / divisor
        let remainder = total.minorUnits % divisor
        let direction: Int64 = remainder < 0 ? -1 : 1

        return (0..<count).map { index in
            let receivesRemainder = Int64(index) < abs(remainder)
            return Money(minorUnits: base + (receivesRemainder ? direction : 0))
        }
    }

    /// Allocates a total across weighted recipients and gives any remaining
    /// cents to the largest fractional shares, with stable input-order ties.
    nonisolated static func allocate(_ total: Money, by weights: [Int64]) -> [Money] {
        guard !weights.isEmpty else { return [] }
        guard total.minorUnits >= 0, weights.allSatisfy({ $0 >= 0 }) else {
            return Array(repeating: .zero, count: weights.count)
        }

        let weightTotal = weights.reduce(0, +)
        guard weightTotal > 0 else {
            return Array(repeating: .zero, count: weights.count)
        }

        struct AllocationPart {
            let index: Int
            let cents: Int64
            let fraction: Decimal
        }

        let parts: [AllocationPart] = weights.enumerated().map { index, weight in
            let raw = Decimal(total.minorUnits) * Decimal(weight) / Decimal(weightTotal)
            var roundedDown = Decimal()
            var rawCopy = raw
            NSDecimalRound(&roundedDown, &rawCopy, 0, .down)
            let cents = NSDecimalNumber(decimal: roundedDown).int64Value
            return AllocationPart(index: index, cents: cents, fraction: raw - roundedDown)
        }

        var result = parts.map { $0.cents }
        let assigned = result.reduce(0, +)
        let leftovers = Int(total.minorUnits - assigned)

        for part in parts.sorted(by: {
            if $0.fraction == $1.fraction { return $0.index < $1.index }
            return $0.fraction > $1.fraction
        }).prefix(max(0, leftovers)) {
            result[part.index] += 1
        }

        return result.map(Money.init(minorUnits:))
    }

    nonisolated func applying(percent: Int) -> Money {
        guard percent >= 0 else { return .zero }
        var value = Decimal(minorUnits) * Decimal(percent) / 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return Money(minorUnits: Self.minorUnits(from: rounded))
    }

    private nonisolated static func minorUnits(from cents: Decimal) -> Int64 {
        let maximum = Decimal(Int64.max)
        let minimum = Decimal(Int64.min)
        if cents >= maximum { return .max }
        if cents <= minimum { return .min }
        return NSDecimalNumber(decimal: cents).int64Value
    }
}

enum ExpenseInputValidator {
    /// This is vastly above realistic personal spending while leaving enough
    /// headroom for tax, tips, and aggregation without integer overflow.
    nonisolated static let maximumInputMinorUnits: Int64 = 100_000_000_000_000

    nonisolated static func isValidAmount(_ amount: Double?) -> Bool {
        guard let amount else { return false }
        let money = Money(amount)
        return amount.isFinite &&
            hasCurrencyPrecision(amount, money: money) &&
            money.minorUnits > 0 &&
            money.minorUnits <= maximumInputMinorUnits
    }

    nonisolated static func isValidLineItemAmount(_ amount: Double) -> Bool {
        let money = Money(amount)
        return amount.isFinite &&
            hasCurrencyPrecision(amount, money: money) &&
            money.minorUnits > 0 &&
            money.minorUnits <= maximumInputMinorUnits
    }

    /// TextField supplies Double values, so compare with a small tolerance for
    /// binary representation noise while rejecting any meaningful third cent.
    private nonisolated static func hasCurrencyPrecision(_ amount: Double, money: Money) -> Bool {
        abs(amount - money.amount) < 0.000_001
    }
}
