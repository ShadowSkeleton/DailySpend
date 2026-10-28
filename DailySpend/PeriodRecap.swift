import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One expense as Insights' summaries see it.
nonisolated struct SpendingRecord: Equatable, Sendable {
    var money: Money
    var category: String
    var note: String
    var date: Date
}

// MARK: - Periods

/// The stretch of time Insights summarizes, and the stretch of the same
/// length it is compared with. Periods are whole days: the date picker saves
/// a day, so the time an expense happened to be saved never matters.
nonisolated struct SpendingPeriod: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The 1st of this month through today, against the 1st of last
        /// month through the same day.
        case monthToDate
        /// A whole month, against the month before.
        case month
        /// The last few months through today, against as many months before them.
        case recentMonths(Int)
        /// January 1 through today, against the same dates last year.
        case yearToDate
        /// Everything, with nothing to compare.
        case allTime
    }

    var kind: Kind
    /// The period runs from `start` up to, not including, `end`.
    var start: Date
    var end: Date
    var previousStart: Date?
    var previousEnd: Date?
    /// "Now" when the period was made, so its words never depend on the clock.
    var now: Date

    func contains(_ date: Date) -> Bool { date >= start && date < end }

    func previousContains(_ date: Date) -> Bool {
        guard let previousStart, let previousEnd else { return false }
        return date >= previousStart && date < previousEnd
    }

    /// Only a past month is over; every other period runs to today.
    var isComplete: Bool { kind == .month }
    /// The budget is monthly, so only months are measured against it.
    var usesBudget: Bool { kind == .monthToDate || kind == .month }

    private static func monthStart(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func adding(_ component: Calendar.Component, _ value: Int, to date: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    /// The start of tomorrow: to-date periods include all of today.
    private static func endOfToday(_ now: Date, _ calendar: Calendar) -> Date {
        adding(.day, 1, to: calendar.startOfDay(for: now), calendar)
    }

    static func monthToDate(now: Date, calendar: Calendar = .current) -> SpendingPeriod {
        let start = monthStart(now, calendar)
        // The same day last month; a shorter month stops at its last day.
        let sameDayLastMonth = adding(.month, -1, to: calendar.startOfDay(for: now), calendar)
        return SpendingPeriod(kind: .monthToDate, start: start, end: endOfToday(now, calendar),
                              previousStart: adding(.month, -1, to: start, calendar),
                              previousEnd: min(adding(.day, 1, to: sameDayLastMonth, calendar), start), now: now)
    }

    /// The month containing `date`; the current month runs through today.
    static func month(containing date: Date, now: Date, calendar: Calendar = .current) -> SpendingPeriod {
        let start = monthStart(date, calendar)
        if start == monthStart(now, calendar) { return monthToDate(now: now, calendar: calendar) }
        return SpendingPeriod(kind: .month, start: start, end: adding(.month, 1, to: start, calendar),
                              previousStart: adding(.month, -1, to: start, calendar), previousEnd: start, now: now)
    }

    static func recentMonths(_ months: Int, now: Date, calendar: Calendar = .current) -> SpendingPeriod {
        let end = endOfToday(now, calendar)
        let start = adding(.month, -months, to: end, calendar)
        return SpendingPeriod(kind: .recentMonths(months), start: start, end: end,
                              previousStart: adding(.month, -2 * months, to: end, calendar), previousEnd: start, now: now)
    }

    static func yearToDate(now: Date, calendar: Calendar = .current) -> SpendingPeriod {
        let start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        let end = endOfToday(now, calendar)
        return SpendingPeriod(kind: .yearToDate, start: start, end: end,
                              previousStart: adding(.year, -1, to: start, calendar),
                              previousEnd: adding(.year, -1, to: end, calendar), now: now)
    }

    static func allTime(now: Date) -> SpendingPeriod {
        SpendingPeriod(kind: .allTime, start: .distantPast, end: .distantFuture,
                       previousStart: nil, previousEnd: nil, now: now)
    }
}

// MARK: - Recap facts

/// The facts behind a period's summary, all worked out by code. The model
/// only puts them into words.
nonisolated struct PeriodRecap: Equatable, Sendable {
    struct CategoryTotal: Equatable, Sendable {
        var category: String
        var total: Money
        var previous: Money
    }

    var period: SpendingPeriod
    var total: Money
    var count: Int
    /// The period before, when the records cover it. Zero when nothing was
    /// spent in it.
    var previousTotal: Money?
    /// Every category spent on in this period or the one before, largest first.
    var categories: [CategoryTotal]
    var biggest: SpendingRecord
    var budget: Money?
    /// This month's expenses dated after today, which Home already counts.
    var laterThisMonth: Money

    /// The summary of `period`, or nil if nothing was spent in it.
    static func make(records: [SpendingRecord], period: SpendingPeriod, budget: Money?,
                     calendar: Calendar = .current) -> PeriodRecap? {
        let inPeriod = records.filter { period.contains($0.date) }
        guard let biggest = inPeriod.max(by: { ($0.money, $1.date) < ($1.money, $0.date) }) else { return nil }
        let inPrevious = coversPrevious(of: period, records: records) ? records.filter { period.previousContains($0.date) } : nil

        func sum(_ items: [SpendingRecord]) -> Money { items.reduce(.zero) { $0 + $1.money } }
        let previousByCategory = Dictionary(grouping: inPrevious ?? [], by: \.category).mapValues(sum)
        let thisByCategory = Dictionary(grouping: inPeriod, by: \.category).mapValues(sum)
        // Categories from either period, so one that stopped counts as a change.
        let categories = Set(thisByCategory.keys).union(previousByCategory.keys)
            .map { CategoryTotal(category: $0, total: thisByCategory[$0] ?? .zero, previous: previousByCategory[$0] ?? .zero) }
            .sorted { ($0.total, $1.category) > ($1.total, $0.category) }
        let later = period.kind == .monthToDate
            ? sum(records.filter { $0.date >= period.end && calendar.isDate($0.date, equalTo: period.start, toGranularity: .month) })
            : .zero
        return PeriodRecap(period: period, total: sum(inPeriod), count: inPeriod.count,
                           previousTotal: inPrevious.map(sum),
                           categories: categories, biggest: biggest,
                           budget: period.usesBudget ? budget.flatMap { $0 > .zero ? $0 : nil } : nil,
                           laterThisMonth: later)
    }

    /// True when the records reach back into the first half of the period
    /// before. Someone who started tracking partway through it has no fair
    /// comparison, so they see their total instead of "more than nothing".
    static func coversPrevious(of period: SpendingPeriod, records: [SpendingRecord]) -> Bool {
        guard let previousStart = period.previousStart, let previousEnd = period.previousEnd,
              let earliest = records.map(\.date).min() else { return false }
        return earliest < previousStart.addingTimeInterval(previousEnd.timeIntervalSince(previousStart) / 2)
    }

    /// The headline: how much more or less than the period before, and the
    /// category that moved most that way. Nil without a period to compare
    /// with, or when the two are less than 1 apart.
    var change: (amount: Money, driver: String, driverChange: Money)? {
        guard let previousTotal else { return nil }
        let diff = total - previousTotal
        guard abs(diff.amount) >= 1 else { return nil }
        var driver = ""
        var driverChange: Money?
        // Sorted so equal changes always name the same category.
        for category in categories.sorted(by: { $0.category < $1.category }) {
            let moved = category.total - category.previous
            if let best = driverChange, diff > .zero ? moved <= best : moved >= best { continue }
            driverChange = moved
            driver = category.category
        }
        return (diff, driver, driverChange ?? diff)
    }

    /// Compared with the period before, and within 1 of it.
    var isAboutTheSame: Bool { previousTotal != nil && change == nil }

    /// Change against the period before, in whole percent. Left out in the
    /// first 3 days of a period and past +300%, where one bill's timing or a
    /// tiny start makes a percentage misleading; the amount still shows.
    var percentChange: Int? {
        guard let previousTotal, previousTotal > .zero,
              period.end.timeIntervalSince(period.start) > 3 * 86_400 else { return nil }
        let change = Double(total.minorUnits - previousTotal.minorUnits) / Double(previousTotal.minorUnits) * 100
        let percent = Int(change.rounded())
        return percent > 300 ? nil : percent
    }

    /// A category that moved the other way by more than the driver did, so
    /// the summary never seems to contradict the headline.
    var otherWayMover: (category: String, change: Money)? {
        guard let change else { return nil }
        let wentUp = change.amount > .zero
        let moves: [(category: String, change: Money)] = categories.map {
            (category: $0.category, change: $0.total - $0.previous)
        }
        let otherWay = moves.filter { wentUp ? $0.change < .zero : $0.change > .zero }
        guard let mover = otherWay.max(by: { abs($0.change.minorUnits) < abs($1.change.minorUnits) }),
              abs(mover.change.minorUnits) > abs(change.driverChange.minorUnits) else { return nil }
        return mover
    }
}

// MARK: - Words

nonisolated enum RecapText {
    private static var isZh: Bool { L10n.isZh }

    static func money(_ value: Money) -> String {
        value.amount.formatted(.currency(code: L10n.currencyCode))
    }

    /// Whole dollars for the quick look; Details keeps the cents.
    static func wholeMoney(_ value: Money) -> String {
        value.amount.formatted(.currency(code: L10n.currencyCode).precision(.fractionLength(0)))
    }

    private static func positive(_ value: Money) -> Money { Money(minorUnits: abs(value.minorUnits)) }

    /// "September", or "September 2025" when it isn't this year.
    static func monthName(_ date: Date, now: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.month(.wide)) : date.formatted(.dateTime.month(.wide).year())
    }

    private static func yearName(_ date: Date) -> String { date.formatted(.dateTime.year()) }

    /// The card's title: "October So Far", "September", "Last 3 Months".
    static func title(for period: SpendingPeriod) -> String {
        switch period.kind {
        case .monthToDate:
            let month = monthName(period.start, now: period.now)
            return isZh ? "\(month)至今" : "\(month) So Far"
        case .month: return monthName(period.start, now: period.now)
        case .recentMonths(let months): return isZh ? "近\(months)个月" : "Last \(months) Months"
        case .yearToDate:
            let year = yearName(period.start)
            return isZh ? "\(year)至今" : "\(year) So Far"
        case .allTime: return isZh ? "全部" : "All Time"
        }
    }

    /// Where the spending happened: "in October so far", "近3个月".
    private static func spentWhen(_ period: SpendingPeriod) -> String {
        switch period.kind {
        case .monthToDate:
            let month = monthName(period.start, now: period.now)
            return isZh ? "\(month)至今" : "in \(month) so far"
        case .month:
            let month = monthName(period.start, now: period.now)
            return isZh ? month : "in \(month)"
        case .recentMonths(let months): return isZh ? "近\(months)个月" : "in the last \(months) months"
        case .yearToDate:
            let year = yearName(period.start)
            return isZh ? "\(year)至今" : "in \(year) so far"
        case .allTime: return isZh ? "累计" : "in total"
        }
    }

    /// The period it's compared with, as the facts name it.
    private static func previousName(_ period: SpendingPeriod) -> String {
        let previous = period.previousStart ?? period.start
        switch period.kind {
        case .monthToDate:
            let month = monthName(previous, now: period.now)
            return isZh ? "\(month)同期" : "the same days of \(month)"
        case .month: return monthName(previous, now: period.now)
        case .recentMonths(let months): return isZh ? "之前\(months)个月" : "the \(months) months before"
        case .yearToDate:
            let year = yearName(previous)
            return isZh ? "\(year)同期" : "the same time in \(year)"
        case .allTime: return ""
        }
    }

    /// The comparison in plain words: "this time last month".
    static func comparisonName(_ period: SpendingPeriod) -> String {
        switch period.kind {
        case .monthToDate: return isZh ? "上月同期" : "this time last month"
        case .yearToDate: return isZh ? "去年同期" : "this time last year"
        default: return previousName(period)
        }
    }

    /// The big number: "$3,219 less" in green or "$219 more" in red, or the
    /// total when there's nothing to compare.
    static func headline(for recap: PeriodRecap) -> (text: String, tone: Tile.Tone) {
        guard let change = recap.change else { return (wholeMoney(recap.total), .plain) }
        let up = change.amount > .zero
        let amount = wholeMoney(positive(change.amount))
        return (isZh ? "\(up ? "多花" : "少花") \(amount)" : "\(amount) \(up ? "more" : "less")", up ? .up : .down)
    }

    /// Finishes the big number's sentence: "than this time last month".
    static func headlineCaption(for recap: PeriodRecap) -> String {
        let against = comparisonName(recap.period)
        if recap.change != nil { return isZh ? "与\(against)相比" : "than \(against)" }
        if recap.isAboutTheSame { return isZh ? "与\(against)基本持平" : "About the same as \(against)" }
        let soFar = recap.period.kind == .monthToDate || recap.period.kind == .yearToDate
        return isZh ? (soFar ? "至今已花" : "已花") : (soFar ? "spent so far" : "spent")
    }

    /// Two plain lines under it: what you've spent, then what moved. Written
    /// by the app so they always match the numbers.
    static func quickLines(for recap: PeriodRecap) -> [String] {
        let past = recap.period.isComplete
        let spent = isZh ? "已花 \(wholeMoney(recap.total))" : "\(past ? "You spent" : "You’ve spent") \(wholeMoney(recap.total))"
        if let change = recap.change {
            let category = L10n.categoryName(change.driver)
            let up = change.driverChange > .zero
            let amount = wholeMoney(positive(change.driverChange))
            return [spent, isZh ? "\(category)\(up ? "多" : "少")了 \(amount)"
                                : "\(category) \(past ? "was" : "is") \(up ? "up" : "down") \(amount)"]
        }
        let lead = recap.previousTotal != nil ? spent
            : (isZh ? "共 \(recap.count) 笔" : "\(recap.count) \(recap.count == 1 ? "expense" : "expenses")")
        guard let top = recap.categories.first.map({ L10n.categoryName($0.category) }) else { return [lead] }
        return [lead, isZh ? "花在\(top)最多" : "Most on \(top)"]
    }

    /// What the "?" explains.
    static func comparisonExplanation(_ period: SpendingPeriod) -> String {
        switch period.kind {
        case .monthToDate:
            return isZh ? "对比的是【本月1号到今天】与【上月1号到同一天】的支出总额，按整天计算。记在本月稍后日期的支出到那天才计入。"
                        : "This compares your spending from the 1st of this month through today with the 1st of last month through the same day, counting whole days. Expenses dated later this month count once that day comes."
        case .month:
            return isZh ? "此数据对比的是这个月与上一个月的全月支出总额。"
                        : "This compares the whole month's spending with the whole month before it."
        case .recentMonths(let months):
            return isZh ? "此数据对比的是最近\(months)个月与再之前\(months)个月的支出总额。"
                        : "This compares the last \(months) months with the \(months) months before them."
        case .yearToDate:
            return isZh ? "此数据对比的是今年1月1日至今与去年同期的支出总额。"
                        : "This compares this year from January 1 to today with the same dates last year."
        case .allTime: return ""
        }
    }

    /// A key number shown under Details.
    struct Tile: Equatable, Sendable {
        enum Tone: Sendable { case plain, up, down }
        var label: String
        var value: String
        var tone: Tone = .plain
    }

    /// This period, the one before, and the change; or, with nothing to
    /// compare, the total and how many expenses.
    static func tiles(for recap: PeriodRecap) -> [Tile] {
        let period = recap.period
        let current: String
        switch period.kind {
        case .monthToDate, .yearToDate: current = isZh ? "至今" : "So far"
        default: current = isZh ? "本期" : "This period"
        }
        guard let previous = recap.previousTotal else {
            return [Tile(label: current, value: money(recap.total)),
                    Tile(label: isZh ? "笔数" : "Expenses", value: "\(recap.count)")]
        }
        let before: String
        let previousStart = period.previousStart ?? period.start
        let shortMonth = previousStart.formatted(.dateTime.month(.abbreviated))
        switch period.kind {
        case .monthToDate: before = isZh ? "上月同期" : "Same days, \(shortMonth)"
        case .month: before = shortMonth
        case .recentMonths(let months): before = isZh ? "之前\(months)个月" : "\(months) months before"
        case .yearToDate: before = isZh ? "去年同期" : "Same time last year"
        case .allTime: before = ""
        }
        let change: Tile
        if let percent = recap.percentChange {
            change = Tile(label: isZh ? "变化" : "Change",
                          value: percent == 0 ? "0%" : "\(percent > 0 ? "+" : "−")\(abs(percent))%",
                          tone: percent > 0 ? .up : percent < 0 ? .down : .plain)
        } else {
            // No percentage early in a period or from a tiny start; the amount says it.
            let diff = recap.total - previous
            change = Tile(label: isZh ? "变化" : "Change", value: (diff < .zero ? "−" : "+") + money(positive(diff)),
                          tone: diff > .zero ? .up : diff < .zero ? .down : .plain)
        }
        return [Tile(label: current, value: money(recap.total)), Tile(label: before, value: money(previous)), change]
    }

    static func biggestLabel(_ record: SpendingRecord) -> String {
        var firstLine = record.note.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        // "Shop at Apple 1200" names the place; the amount is shown on its own.
        firstLine = firstLine.replacingOccurrences(of: #"\s+[$€£¥]?\d[\d,]*(?:\.\d+)?\s*(?:dollars?|bucks|元|块)?$"#,
                                                   with: "", options: [.regularExpression, .caseInsensitive])
        guard !firstLine.isEmpty else { return L10n.categoryName(record.category) }
        // A long note would swallow the sentence; its start names the expense.
        return firstLine.count > 32 ? firstLine.prefix(31).trimmingCharacters(in: .whitespaces) + "…" : firstLine
    }

    /// The facts as short lines, shown under "Facts" and given to the model.
    static func facts(for recap: PeriodRecap) -> [String] {
        let period = recap.period
        var lines: [String] = []
        lines.append(isZh
            ? "\(spentWhen(period))共支出 \(money(recap.total))，共 \(recap.count) 笔"
            : "Spent \(money(recap.total)) \(spentWhen(period)) across \(recap.count) \(recap.count == 1 ? "expense" : "expenses")")
        let name = previousName(period)
        if let previous = recap.previousTotal {
            let diff = recap.total - previous
            if previous == .zero {
                lines.append(isZh ? "\(name)没有支出" : "Nothing spent in \(name)")
            } else if recap.isAboutTheSame || recap.percentChange == 0 {
                lines.append(isZh ? "与\(name)持平（\(name)共 \(money(previous))）" : "About the same as \(name), which came to \(money(previous))")
            } else if let percent = recap.percentChange {
                lines.append(isZh
                    ? "比\(name)\(percent > 0 ? "多" : "少") \(abs(percent))%（\(name)共 \(money(previous))）"
                    : "\(abs(percent))% \(percent > 0 ? "more" : "less") than \(name), which came to \(money(previous))")
            } else {
                lines.append(isZh
                    ? "比\(name)\(diff > .zero ? "多" : "少") \(money(positive(diff)))（\(name)共 \(money(previous))）"
                    : "\(money(positive(diff))) \(diff > .zero ? "more" : "less") than \(name), which came to \(money(previous))")
            }
        }
        if let top = recap.categories.first {
            let share = recap.total.minorUnits > 0 ? Int((Double(top.total.minorUnits) / Double(recap.total.minorUnits) * 100).rounded()) : 0
            let category = L10n.categoryName(top.category)
            // A share of this period's spending, worded so it isn't read as the change.
            let soFar = period.kind == .monthToDate || period.kind == .yearToDate
            lines.append(isZh
                ? "\(category)占支出的 \(share)%（\(money(top.total))）"
                : "\(category) \(period.isComplete ? "was" : "is") \(share)% of your spending\(soFar ? " so far" : "") (\(money(top.total)))")
        }
        if let change = recap.change {
            // The category that moved the total, so this agrees with the headline.
            // Words, not a sign, so the model can't misread the direction.
            let rose = change.driverChange > .zero
            let category = L10n.categoryName(change.driver)
            let amount = money(positive(change.driverChange))
            lines.append(isZh
                ? "变化最大：\(category)比\(name)\(rose ? "增加" : "减少") \(amount)"
                : "\(category) \(rose ? "rose" : "fell") the most: \(rose ? "up" : "down") \(amount) from \(name)")
            if let other = recap.otherWayMover {
                let otherRose = other.change > .zero
                lines.append(isZh
                    ? "\(L10n.categoryName(other.category))反向变化：\(otherRose ? "增加" : "减少") \(money(positive(other.change)))"
                    : "\(L10n.categoryName(other.category)) went the other way: \(otherRose ? "up" : "down") \(money(positive(other.change))) from \(name)")
            }
        }
        let day = recap.biggest.date.formatted(.dateTime.month(.abbreviated).day())
        lines.append(isZh
            ? "最大一笔：\(money(recap.biggest.money))，\(biggestLabel(recap.biggest))（\(day)）"
            : "Largest expense: \(money(recap.biggest.money)), \(biggestLabel(recap.biggest)) (\(day))")
        if let budget = recap.budget {
            let left = budget - recap.total
            let over = money(Money(minorUnits: -left.minorUnits))
            if left < .zero {
                lines.append(isZh ? "预算 \(money(budget))，超支 \(over)" : "Budget \(money(budget)): \(over) over")
            } else if period.isComplete {
                lines.append(isZh ? "预算 \(money(budget))，结余 \(money(left))" : "Budget \(money(budget)): \(money(left)) under")
            } else {
                lines.append(isZh ? "预算 \(money(budget))，还剩 \(money(left))" : "Budget \(money(budget)): \(money(left)) left")
            }
        }
        if recap.laterThisMonth > .zero {
            let month = monthName(period.start, now: period.now)
            lines.append(isZh ? "另有 \(money(recap.laterThisMonth)) 记在本月稍后日期，到那天才计入"
                              : "Plus \(money(recap.laterThisMonth)) dated later in \(month), counted once that day comes")
        }
        return lines
    }

    /// The summary's sentences with numbers, always written by the app so
    /// each amount sits next to what it belongs to.
    static func summary(for recap: PeriodRecap) -> String {
        let period = recap.period
        let past = period.isComplete
        let name = previousName(period)
        var sentences: [String] = []
        let spent = isZh
            ? "你\(spentWhen(period))共支出 \(money(recap.total))"
            : "\(past ? "You spent" : "You’ve spent") \(money(recap.total)) \(spentWhen(period))"
        if let previous = recap.previousTotal, let change = recap.change, previous > .zero {
            let up = change.amount > .zero
            let howMuch = recap.percentChange.map { "\(abs($0))%" } ?? money(positive(change.amount))
            sentences.append(isZh
                ? "\(spent)，比\(name)（\(money(previous))）\(up ? "多" : "少") \(howMuch)。"
                : "\(spent), \(howMuch) \(up ? "more" : "less") than \(name) (\(money(previous))).")
        } else if let previous = recap.previousTotal, recap.isAboutTheSame {
            sentences.append(isZh ? "\(spent)，与\(name)（\(money(previous))）基本持平。"
                                  : "\(spent), about the same as \(name) (\(money(previous))).")
        } else {
            sentences.append(spent + (isZh ? "。" : "."))
        }
        if let change = recap.change {
            let category = L10n.categoryName(change.driver)
            let up = change.driverChange > .zero
            let amount = money(positive(change.driverChange))
            sentences.append(isZh
                ? "\(category)变化最大，\(up ? "增加" : "减少")了 \(amount)。"
                : "\(category) \(up ? "rose" : "fell") the most, \(up ? "up" : "down") \(amount).")
        } else if let top = recap.categories.first {
            sentences.append(isZh
                ? "\(L10n.categoryName(top.category))是最大的类别，共 \(money(top.total))。"
                : "\(L10n.categoryName(top.category)) \(past ? "was" : "is") your biggest category at \(money(top.total)).")
        }
        if let budget = recap.budget {
            let left = budget - recap.total
            let over = money(Money(minorUnits: -left.minorUnits))
            if left < .zero {
                sentences.append(isZh ? "超出预算 \(over)。"
                                      : "You \(past ? "went" : "are") \(over) over your \(money(budget)) budget.")
            } else if past {
                sentences.append(isZh ? "预算 \(money(budget)) 结余 \(money(left))。"
                                      : "You stayed \(money(left)) under your \(money(budget)) budget.")
            } else {
                sentences.append(isZh ? "预算 \(money(budget)) 还剩 \(money(left))。"
                                      : "You have \(money(left)) left of your \(money(budget)) budget.")
            }
        }
        return sentences.joined(separator: " ")
    }

    // MARK: Checking the model's sentence

    /// Category IDs and the word stems that name them in English and Chinese.
    private static let categoryWords: [(id: String, words: [String])] = [
        ("Food", ["food", "餐饮"]), ("Grocery", ["grocer", "超市", "杂货"]), ("Shopping", ["shopping", "购物"]),
        ("Transport", ["transport", "交通"]), ("Housing", ["housing", "居住"]), ("Entertainment", ["entertainment", "娱乐"]),
        ("Health", ["health", "医疗"]), ("Utilities", ["utilit", "生活缴费"])
    ]
    private static let upWords = ["rose", "rise", "rising", "up", "more", "increase", "increased", "higher", "grew", "jumped", "climbed",
                                  "增加", "上升", "上涨", "增长"]
    private static let downWords = ["fell", "fall", "falling", "down", "less", "decrease", "decreased", "lower", "dropped", "drop",
                                    "declined", "减少", "下降", "降低", "回落"]

    private static func mentions(_ word: String, in text: String) -> Bool {
        if word.unicodeScalars.allSatisfy(\.isASCII) {
            return text.range(of: "\\b\(word)", options: [.regularExpression, .caseInsensitive]) != nil
        }
        return text.contains(word)
    }

    private static func mentionsWholeWord(_ word: String, in text: String) -> Bool {
        if word.unicodeScalars.allSatisfy(\.isASCII) {
            return text.range(of: "\\b\(word)\\b", options: [.regularExpression, .caseInsensitive]) != nil
        }
        return text.contains(word)
    }

    /// The model's one sentence is shown only if it can't misstate anything:
    /// no numbers at all, one short sentence, only categories from this
    /// period, and every "up" or "down" agreeing with the facts.
    static func isSafeInsight(_ text: String, for recap: PeriodRecap) -> Bool {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, sentence.count <= 160,
              sentence.range(of: #"[0-9０-９%％]"#, options: .regularExpression) == nil,
              sentence.dropLast().range(of: #"[.!?](\s|$)|[。！？]"#, options: .regularExpression) == nil else { return false }

        let named = categoryWords.filter { entry in entry.words.contains { mentions($0, in: sentence) } }.map(\.id)
        let known = Set(recap.categories.map(\.category))
        guard named.allSatisfy(known.contains) else { return false }

        let saysUp = upWords.contains { mentionsWholeWord($0, in: sentence) }
        let saysDown = downWords.contains { mentionsWholeWord($0, in: sentence) }
        guard saysUp || saysDown else { return true }
        // A direction needs a comparison, and only one direction per sentence.
        guard recap.previousTotal != nil, saysUp != saysDown else { return false }
        let moves: [Money] = named.isEmpty
            ? [recap.total - (recap.previousTotal ?? .zero)]
            : named.compactMap { id in recap.categories.first { $0.category == id }.map { $0.total - $0.previous } }
        return moves.allSatisfy { saysUp ? $0 > .zero : $0 < .zero }
    }

    /// Every number in the model's words must be one of the facts' numbers.
    /// A made-up or changed number means the code's own summary is shown.
    static func isFaithful(_ text: String, to facts: [String]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 500 else { return false }
        let allowed = Set(facts.flatMap(numbers(in:)))
        return numbers(in: trimmed).allSatisfy(allowed.contains)
    }

    static func numbers(in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"\d[\d,]*(?:\.\d+)?"#) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]).replacingOccurrences(of: ",", with: "") }
        }
    }
}

// MARK: - Writing with the on-device model

#if canImport(FoundationModels)
@available(iOS 26.0, *)
nonisolated struct RecapWriter {
    static let instructions = """
    You add one short observation to a spending summary that the person already sees with all its numbers. Using only the facts given, write one sentence of at most 20 words that helps them understand what happened, such as which category explains most of the change. Do not write any numbers, amounts, percentages, or dates. Name only categories that appear in the facts, and keep each one's direction exactly as the facts say. Speak to the person as "you", in the same language as the facts. If the first fact says "so far", the period isn't over yet: use the present tense. Don't give advice or judge the spending.
    """

    func write(facts: [String]) async throws -> String {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: "Facts:\n" + facts.map { "- " + $0 }.joined(separator: "\n"),
            options: .mostLikely
        )
        // One paragraph, even if the model breaks lines.
        return response.content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
#endif

/// The model's one sentence for a summary, kept only when it can be trusted.
/// An empty text means the app's sentences stand alone.
nonisolated struct RecapWording: Codable, Equatable, Sendable {
    var text: String
    var isFromModel: Bool
    /// The facts the text was written from; a change means rewriting it.
    var factsSignature: String

    /// Raised when the wording changes, so saved summaries are rewritten too.
    static let wordingVersion = 9

    static func signature(for facts: [String]) -> String {
        (["v\(wordingVersion)"] + facts).joined(separator: "\n")
    }

    /// One saved summary per period button, and one per past month, so the
    /// saved words never pile up.
    static func cacheKey(for period: SpendingPeriod) -> String {
        switch period.kind {
        case .month:
            let parts = Calendar.current.dateComponents([.year, .month], from: period.start)
            return String(format: "monthlyRecap.%04d-%02d", parts.year ?? 0, parts.month ?? 0)
        case .monthToDate: return "insightsRecap.monthToDate"
        case .recentMonths(let months): return "insightsRecap.last\(months)Months"
        case .yearToDate: return "insightsRecap.yearToDate"
        case .allTime: return "insightsRecap.allTime"
        }
    }

    static func cached(for recap: PeriodRecap, facts: [String], defaults: UserDefaults = .standard) -> RecapWording? {
        guard let data = defaults.data(forKey: cacheKey(for: recap.period)),
              let wording = try? JSONDecoder().decode(RecapWording.self, from: data),
              wording.factsSignature == signature(for: facts) else { return nil }
        return wording
    }

    func store(for recap: PeriodRecap, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.cacheKey(for: recap.period))
    }

    /// The model's sentence when Apple Intelligence is ready and it passes
    /// every check; otherwise nothing, and the app's sentences stand alone.
    static func make(for recap: PeriodRecap, facts: [String]) async -> RecapWording {
        let signature = signature(for: facts)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), ReceiptIntelligenceStatus.current == .ready,
           let text = try? await RecapWriter().write(facts: facts),
           RecapText.isSafeInsight(text, for: recap) {
            return RecapWording(text: text, isFromModel: true, factsSignature: signature)
        }
        #endif
        return RecapWording(text: "", isFromModel: false, factsSignature: signature)
    }

    /// What Details shows: the app's sentences, then the model's if any.
    func paragraph(for recap: PeriodRecap) -> String {
        let summary = RecapText.summary(for: recap)
        return isFromModel && !text.isEmpty ? summary + " " + text : summary
    }
}
