import CoreGraphics
import Foundation

/// Structured data read from a receipt. A draft is never saved: it only fills
/// the existing expense and split forms, where a person reviews it first.
///
/// The on-device model may read text, but it never does the arithmetic. Every
/// amount is parsed into exact cents here, and the checks below decide whether
/// the printed values agree before any of them reach a form.
nonisolated struct ReceiptDraft: Equatable, Sendable {
    nonisolated struct LineItem: Identifiable, Equatable, Sendable {
        var id = UUID()
        var name: String
        var quantity: Int
        /// The printed line total, not a unit price.
        var price: Money
    }

    enum Source: Equatable, Sendable {
        /// Apple's on-device model structured the recognized text.
        case appleIntelligence
        /// Only Vision text recognition and the total parser were available.
        case textRecognition
    }

    enum Issue: Equatable, Sendable {
        case totalNotFound
        case totalMismatch(calculated: Money, printed: Money)
        case itemsAdjusted(by: Money)
        case differentCurrency(String)
        case textTruncated
    }

    /// Must match `Expense.categories`; kept here so this value type stays
    /// usable outside the main actor. A unit test checks both lists agree.
    static let categoryNames = ["Food", "Grocery", "Shopping", "Transport", "Housing",
                                "Entertainment", "Health", "Utilities", "Other"]

    var merchant: String?
    var date: Date?
    var currencyCode: String?
    var items: [LineItem] = []
    var subtotal: Money?
    var discount: Money?
    var tax: Money?
    var tip: Money?
    var total: Money?
    var category: String?
    /// Whether tipping is customary for this business, as judged by the model.
    var isTippedService: Bool?
    var source: Source
    var wasTextTruncated = false

    // MARK: - Values used by the forms

    /// What was paid, used for a single expense.
    var amountToRecord: Money? {
        guard let total, total > .zero else { return nil }
        return total
    }

    /// The bill an even split starts from. A charged tip is handled by the
    /// split's own tip control, so it is removed here to avoid counting it twice.
    var billBeforeTip: Money? {
        guard let total = amountToRecord else { return nil }
        guard let tip, tip > .zero, total - tip > .zero else { return total }
        return total - tip
    }

    var itemsTotal: Money {
        items.reduce(.zero) { $0 + $1.price }
    }

    /// The amount the line items should add up to before tax and tip.
    private var itemTarget: Money? {
        if let subtotal, subtotal > .zero { return subtotal }
        guard let total = amountToRecord else { return nil }
        let target = total - (tax ?? .zero) - (tip ?? .zero)
        return target > .zero ? target : nil
    }

    /// Items for an itemized split. They always add up to the receipt's
    /// subtotal: a printed discount is spread across items in proportion to
    /// their prices, and anything the reader missed becomes a visible
    /// "Other items" line that people can assign or delete.
    func itemsForSplit(expandingQuantities: Bool = true) -> [LineItem] {
        var result = items
        if let target = itemTarget, !result.isEmpty {
            let difference = target - itemsTotal
            if difference < .zero {
                let reduction = Money(minorUnits: -difference.minorUnits)
                if reduction < itemsTotal {
                    let cuts = Money.allocate(reduction, by: result.map(\.price.minorUnits))
                    for index in result.indices {
                        result[index].price = result[index].price - cuts[index]
                    }
                    result.removeAll { $0.price <= .zero }
                }
            } else if difference > .zero {
                result.append(LineItem(name: Self.otherItemsName, quantity: 1, price: difference))
            }
        }
        guard expandingQuantities else { return result }
        return result.flatMap { item -> [LineItem] in
            // "2 × Burger" becomes two burgers so different people can take
            // each one. Larger quantities stay together to keep lists short.
            guard (2...6).contains(item.quantity) else { return [item] }
            return Money.splitEvenly(item.price, among: item.quantity).map {
                LineItem(name: item.name, quantity: 1, price: $0)
            }
        }
    }

    /// Tax for an itemized split, including any small fees printed between the
    /// subtotal and total so each person's share adds up to the receipt.
    var taxForSplit: Money? {
        guard let total = amountToRecord, let target = itemTarget else { return tax }
        let remainder = total - target - (tip ?? .zero)
        if remainder >= .zero { return remainder }
        return tax
    }

    var issues: [Issue] {
        var issues: [Issue] = []
        if amountToRecord == nil { issues.append(.totalNotFound) }
        if let printed = amountToRecord, let calculated = calculatedTotal, calculated != printed {
            issues.append(.totalMismatch(calculated: calculated, printed: printed))
        }
        if let target = itemTarget, !items.isEmpty, target != itemsTotal {
            let adjustment = target - itemsTotal
            // A printed discount that explains the gap is expected, not a warning.
            if discount.map({ Money(minorUnits: -adjustment.minorUnits) == $0 }) != true {
                issues.append(.itemsAdjusted(by: adjustment))
            }
        }
        if let currencyCode, currencyCode != Self.localCurrencyCode {
            issues.append(.differentCurrency(currencyCode))
        }
        if wasTextTruncated { issues.append(.textTruncated) }
        return issues
    }

    /// Subtotal plus tax and tip, when enough parts were printed to check.
    private var calculatedTotal: Money? {
        guard let subtotal, subtotal > .zero, tax != nil || tip != nil else { return nil }
        return subtotal + (tax ?? .zero) + (tip ?? .zero)
    }

    static var otherItemsName: String {
        L10n.isZh ? "其他项目" : "Other items"
    }

    static var localCurrencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    /// Store and shop receipts show the final amount paid; adding a default
    /// restaurant tip to them would split more than anyone spent.
    var expectsNoTip: Bool {
        tip == nil && isTippedService == false
    }

    /// A short note for the expense: the merchant, then a few item names.
    var suggestedNote: String {
        let names = items.map(\.name).filter { !$0.isEmpty }
        var parts: [String] = []
        if let merchant, !merchant.isEmpty { parts.append(merchant) }
        if !names.isEmpty {
            let shown = names.prefix(3).joined(separator: ", ")
            let extra = names.count - 3
            parts.append(extra > 0
                ? (L10n.isZh ? "\(shown) 等 \(names.count) 项" : "\(shown) +\(extra) more")
                : shown)
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Cleaning model output

extension ReceiptDraft {
    /// Applies the deterministic rules to values read from a receipt. The model
    /// is told not to calculate, so anything derived is derived here.
    func reconciled(now: Date = Date(), calendar: Calendar = .current) -> ReceiptDraft {
        var draft = self
        draft.merchant = merchant.map(Self.readableName)?.nilIfEmpty
        draft.currencyCode = currencyCode.map { $0.uppercased() }.flatMap { $0.count == 3 && $0.allSatisfy(\.isLetter) ? $0 : nil }
        draft.category = category.flatMap { Self.categoryNames.contains($0) ? $0 : nil }
        draft.subtotal = subtotal.flatMap(Self.positive)
        draft.tax = tax.flatMap(Self.positive)
        draft.tip = tip.flatMap(Self.positive)
        draft.total = total.flatMap(Self.positive)

        if let date {
            let latest = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            let earliest = calendar.date(byAdding: .year, value: -2, to: now) ?? now
            draft.date = (earliest...latest).contains(date) ? date : nil
        }

        // Negative lines are coupons or discounts, not purchases.
        var extraDiscount = Money.zero
        draft.items = items.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Self.isSummaryLabel(name) else { return nil }
            if item.price < .zero {
                extraDiscount = extraDiscount + Money(minorUnits: -item.price.minorUnits)
                return nil
            }
            guard item.price > .zero,
                  item.price.minorUnits <= ExpenseInputValidator.maximumInputMinorUnits else { return nil }
            return LineItem(id: item.id, name: Self.readableName(name), quantity: max(1, min(item.quantity, 99)), price: item.price)
        }
        // A coupon row is often printed both as a line and in a discount
        // summary, so the larger of the two is used rather than their sum.
        let printedDiscount = discount.map { Money(minorUnits: abs($0.minorUnits)) } ?? .zero
        let combinedDiscount = max(printedDiscount, extraDiscount)
        draft.discount = combinedDiscount > .zero ? combinedDiscount : nil

        // "2 @ 3.49" rows are sometimes read as the unit price. Use line totals
        // only when that makes the items match the printed subtotal exactly.
        if let target = draft.subtotal, draft.items.contains(where: { $0.quantity > 1 }) {
            let discountValue = draft.discount ?? .zero
            func matchesSubtotal(_ items: [LineItem]) -> Bool {
                let sum = items.reduce(Money.zero) { $0 + $1.price }
                return sum == target || sum - discountValue == target
            }
            let lineTotals = draft.items.map { item -> LineItem in
                var line = item
                if item.quantity > 1 { line.price = Money(minorUnits: item.price.minorUnits * Int64(item.quantity)) }
                return line
            }
            if !matchesSubtotal(draft.items), matchesSubtotal(lineTotals) {
                draft.items = lineTotals
            }
        }

        // A tip line is often a printed suggestion. When the total already
        // matches without it, nothing was charged.
        if let tip = draft.tip, let total = draft.total, let subtotal = draft.subtotal,
           subtotal + (draft.tax ?? .zero) == total, subtotal + (draft.tax ?? .zero) + tip != total {
            draft.tip = nil
        }

        if draft.total == nil {
            if let subtotal = draft.subtotal {
                draft.total = subtotal + (draft.tax ?? .zero) + (draft.tip ?? .zero)
            } else if !draft.items.isEmpty {
                let computed = draft.itemsTotal - (draft.discount ?? .zero) + (draft.tax ?? .zero) + (draft.tip ?? .zero)
                draft.total = computed > .zero ? computed : nil
            }
        }
        return draft
    }

    /// Receipt printers often use capitals only. Long all-capital words are
    /// shown in title case; short ones such as "CVS" or "24CT" stay as printed.
    static func readableName(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { word -> String in
                let letters = word.filter(\.isLetter)
                guard letters.count > 3, letters.allSatisfy(\.isUppercase) else { return String(word) }
                return String(word.prefix(1)) + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private static func positive(_ money: Money) -> Money? {
        let value = Money(minorUnits: abs(money.minorUnits))
        guard value > .zero, value.minorUnits <= ExpenseInputValidator.maximumInputMinorUnits else { return nil }
        return value
    }

    private static let latinSummaryLabels = [
        "subtotal", "sub total", "sub-total", "total", "tax", "vat", "gst", "hst", "pst", "tip",
        "gratuity", "change", "cash", "visa", "mastercard", "amex", "debit", "credit", "balance",
        "amount due", "payment", "tender"
    ]
    private static let cjkSummaryLabels = ["小计", "合计", "总计", "税", "小费", "找零", "现金", "实付", "应付", "支付", "总额"]

    /// True for rows that summarize a receipt rather than describe a purchase.
    static func isSummaryLabel(_ name: String) -> Bool {
        let normalized = name.lowercased()
        if cjkSummaryLabels.contains(where: normalized.contains) { return true }
        return latinSummaryLabels.contains { label in
            normalized.range(of: #"(^|[^a-z])"# + NSRegularExpression.escapedPattern(for: label) + #"($|[^a-z])"#,
                             options: .regularExpression) != nil
        }
    }
}

// MARK: - Amounts as printed

/// Reads an amount exactly as it appears on a receipt, independent of the
/// device's locale: "1,234.56", "1.234,56", "$12.5", and "(2.00)" all work.
nonisolated enum ReceiptNumberParser {
    static func money(from text: String?) -> Money? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let isNegative = text.contains("-") || text.contains("−") || (text.hasPrefix("(") && text.hasSuffix(")"))
        let kept = text.filter { $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }
        guard kept.contains(where: \.isNumber) else { return nil }

        var integerPart = Substring(kept)
        var fractionPart = Substring("")
        // The last separator is a decimal point only when one or two digits
        // follow it; three digits mean it groups thousands.
        if let separator = kept.lastIndex(where: { $0 == "." || $0 == "," }) {
            let after = kept[kept.index(after: separator)...]
            if (1...2).contains(after.count), after.allSatisfy(\.isNumber) {
                integerPart = kept[..<separator]
                fractionPart = after
            }
        }
        let digits = integerPart.filter(\.isNumber)
        guard digits.count <= 14 else { return nil }
        let cents = fractionPart.padding(toLength: 2, withPad: "0", startingAt: 0)
        guard let minorUnits = Int64((digits.isEmpty ? "0" : digits) + cents) else { return nil }
        return Money(minorUnits: isNegative ? -minorUnits : minorUnits)
    }

    /// Reads "YYYY-MM-DD" as a calendar date in the current time zone.
    static func date(from text: String?, calendar: Calendar = .current) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        var components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        components.hour = 12
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == parts[2] else { return nil }
        return date
    }
}

// MARK: - Recognized text layout

/// Vision returns each text fragment separately, so a receipt's item name and
/// its price arrive as two observations. Grouping them back into printed rows
/// keeps prices next to the things they belong to.
nonisolated enum ReceiptTextLayout {
    /// Roughly 1,000 tokens of Latin text. It leaves room for instructions,
    /// the response schema, and a long item list in the model's context.
    static let defaultCharacterBudget = 4_000

    static func rows(from lines: [ReceiptAmountParser.Line]) -> [String] {
        rowLines(from: lines).map(\.text)
    }

    /// Printed rows with the combined bounds of their fragments, top first.
    static func rowLines(from lines: [ReceiptAmountParser.Line]) -> [ReceiptAmountParser.Line] {
        struct Row {
            var midY: CGFloat
            var height: CGFloat
            var fragments: [ReceiptAmountParser.Line]
        }
        var rows: [Row] = []
        // Vision's coordinates start at the bottom, so larger Y is higher up.
        for line in lines.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let index = rows.firstIndex(where: { row in
                abs(row.midY - line.boundingBox.midY) < min(row.height, line.boundingBox.height) * 0.5
            }) {
                rows[index].fragments.append(line)
            } else {
                rows.append(Row(midY: line.boundingBox.midY, height: line.boundingBox.height, fragments: [line]))
            }
        }
        return rows
            .sorted { $0.midY > $1.midY }
            .map { row in
                let fragments = row.fragments.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                let text = fragments
                    .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .joined(separator: " | ")
                let bounds = fragments.dropFirst().reduce(fragments[0].boundingBox) { $0.union($1.boundingBox) }
                return ReceiptAmountParser.Line(text: text, boundingBox: bounds)
            }
    }

    /// Fits recognized rows into a character budget. Address lines at the top
    /// and payment details after the total go first; items are kept longest.
    static func prompt(fromRows rows: [String], characterBudget: Int = defaultCharacterBudget) -> (text: String, truncated: Bool) {
        var kept = rows
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }

        func cost(_ rows: [String]) -> Int {
            // Non-Latin scripts use more tokens per character.
            rows.reduce(0) { total, row in total + row.unicodeScalars.reduce(1) { $0 + ($1.isASCII ? 1 : 3) } }
        }
        guard cost(kept) > characterBudget else { return (kept.joined(separator: "\n"), false) }

        if let lastTotal = kept.lastIndex(where: { ($0.lowercased().contains("total") && ReceiptDraft.isSummaryLabel($0)) || $0.contains("合计") }),
           kept.count > lastTotal + 4 {
            kept.removeSubrange((lastTotal + 4)...)
        }
        // Keep the first rows, which usually name the store, then drop address
        // and phone rows until the first priced row.
        let pricePattern = #"\d[.,]\d{2}(\D|$)"#
        while cost(kept) > characterBudget, kept.count > 4,
              kept[3].range(of: pricePattern, options: .regularExpression) == nil {
            kept.remove(at: 3)
        }
        // A very long receipt loses its earliest items before its totals.
        // Splits show the missing amount as a separate line.
        while cost(kept) > characterBudget, kept.count > 8 {
            kept.remove(at: 3)
        }
        return (kept.joined(separator: "\n"), true)
    }
}

