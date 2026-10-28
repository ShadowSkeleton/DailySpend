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
        /// The total read isn't printed anywhere on the receipt.
        case totalNotPrinted(Money)
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
    /// The tip table some restaurants print, such as "18% $7.02  20% $7.80".
    /// Nothing here was charged; it shows how the restaurant figures tips.
    var suggestedTips: [SuggestedTip] = []
    /// Whether the total appears on the receipt's own rows; nil when the
    /// rows weren't checked, as for a total-only read.
    var totalIsPrinted: Bool?

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
        if let subtotal, subtotal > .zero {
            return isDiscountAfterSubtotal ? subtotal - (discount ?? .zero) : subtotal
        }
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
        if let printed = amountToRecord, totalIsPrinted == false {
            issues.append(.totalNotPrinted(printed))
        } else if let printed = amountToRecord, let calculated = calculatedTotal, calculated != printed {
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

    /// True when the reading checks itself: the total is printed on the
    /// receipt, and either the subtotal, tax, and tip add up to it or the
    /// items do, with nothing else to question.
    var isVerified: Bool {
        guard source == .appleIntelligence, let total = amountToRecord, totalIsPrinted == true,
              issues.allSatisfy({ if case .differentCurrency = $0 { return true } else { return false } })
        else { return false }
        if let calculated = calculatedTotal { return calculated == total }
        return !items.isEmpty && itemsTotal - (discount ?? .zero) + (tax ?? .zero) + (tip ?? .zero) == total
    }

    /// How much a reading's problems matter, for choosing between two reads.
    var issueSeverity: Int {
        issues.reduce(0) { score, issue in
            switch issue {
            case .totalNotFound: score + 10
            case .totalNotPrinted: score + 6
            case .totalMismatch: score + 5
            case .itemsAdjusted: score + 2
            case .textTruncated: score + 1
            case .differentCurrency: score
            }
        }
    }

    /// Subtotal plus tax and tip, when enough parts were printed to check.
    private var calculatedTotal: Money? {
        guard let subtotal, subtotal > .zero, tax != nil || tip != nil else { return nil }
        let base = isDiscountAfterSubtotal ? subtotal - (discount ?? .zero) : subtotal
        return base + (tax ?? .zero) + (tip ?? .zero)
    }

    /// Some receipts print a member discount below the subtotal, so it isn't
    /// already reflected in the subtotal like an item coupon would be.
    var isDiscountAfterSubtotal: Bool {
        guard let subtotal, let discount, discount > .zero, let total = amountToRecord else { return false }
        let extras = (tax ?? .zero) + (tip ?? .zero)
        return subtotal - discount + extras == total && subtotal + extras != total
    }

    /// The discount spread across item prices for a split, when one explains
    /// why the items add up to more than the amount they should.
    var discountSpreadAcrossItems: Money? {
        guard let target = itemTarget, let discount, discount > .zero, !items.isEmpty,
              itemsTotal - target == discount else { return nil }
        return discount
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

    /// Keeps the printed suggestions that are really percentages of one
    /// amount, so a misread number never becomes a tip button. Each must be
    /// its percentage of the bill before tax or after tax, to the cent, and
    /// all on the same one. When the bill isn't known they're kept as read.
    func consistentSuggestions(_ suggestions: [SuggestedTip]) -> [SuggestedTip] {
        // Printed subtotal and tax first: a tip misread from the guide may
        // still be in the draft at this point.
        let printedBill = subtotal.flatMap { subtotal in tax.map { subtotal + $0 } }
        guard let afterTax = printedBill ?? billBeforeTip else { return suggestions }
        let beforeTax = afterTax - (tax ?? .zero)
        func fits(_ base: Money) -> [SuggestedTip] {
            suggestions.filter { abs((base.applying(percent: $0.percent) - $0.amount).minorUnits) <= 1 }
        }
        let onAfterTax = fits(afterTax)
        let onBeforeTax = fits(beforeTax)
        return onAfterTax.count > onBeforeTax.count ? onAfterTax : onBeforeTax
    }

    /// Which amount the printed suggested tips were figured on. Restaurants
    /// differ: most use the bill before tax, some the total after tax. Nil
    /// when nothing was printed, there's no separate tax, or the printed
    /// amounts fit neither.
    var suggestedTipBasis: TipBasis? {
        guard !suggestedTips.isEmpty, let afterTax = billBeforeTip,
              let tax, tax > .zero, afterTax - tax > .zero else { return nil }
        func fits(_ base: Money) -> Bool {
            // One cent of slack for restaurants that round down.
            suggestedTips.allSatisfy { abs((base.applying(percent: $0.percent) - $0.amount).minorUnits) <= 1 }
        }
        switch (fits(afterTax - tax), fits(afterTax)) {
        case (true, false): return .beforeTax
        case (false, true): return .afterTax
        default: return nil
        }
    }

    /// A restaurant-style bill with no tip charged yet: the payer adds one on
    /// the card slip and the merchant adjusts the charge afterwards.
    var leavesTipToPayer: Bool {
        tip == nil && isTippedService == true
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

nonisolated extension ReceiptDraft {
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
            // Old receipts are fine; a decade-old date is far more likely a misread.
            let earliest = calendar.date(byAdding: .year, value: -10, to: now) ?? now
            draft.date = (earliest...latest).contains(date) ? date : nil
        }

        // Negative lines are coupons or discounts, not purchases.
        var couponLines = Money.zero
        draft.items = items.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Self.isSummaryLabel(name) else { return nil }
            if item.price < .zero {
                couponLines = couponLines + Money(minorUnits: -item.price.minorUnits)
                return nil
            }
            guard item.price > .zero,
                  item.price.minorUnits <= ExpenseInputValidator.maximumInputMinorUnits else { return nil }
            return LineItem(id: item.id, name: Self.readableName(name),
                            quantity: Self.purchasedQuantity(item.quantity, name: name), price: item.price)
        }

        // A coupon can be printed as a line, in a discount summary, or both,
        // and the model may misread a percentage as a discount. The reading
        // that makes the items add up to the printed subtotal wins.
        let printedDiscount = discount.map { Money(minorUnits: abs($0.minorUnits)) } ?? .zero
        let candidates = [printedDiscount, couponLines, printedDiscount + couponLines, .zero]
        func reconcilesSubtotal(_ items: [LineItem], _ discount: Money) -> Bool {
            guard let subtotal = draft.subtotal else { return false }
            return items.reduce(Money.zero) { $0 + $1.price } - discount == subtotal
        }
        var chosenDiscount = candidates.first { reconcilesSubtotal(draft.items, $0) }
        // "2 @ 3.49" rows are sometimes read as the unit price. Use line totals
        // only when that makes the items match the printed subtotal exactly.
        if chosenDiscount == nil, draft.items.contains(where: { $0.quantity > 1 }) {
            let lineTotals = draft.items.map { item -> LineItem in
                var line = item
                if item.quantity > 1 { line.price = Money(minorUnits: item.price.minorUnits * Int64(item.quantity)) }
                return line
            }
            if let discount = candidates.first(where: { reconcilesSubtotal(lineTotals, $0) }) {
                draft.items = lineTotals
                chosenDiscount = discount
            }
        }
        var appliedDiscount = chosenDiscount ?? max(printedDiscount, couponLines)
        // A discount printed below the subtotal applies to the total instead.
        if appliedDiscount == .zero, printedDiscount > .zero,
           let subtotal = draft.subtotal, let total = draft.total {
            let tip = draft.tip ?? .zero
            if subtotal - printedDiscount + (draft.tax ?? .zero) + tip == total || subtotal - printedDiscount + tip == total {
                appliedDiscount = printedDiscount
            }
        }
        draft.discount = appliedDiscount > .zero ? appliedDiscount : nil
        if draft.discount != nil, let subtotal = draft.subtotal, let total = draft.total,
           subtotal - appliedDiscount + (draft.tip ?? .zero) == total, draft.tax != nil,
           subtotal - appliedDiscount + (draft.tax ?? .zero) + (draft.tip ?? .zero) != total {
            draft.tax = nil
        }

        if let subtotal = draft.subtotal, let total = draft.total {
            let base = draft.isDiscountAfterSubtotal ? subtotal - appliedDiscount : subtotal
            // A tip line is often a printed suggestion. When the total already
            // matches without it, nothing was charged.
            if let tip = draft.tip, base + (draft.tax ?? .zero) == total, base + (draft.tax ?? .zero) + tip != total {
                draft.tip = nil
            }
            // The model sometimes copies another amount into tax, or misses a
            // tax amount that recognition dropped. When the printed parts don't
            // add up, the remainder is the tax and fees actually charged, as
            // long as it is a plausible share of the bill.
            let tip = draft.tip ?? .zero
            let remainder = total - base - tip
            if let tax = draft.tax, base + tax + tip != total,
               remainder >= .zero, remainder.minorUnits * 100 <= base.minorUnits * 35 {
                draft.tax = remainder > .zero ? remainder : nil
            }
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

    /// Pack sizes and weights such as "10枚", "5kg", or "12CT" describe one
    /// item; they are not a count of items bought.
    static func purchasedQuantity(_ quantity: Int, name: String) -> Int {
        let count = max(1, min(quantity, 99))
        guard count > 1 else { return 1 }
        return packSize(count, in: name) == nil ? count : 1
    }

    /// The text of a pack size or weight equal to `count`, such as "5kg".
    static func packSize(_ count: Int, in text: String) -> String? {
        let units = "kg|g|lb|lbs|oz|l|ml|ct|pk|pack|枚|个|斤|克|千克|公斤|升|毫升|片|包|瓶|袋"
        // "5kg" or "12CT", or a piece count in parentheses such as "Dumplings (6)".
        let pattern = "(?<![0-9.])\(count)\\s*(\(units))(?![a-z])|\\(\\s*\(count)\\s*(pcs?|pieces?|个|只)?\\s*\\)"
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(text[range])
    }

    /// Ties each item to the row it was printed on. The model is told to copy
    /// amounts, but on restaurant receipts it sometimes adds an add-on into
    /// its item, multiplies a line by its quantity, or lists an item twice.
    /// The recognized text is the source of truth for every price:
    /// - each item takes the last amount printed on its own row,
    /// - a second item for an already-used row is dropped,
    /// - priced add-on rows ("- add avocado $3.00") join the item above them,
    ///   but only when that makes the items match the printed subtotal.
    /// Items whose names can't be found in the text are kept as read.
    func grounded(in rows: [String]) -> ReceiptDraft {
        var draft = correctingPackSizes(using: rows).groundingTip(in: rows).groundingAmounts(in: rows)
        draft.suggestedTips = draft.consistentSuggestions(Self.suggestedTips(in: rows))
        func isAddOnRow(_ index: Int) -> Bool {
            let text = rows[index].trimmingCharacters(in: .whitespaces)
            return text.hasPrefix("-") || text.hasPrefix("+") || text.hasPrefix("•")
        }

        var usedRows = Set<Int>()
        var matched: [(item: LineItem, row: Int?)] = []
        for item in draft.items {
            let base = Self.baseItemName(item.name)
            guard !base.isEmpty else { matched.append((item, nil)); continue }
            let candidates = rows.indices.filter { rows[$0].localizedCaseInsensitiveContains(base) }
            if let row = candidates.first(where: { !usedRows.contains($0) && !isAddOnRow($0) && Self.lastAmount(in: rows[$0]) != nil }),
               let price = Self.lastAmount(in: rows[row]) {
                usedRows.insert(row)
                var line = item
                line.name = base
                line.price = price
                matched.append((line, row))
            } else if candidates.contains(where: { usedRows.contains($0) || isAddOnRow($0) }) {
                // A repeat of an item already listed, or an add-on that is
                // handled with its item below.
                continue
            } else {
                matched.append((item, nil))
            }
        }

        var addOns: [Int: Money] = [:]
        let itemForRow = Dictionary(matched.enumerated().compactMap { index, entry in entry.row.map { ($0, index) } },
                                    uniquingKeysWith: { first, _ in first })
        var currentItem: Int?
        for index in rows.indices {
            if let item = itemForRow[index] {
                currentItem = item
            } else if let amount = Self.lastAmount(in: rows[index]) {
                if isAddOnRow(index), let currentItem, amount > .zero {
                    addOns[currentItem, default: .zero] = addOns[currentItem, default: .zero] + amount
                } else if !isAddOnRow(index) {
                    currentItem = nil
                }
            }
        }

        let plain = matched.map(\.item)
        let claimed = Set(matched.compactMap(\.row))
        guard !addOns.isEmpty else {
            draft.items = plain
            return draft.recoveringMissedItems(in: rows, claimed: claimed)
        }
        let withAddOns = matched.enumerated().map { index, entry -> LineItem in
            var line = entry.item
            if let extra = addOns[index] { line.price = line.price + extra }
            return line
        }
        func distance(_ items: [LineItem]) -> Int64 {
            guard let subtotal = draft.subtotal.map({ Money(minorUnits: abs($0.minorUnits)) }) else { return 0 }
            return abs((items.reduce(Money.zero) { $0 + $1.price } - subtotal).minorUnits)
        }
        // Add-ons are charged on most receipts, so they win ties.
        draft.items = distance(plain) < distance(withAddOns) ? plain : withAddOns
        return draft.recoveringMissedItems(in: rows, claimed: claimed)
    }

    /// An item's name without add-on details the model may have appended,
    /// such as "Grilled Salmon - well done - no asparagus".
    static func baseItemName(_ name: String) -> String {
        var base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" - ", " + ", " – ", " — "] {
            if let range = base.range(of: separator) { base = String(base[..<range.lowerBound]) }
        }
        return base.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The last amount printed on a row, such as "$28.00", "-1.00", or "12,50 €".
    static func lastAmount(in row: String) -> Money? {
        amounts(in: row).last
    }

    /// Every amount printed on a row, in order.
    static func amounts(in row: String) -> [Money] {
        let pattern = #"[-−]?\s?[$€£¥]?\s?(?<![\d.,])\d+(?:[.,]\d{3})*[.,]\d{2}(?!\d)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: row, range: NSRange(row.startIndex..., in: row)).compactMap { match in
            Range(match.range, in: row).flatMap { ReceiptNumberParser.money(from: String(row[$0])) }
        }
    }

    private static let percentFirstPattern = #"(?<![\d.])(\d{1,2})\s?%[^\d%]{0,14}?[$€£¥]?\s?(\d+[.,]\d{2})(?!\d)"#
    private static let amountFirstPattern = #"[$€£¥]?\s?(\d+[.,]\d{2})\s*\(\s*(\d{1,2})\s?%\s*\)"#

    /// Percentages printed with an amount on a row, such as "18% $7.02".
    private static func percentPairs(in row: String) -> [SuggestedTip] {
        guard let percentFirst = try? NSRegularExpression(pattern: percentFirstPattern),
              let amountFirst = try? NSRegularExpression(pattern: amountFirstPattern) else { return [] }
        let range = NSRange(row.startIndex..., in: row)
        func text(_ match: NSTextCheckingResult, _ group: Int) -> String? {
            Range(match.range(at: group), in: row).map { String(row[$0]) }
        }
        var pairs: [SuggestedTip] = []
        for match in percentFirst.matches(in: row, range: range) {
            if let percent = text(match, 1).flatMap({ Int($0) }),
               let amount = text(match, 2).flatMap(ReceiptNumberParser.money(from:)) {
                pairs.append(SuggestedTip(percent: percent, amount: amount))
            }
        }
        for match in amountFirst.matches(in: row, range: range) {
            if let percent = text(match, 2).flatMap({ Int($0) }),
               let amount = text(match, 1).flatMap(ReceiptNumberParser.money(from:)) {
                pairs.append(SuggestedTip(percent: percent, amount: amount))
            }
        }
        return pairs
    }

    /// The rows of a printed suggested-tip table: a "Suggested tip" or "Tip
    /// guide" heading and the rows after it, or a row that lists several
    /// percentages or a percentage with its tip and new total. Text
    /// recognition can split a table's columns onto separate rows, such as
    /// "18%", "Tip $7.94", and "Total $52.04", so after a heading every row
    /// with an amount or a percentage counts until the table clearly ends.
    /// Nothing on these rows was charged, so their amounts are never the
    /// receipt's tip or total. Charged service charges and tax rates aren't
    /// included, and neither are payment rows.
    static func tipTableRows(in rows: [String]) -> Set<Int> {
        let headings = ["suggest", "guide", "convenience", "calculat", "建议", "参考"]
        let charged = ["tax", "vat", "gst", "hst", "税", "service charge", "服务费", "subtotal", "小计"]
        let payment = ["visa", "mastercard", "amex", "card", "cash", "change", "auth", "approv", "支付", "找零"]
        var table = Set<Int>()
        var rowsLeft = 0
        for (index, row) in rows.enumerated() {
            let lowered = row.lowercased()
            if headings.contains(where: lowered.contains) {
                table.insert(index)
                rowsLeft = 3
                continue
            }
            let isCharged = charged.contains(where: { lowered.contains($0) && !lowered.contains("suggest") })
            let isPayment = payment.contains(where: lowered.contains)
            let pairs = percentPairs(in: row)
            if rowsLeft > 0 {
                let looksLikeTable = !isCharged && !isPayment && (row.contains("%") || !amounts(in: row).isEmpty)
                if looksLikeTable {
                    table.insert(index)
                    rowsLeft = 3
                } else {
                    rowsLeft -= 1
                }
                continue
            }
            guard !isCharged, !pairs.isEmpty else { continue }
            if pairs.count > 1 || (amounts(in: row).count > 1 && lowered.contains("total")) {
                table.insert(index)
            }
        }
        return table
    }

    /// Reads a printed suggested-tip table, such as "18% $7.02  20% $7.80".
    static func suggestedTips(in rows: [String]) -> [SuggestedTip] {
        let tableRows = tipTableRows(in: rows).sorted().map { rows[$0] }
        var tips = tableRows.flatMap(percentPairs(in:))
        // Columns split onto separate rows ("15%", "Tip $6.62") read in order.
        if tips.isEmpty { tips = percentPairs(in: tableRows.joined(separator: " ")) }
        var seen = Set<Int>()
        return tips.filter { (5...40).contains($0.percent) && $0.amount > .zero && seen.insert($0.percent).inserted }
    }

    /// Drops a tip the receipt doesn't actually charge. Models sometimes read
    /// the tax, or a row of the suggested-tip table, as the tip; the first
    /// becomes the tax again. A tip printed on its own tip or service line
    /// is kept.
    func groundingTip(in rows: [String]) -> ReceiptDraft {
        guard let tip, tip > .zero, !rows.isEmpty else { return self }
        func mentions(_ row: String, _ words: [String]) -> Bool {
            words.contains { row.localizedCaseInsensitiveContains($0) }
        }
        let tipWords = ["tip", "gratuity", "service", "svc", "小费", "服务费", "pourboire", "propina", "trinkgeld", "mancia"]
        let taxWords = ["tax", "vat", "gst", "hst", "pst", "税"]
        let table = Self.tipTableRows(in: rows)

        let isCharged = rows.indices.contains {
            !table.contains($0) && mentions(rows[$0], tipWords) && Self.amounts(in: rows[$0]).contains(tip)
        }
        guard !isCharged else { return self }
        let isTax = rows.indices.contains {
            !table.contains($0) && mentions(rows[$0], taxWords) && !mentions(rows[$0], tipWords)
                && Self.lastAmount(in: rows[$0]) == tip
        }
        let isSuggestion = table.contains { Self.amounts(in: rows[$0]).contains(tip) }
        guard isTax || isSuggestion else { return self }

        var draft = self
        draft.tip = nil
        if isTax, draft.tax == nil { draft.tax = tip }
        return draft
    }

    /// Keeps the subtotal, tax, and total to amounts the receipt prints. The
    /// model can copy a total from the suggested-tip table ("18% … Total
    /// $52.04") or add numbers up itself; either is replaced by the amount on
    /// the receipt's own labeled row when there is one.
    func groundingAmounts(in rows: [String]) -> ReceiptDraft {
        guard !rows.isEmpty else { return self }
        let table = Self.tipTableRows(in: rows)
        let receiptRows = rows.indices.filter { !table.contains($0) }.map { rows[$0] }
        let printed = Set(receiptRows.flatMap(Self.amounts(in:)))
        let subtotalWords = ["subtotal", "sub total", "sub-total", "小计"]

        func labeled(_ words: [String], excluding excluded: [String], pick: ([Money]) -> Money?) -> Money? {
            let found = receiptRows.compactMap { row -> Money? in
                let lowered = row.lowercased()
                guard words.contains(where: lowered.contains), !excluded.contains(where: lowered.contains) else { return nil }
                return Self.lastAmount(in: row).flatMap { $0 > .zero ? $0 : nil }
            }
            return pick(found)
        }
        func grounded(_ value: Money?, _ label: Money?) -> Money? {
            guard let value, printed.contains(value) else { return label ?? value }
            return value
        }

        var draft = self
        draft.subtotal = grounded(subtotal, labeled(subtotalWords, excluding: [], pick: \.last))
        draft.tax = grounded(tax, labeled(["tax", "vat", "gst", "hst", "税"],
                                          excluding: ["total", "合计", "incl", "含税"] , pick: \.last))
        // The largest labeled total: "Total savings" and the like are smaller.
        draft.total = grounded(total, labeled(["total", "合计", "总计", "amount due", "balance due", "应付", "实付"],
                                              excluding: subtotalWords + ["saving", "节省", "优惠"], pick: { $0.max() }))
        // A printed total that is exactly subtotal plus tax (and any charged
        // tip) beats one that isn't, wherever the other one came from.
        if let subtotal = draft.subtotal, let tax = draft.tax, draft.discount == nil {
            let expected = subtotal + tax + (draft.tip ?? .zero)
            if draft.total != expected, printed.contains(expected) { draft.total = expected }
        }
        draft.totalIsPrinted = draft.total.map(printed.contains)
        return draft
    }

    /// Adds priced rows the model skipped above the subtotal, but only when
    /// together they are exactly what is missing from it, so a header line
    /// is never mistaken for an item.
    func recoveringMissedItems(in rows: [String], claimed: Set<Int>) -> ReceiptDraft {
        guard let subtotal, subtotal > itemsTotal else { return self }
        let summaryWords = ["subtotal", "sub total", "小计", "tax", "税", "total", "合计", "tip", "gratuity", "小费",
                            "discount", "coupon", "saving", "优惠", "折扣", "visa", "card", "cash", "change"]
        let table = Self.tipTableRows(in: rows)
        guard let end = rows.indices.first(where: { Self.amounts(in: rows[$0]).contains(subtotal) }) else { return self }

        var recovered: [LineItem] = []
        for index in (0..<end) where !claimed.contains(index) && !table.contains(index) {
            let row = rows[index]
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            let lowered = row.lowercased()
            guard !trimmed.hasPrefix("-"), !trimmed.hasPrefix("+"), !trimmed.hasPrefix("•"),
                  !summaryWords.contains(where: lowered.contains),
                  let price = Self.lastAmount(in: row), price > .zero else { continue }
            let name = row.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { Self.amounts(in: $0).isEmpty }
                .max { $0.filter(\.isLetter).count < $1.filter(\.isLetter).count } ?? ""
            guard name.contains(where: \.isLetter) else { continue }
            recovered.append(LineItem(name: Self.readableName(name), quantity: 1, price: price))
        }
        guard !recovered.isEmpty,
              itemsTotal + recovered.reduce(.zero, { $0 + $1.price }) == subtotal else { return self }
        var draft = self
        draft.items += recovered
        return draft
    }

    /// The model sometimes moves a pack size out of the name into the
    /// quantity ("鸡蛋 10枚" becomes 鸡蛋 × 10). The recognized row still has
    /// it, so it goes back into the name and the quantity becomes 1.
    func correctingPackSizes(using rows: [String]) -> ReceiptDraft {
        var draft = self
        for index in draft.items.indices where draft.items[index].quantity > 1 {
            let item = draft.items[index]
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  let row = rows.first(where: { $0.localizedCaseInsensitiveContains(name) }),
                  let size = Self.packSize(item.quantity, in: row) else { continue }
            draft.items[index].quantity = 1
            if !name.localizedCaseInsensitiveContains(size) {
                draft.items[index].name = "\(name) \(size)"
            }
        }
        return draft
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

/// What a percentage tip is figured on.
nonisolated enum TipBasis: Equatable, Sendable {
    case beforeTax
    case afterTax
}

/// One entry of a receipt's printed suggested-tip table.
nonisolated struct SuggestedTip: Equatable, Sendable {
    var percent: Int
    var amount: Money
}