/// Straightens text read from a tilted photo. Vision reports upright boxes,
/// so on a crooked receipt a price at the right edge sits higher or lower
/// than its item name and would otherwise land on a different row.
nonisolated enum ReceiptSkew {
    /// The tilt of a photo, in radians, from the baselines of long text
    /// fragments. Coordinates are Vision's normalized ones for an image of
    /// `size`. Short words report noisy or exactly flat baselines, so only
    /// long, measurably tilted fragments count, weighted by their length.
    static func angle(baselines: [(left: CGPoint, right: CGPoint, height: CGFloat)], imageSize size: CGSize) -> CGFloat {
        var weightedSum: CGFloat = 0
        var totalWeight: CGFloat = 0
        for baseline in baselines {
            let dx = (baseline.right.x - baseline.left.x) * size.width
            let dy = (baseline.right.y - baseline.left.y) * size.height
            guard dx > 4 * baseline.height * size.height else { continue }
            let angle = atan2(dy, dx)
            guard abs(angle) > 0.0005 else { continue }
            weightedSum += angle * dx
            totalWeight += dx
        }
        guard totalWeight > 0 else { return 0 }
        let angle = weightedSum / totalWeight
        // Very small angles are noise; very large ones are a sideways photo,
        // which orientation metadata handles instead.
        return abs(angle) < 0.004 || abs(angle) > 0.35 ? 0 : angle
    }

    /// Rotates each fragment's center around the image center by `-angle`,
    /// keeping its size, so fragments on one printed row share a height.
    static func straighten(_ lines: [ReceiptAmountParser.Line], angle: CGFloat, imageSize size: CGSize) -> [ReceiptAmountParser.Line] {
        guard angle != 0, size.width > 0, size.height > 0 else { return lines }
        let cosine = cos(-angle), sine = sin(-angle)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return lines.map { line in
            let box = line.boundingBox
            let x = box.midX * size.width - center.x
            let y = box.midY * size.height - center.y
            let rotated = CGPoint(x: center.x + x * cosine - y * sine,
                                  y: center.y + x * sine + y * cosine)
            let straightened = CGRect(x: rotated.x / size.width - box.width / 2,
                                      y: rotated.y / size.height - box.height / 2,
                                      width: box.width, height: box.height)
            return ReceiptAmountParser.Line(text: line.text, boundingBox: straightened)
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
