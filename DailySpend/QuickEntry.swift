import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What a typed or dictated description of an expense says, such as
/// "lunch with Alex 36, split 3" or "昨天打车 23 块". Amounts, dates, and
/// splits are read by rules so they are exact; only the category comes from
/// the on-device model, or from familiar words without it.
nonisolated struct QuickEntry: Equatable, Sendable {
    enum Issue: Equatable, Sendable {
        /// No amount was found in the words.
        case noAmount
        /// Several amounts were found and added together.
        case addedAmounts(count: Int)
        /// A split was mentioned without saying how many people.
        case splitWithoutCount
    }

    var text: String
    /// The amount mentioned, or the sum of several.
    var total: Money?
    /// How many people share it, counting the person writing.
    var splitCount: Int?
    var date: Date?
    var category: String?
    var categoryIsFromModel = false
    /// A short name for lists, like a scanned receipt's store name: "KFC",
    /// "Coffee", "Lunch with Alex". Empty when the words were only an amount.
    var title = ""
    var titleIsFromModel = false
    var issues: [Issue] = []

    /// What to record: this person's share of a split, or the whole amount.
    /// An uneven split gives the extra cent to the person recording it.
    var amount: Money? {
        guard let total else { return nil }
        guard let splitCount, splitCount > 1 else { return total }
        return Money.splitEvenly(total, among: splitCount).first
    }

    /// The person's own words, plus the split when there is one.
    /// The short title first, as a scan puts its store name first, so every
    /// list shows one tidy line; the person's own words follow for detail.
    var note: String {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        if !title.isEmpty { lines.append(title) }
        if !words.isEmpty, words.caseInsensitiveCompare(title) != .orderedSame { lines.append(words) }
        if let total, let splitCount, splitCount > 1 {
            let totalText = total.amount.formatted(.currency(code: L10n.currencyCode))
            lines.append(L10n.isZh ? "总额 \(totalText) · \(splitCount) 人平分" : "Total \(totalText) · split \(splitCount)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Rules

nonisolated enum QuickEntryParser {
    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> QuickEntry {
        var entry = QuickEntry(text: text)
        let normalized = normalize(text)
        let working = NSMutableString(string: normalized)

        let split = readSplit(in: working)
        entry.splitCount = split.count
        if split.mentioned && split.count == nil { entry.issues.append(.splitWithoutCount) }
        entry.date = readDate(in: working, now: now, calendar: calendar)
        mask(in: working, patterns: [
            #"\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#, #"\bat\s+\d{1,2}:\d{2}\b"#, #"\d{1,2}点(?:半|\d{1,2}分?)?"#,
            #"\b\d+(?:st|nd|rd|th)\b"#
        ])

        let amounts = readAmounts(in: working as String)
        switch amounts.count {
        case 0:
            entry.issues.append(.noAmount)
        case 1:
            entry.total = amounts[0]
        default:
            entry.total = amounts.reduce(.zero, +)
            entry.issues.append(.addedAmounts(count: amounts.count))
        }
        entry.category = keywordCategory(for: text)
        entry.title = shortTitle(from: working as String)
        return entry
    }

    // MARK: Title

    /// The words left once amounts, dates, and splits are taken out:
    /// "Lunch at KFC 25" is "Lunch at KFC", "昨天打车 23 块" is "打车".
    static func shortTitle(from remaining: String) -> String {
        let amounts = #"[$€£¥]?\s?\d[\d,]*(?:[.:]\d+)?\s?(?:dollars?|bucks|cents?|usd|rmb|cny|eur|euros?|块钱|块|元|圆|刀|毛)?"#
        var text = remaining.replacingOccurrences(of: amounts, with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"[,，.。;；:：!！?？]+"#, with: " ", options: .regularExpression)
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        // "Coffee coffee" from dictation is one coffee.
        words = words.enumerated().filter { index, word in
            index == 0 || word.caseInsensitiveCompare(words[index - 1]) != .orderedSame
        }.map(\.element)
        let connectors: Set<String> = ["at", "for", "on", "in", "with", "and", "to", "of", "the", "&", "-", "和", "在"]
        while let last = words.last, connectors.contains(last.lowercased()) { words.removeLast() }
        while let first = words.first, connectors.contains(first.lowercased()) && first.lowercased() != "the" { words.removeFirst() }
        // A title, not a sentence: a few words, or a few characters in Chinese.
        if words.count > 4 {
            words = Array(words.prefix(4))
            while let last = words.last, connectors.contains(last.lowercased()) { words.removeLast() }
        }
        var title = words.joined(separator: " ")
        if words.count == 1, title.count > 8, !title.unicodeScalars.allSatisfy(\.isASCII) {
            title = String(title.prefix(8))
        }
        guard let first = title.first, first.isLowercase else { return title }
        return first.uppercased() + title.dropFirst()
    }

    /// True when every word of a suggested title appears in the person's own
    /// words, so a title never names a store they didn't mention.
    static func isGrounded(_ title: String, in text: String) -> Bool {
        let words = title.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
        guard !words.isEmpty else { return false }
        let source = text.lowercased()
        return words.allSatisfy { word in
            if word.unicodeScalars.allSatisfy(\.isASCII) { return source.contains(word.lowercased()) }
            return word.allSatisfy { source.contains($0) }
        }
    }

    // MARK: Normalizing

    /// Full-width digits and symbols become ASCII, and Chinese numerals that
    /// count something ("三十六块", "两个人") become digits.
    static func normalize(_ text: String) -> String {
        var result = String(text.map { character -> Character in
            if let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
               (0xFF10...0xFF19).contains(scalar.value) {
                return Character(UnicodeScalar(scalar.value - 0xFF10 + 0x30)!)
            }
            switch character {
            case "￥": return "¥"
            case "＄": return "$"
            case "．": return "."
            case "，": return ","
            default: return character
            }
        })
        let pattern = "[零一二两三四五六七八九十百千]+(?=[块元圆刀人个位天日号月毛])"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return result }
        for match in expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let range = Range(match.range, in: result),
                  let value = chineseNumber(String(result[range])) else { continue }
            result.replaceSubrange(range, with: String(value))
        }
        // "4块五" is ¥4.50: the digit after 块 counts dimes.
        let afterKuai = ["一": "1", "二": "2", "两": "2", "三": "3", "四": "4", "五": "5", "六": "6", "七": "7", "八": "8", "九": "9"]
        for (word, digit) in afterKuai { result = result.replacingOccurrences(of: "块" + word, with: "块" + digit) }
        return englishNumbers(in: result)
    }

    // MARK: Spoken English numbers

    private static let unitWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]
    private static let tensWords: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    /// Dictation can write money as words: "four fifty" is 4.50, "twenty five"
    /// is 25, "a hundred and twenty" is 120. Counts of people or ways stay
    /// whole numbers, so "split three twenty" is 3 people and $20.
    static func englishNumbers(in text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: "[A-Za-z]+|[^A-Za-z]+") else { return text }
        let pieces = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        func isNumberWord(_ word: String, next: String?) -> Bool {
            let lower = word.lowercased()
            if unitWords[lower] != nil || tensWords[lower] != nil || lower == "hundred" || lower == "thousand" { return true }
            return lower == "a" && (next == "hundred" || next == "thousand")
        }
        var output = ""
        var index = 0
        while index < pieces.count {
            let piece = pieces[index]
            let nextWord = index + 2 < pieces.count ? pieces[index + 2].lowercased() : nil
            guard isNumberWord(piece, next: nextWord) else {
                output += piece
                index += 1
                continue
            }
            // Collect a run of number words; spaces, hyphens, and "and" may join them.
            var words = [piece.lowercased()]
            var end = index
            var probe = index + 1
            while probe + 1 < pieces.count {
                let gap = pieces[probe].trimmingCharacters(in: .whitespaces)
                guard gap.isEmpty || gap == "-" else { break }
                let word = pieces[probe + 1].lowercased()
                let after = probe + 3 < pieces.count ? pieces[probe + 3].lowercased() : nil
                if word == "and", probe + 3 < pieces.count, isNumberWord(pieces[probe + 3], next: nil),
                   pieces[probe + 2].trimmingCharacters(in: .whitespaces).isEmpty {
                    probe += 2
                    continue
                }
                guard isNumberWord(word, next: after) else { break }
                words.append(word)
                end = probe + 1
                probe += 2
            }
            let before = output.lowercased()
            let following = end + 2 < pieces.count ? pieces[end + 2].lowercased() : ""
            let isCount = ["split", "between", "among", "for", "with"].contains { before.hasSuffix($0 + " ") }
                || ["people", "persons", "ways", "way", "friends", "days", "day", "of"].contains(following)
            output += spokenValue(words, allowCents: !isCount)
            index = end + 1
        }
        return output
    }

    /// Whole numbers within a run of number words, read left to right.
    /// "Thousand" closes a group and "hundred" scales only the group after it.
    private static func chunks(_ words: [String]) -> [Int] {
        enum Last { case none, unit, teen, tens, scale }
        var values: [Int] = []
        var thousands = 0
        var group = 0
        var started = false
        var last = Last.none
        func push() {
            if started { values.append(thousands + group) }
            thousands = 0; group = 0; started = false; last = .none
        }
        for word in words {
            if word == "a" { group = max(group, 1); started = true; continue }
            if word == "hundred" {
                group = (group == 0 ? 1 : group) * 100
                started = true; last = .scale
            } else if word == "thousand" {
                thousands += (group == 0 ? 1 : group) * 1000
                group = 0; started = true; last = .scale
            } else if let value = tensWords[word] {
                if started && last != .scale { push() }
                group += value; started = true; last = .tens
            } else if let value = unitWords[word] {
                let isTeen = value >= 10
                let joinsTens = last == .tens && !isTeen && value > 0
                if started && last != .scale && !joinsTens { push() }
                group += value; started = true; last = isTeen ? .teen : .unit
            }
        }
        push()
        return values
    }

    /// "four fifty" reads as dollars and cents; anything else stays whole.
    private static func spokenValue(_ words: [String], allowCents: Bool) -> String {
        let values = chunks(words)
        if allowCents, values.count == 2, (10...99).contains(values[1]), values[0] < 10_000 {
            return "\(values[0]).\(values[1])"
        }
        return values.map(String.init).joined(separator: " ")
    }

    static func chineseNumber(_ text: String) -> Int? {
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
                                        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
        var total = 0
        var current = 0
        for character in text {
            if let digit = digits[character] {
                current = digit
            } else if let unit = units[character] {
                total += (current == 0 ? 1 : current) * unit
                current = 0
            } else {
                return nil
            }
        }
        let value = total + current
        return value > 0 ? value : nil
    }

    // MARK: Splits

    private static let countWords = "two|three|four|five|six|seven|eight|nine|ten|eleven|twelve"
    private static let wordValues = ["two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                                     "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12]

    private static func count(_ text: String) -> Int? {
        Int(text) ?? wordValues[text.lowercased()]
    }

    /// "split 3", "3 ways", "3 people", "with 2 friends", "3个人AA". The count
    /// includes the person writing; "with 2 friends" is 3 people.
    static func readSplit(in text: NSMutableString) -> (count: Int?, mentioned: Bool) {
        let number = "(\\d+|\(countWords))"
        let rules: [(pattern: String, add: Int)] = [
            ("\\bwith\\s+\(number)\\s+(?:friends|others|other people|coworkers|colleagues)\\b", 1),
            ("\\bsplit\\b(?:\\s+(?:it|the bill|evenly))?(?:\\s+(?:in|into|by|between|among|with))?\\s*\(number)(?:\\s*(?:ways?|people|persons|of us))?", 0),
            ("\\b\(number)\\s*(?:ways|people|persons|of us)\\b", 0),
            ("(\\d+)\\s*个?人", 0)
        ]
        var result: Int?
        for rule in rules {
            guard let expression = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(location: 0, length: text.length)
            guard let match = expression.firstMatch(in: text as String, range: range) else { continue }
            let value = count(text.substring(with: match.range(at: 1)))
            blank(match.range, in: text)
            if result == nil, let value, (1...50).contains(value + rule.add) {
                result = value + rule.add
            }
        }
        let mentionPattern = #"\b(?:split|go dutch)\b|aa制?|平分|均摊|分摊"#
        let mentioned = result != nil
            || (try? NSRegularExpression(pattern: mentionPattern, options: .caseInsensitive))?
                .firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) != nil
        mask(in: text, patterns: [mentionPattern])
        return (result.flatMap { $0 > 1 ? $0 : nil }, mentioned)
    }

    // MARK: Dates

    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    /// Whole month names or their usual short forms, so "market" isn't March.
    private static let monthPattern = "january|february|march|april|may|june|july|august|september|sept|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec"

    /// A day mentioned in the words, never later than today.
    static func readDate(in text: NSMutableString, now: Date, calendar: Calendar) -> Date? {
        func daysAgo(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: -days, to: now) }
        func first(_ pattern: String) -> NSTextCheckingResult? {
            (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?
                .firstMatch(in: text as String, range: NSRange(location: 0, length: text.length))
        }
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : text.substring(with: range)
        }
        let relative: [(String, Int)] = [
            (#"\bday before yesterday\b"#, 2), (#"大前天"#, 3), (#"前天"#, 2),
            (#"\byesterday\b|\blast night\b|昨天|昨晚|昨日"#, 1),
            (#"\btoday\b|\btonight\b|\bthis (?:morning|afternoon|evening)\b|今天|今晚|今日"#, 0)
        ]
        for (pattern, days) in relative {
            if let match = first(pattern) {
                blank(match.range, in: text)
                return daysAgo(days)
            }
        }
        // Read a match's parts before blanking it out.
        if let match = first("\\b(\\d+|\(countWords))\\s+days?\\s+ago\\b|(\\d+)\\s*天前") {
            let days = (group(match, 1) ?? group(match, 2)).flatMap(count)
            blank(match.range, in: text)
            if let days, days <= 366 { return daysAgo(days) }
        }
        // Weekdays mean the most recent one; "上周五" means last week's Friday.
        if let match = first("\\b(last|on|this)?\\s*(\(weekdayNames.joined(separator: "|")))\\b") {
            let target = weekdayNames.firstIndex(of: (group(match, 2) ?? "").lowercased()).map { $0 + 1 } ?? 1
            let isLast = group(match, 1)?.lowercased() == "last"
            blank(match.range, in: text)
            let today = calendar.component(.weekday, from: now)
            var back = (today - target + 7) % 7
            if back == 0, isLast { back = 7 }
            return daysAgo(back)
        }
        if let match = first("(上)?(?:周|星期|礼拜)([一二三四五六日天])") {
            let mondayBased = ["一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6][group(match, 2) ?? ""] ?? 0
            let isLastWeek = group(match, 1) != nil
            blank(match.range, in: text)
            let todayMondayBased = (calendar.component(.weekday, from: now) + 5) % 7
            if isLastWeek {
                return daysAgo(todayMondayBased + 7 - mondayBased)
            }
            let back = (todayMondayBased - mondayBased + 7) % 7
            return daysAgo(back)
        }
        // Explicit days: "Oct 24", "10/24", "10月24日". A date later than
        // today means last year's.
        var month: Int?
        var day: Int?
        var year: Int?
        if let match = first("\\b(\(monthPattern))\\b\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b") {
            month = monthNames.firstIndex(of: String((group(match, 1) ?? "").lowercased().prefix(3))).map { $0 + 1 }
            day = group(match, 2).flatMap { Int($0) }
            blank(match.range, in: text)
        } else if let match = first("(\\d{1,2})月(\\d{1,2})[日号]") {
            month = group(match, 1).flatMap { Int($0) }
            day = group(match, 2).flatMap { Int($0) }
            blank(match.range, in: text)
        } else if let match = first("\\b(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?\\b") {
            let first = group(match, 1).flatMap { Int($0) } ?? 0
            let second = group(match, 2).flatMap { Int($0) } ?? 0
            // Month first, as written in the US, unless that can't be a date.
            if first <= 12 { (month, day) = (first, second) } else { (month, day) = (second, first) }
            year = group(match, 3).flatMap { Int($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
            blank(match.range, in: text)
        }
        guard let month, let day, (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = calendar.dateComponents([.year, .hour, .minute], from: now)
        components.month = month
        components.day = day
        if let year { components.year = year }
        guard var date = calendar.date(from: components), calendar.component(.day, from: date) == day else { return nil }
        if date > now, year == nil, let lastYear = calendar.date(byAdding: .year, value: -1, to: date) { date = lastYear }
        return date > now ? nil : date
    }

    // MARK: Amounts

    /// Amounts with a currency mark ("$36", "36块", "4,50 €") win over bare
    /// numbers. "5块5" is ¥5.50.
    static func readAmounts(in text: String) -> [Money] {
        let number = #"(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:[.,]\d{1,2})?)"#
        let marked = [
            #"(\d+)\s*块\s*(\d)(?![\d.])"#,
            #"(\d+)\s*(?:dollars?|bucks)\s*(?:and\s*)?(\d{1,2})\s*cents?\b"#,
            #"(?:[$€£¥]|\b(?:usd|rmb|cny|eur)\s?)\s?"# + number,
            number + #"\s?(?:dollars?\b|bucks\b|usd\b|rmb\b|cny\b|eur\b|euros?\b|块钱|块|元|圆|刀|€)"#
        ]
        var found: [(location: Int, money: Money)] = []
        var claimed: [NSRange] = []
        for (index, pattern) in marked.enumerated() {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard !claimed.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
                let nsText = text as NSString
                let money: Money?
                if index <= 1 {
                    // 块 counts dimes ("5块5" is 5.50); cents need two digits ("5 cents" is .05).
                    let fraction = nsText.substring(with: match.range(at: 2))
                    let cents = index == 0 ? fraction : String(repeating: "0", count: 2 - fraction.count) + fraction
                    money = ReceiptNumberParser.money(from: nsText.substring(with: match.range(at: 1)) + "." + cents)
                } else {
                    money = ReceiptNumberParser.money(from: nsText.substring(with: match.range(at: 1)))
                }
                if let money, money > .zero {
                    found.append((match.range.location, money))
                    claimed.append(match.range)
                }
            }
        }
        // Then cents alone ("50 cents", "五毛"), then amounts with cents or
        // dictation's clock-style "4:50", and only then bare whole numbers,
        // so "one coffee 4.50" is 4.50 and not 5.50.
        let fallbacks: [(pattern: String, read: (NSTextCheckingResult, NSString) -> Money?)] = [
            (#"(?<![\d.])(\d{1,2})\s*(?:cents?\b|毛)"#, { match, text in
                Int64(text.substring(with: match.range(at: 1))).map { Money(minorUnits: $0 * (text.substring(with: match.range).contains("毛") ? 10 : 1)) }
            }),
            (#"(?<![\d.,:])(\d{1,4}[.,]\d{2})(?![\d])|(?<![\d:])(\d{1,3}):(\d{2})(?![\d:])"#, { match, text in
                if match.range(at: 1).location != NSNotFound {
                    return ReceiptNumberParser.money(from: text.substring(with: match.range(at: 1)))
                }
                return ReceiptNumberParser.money(from: text.substring(with: match.range(at: 2)) + "." + text.substring(with: match.range(at: 3)))
            }),
            (#"(?<![\d.,:])"# + number + #"(?![\d:])"#, { match, text in
                ReceiptNumberParser.money(from: text.substring(with: match.range(at: 1)))
            })
        ]
        for fallback in fallbacks where found.isEmpty {
            guard let expression = try? NSRegularExpression(pattern: fallback.pattern, options: .caseInsensitive) else { continue }
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let money = fallback.read(match, text as NSString), money > .zero {
                    found.append((match.range.location, money))
                }
            }
        }
        return found.sorted { $0.location < $1.location }.map(\.money).filter { $0.minorUnits < 1_000_000_000 }
    }

    // MARK: Category

    private static let keywords: [String: [String]] = [
        "Food": ["coffee", "latte", "tea", "lunch", "dinner", "breakfast", "brunch", "restaurant", "pizza", "burger",
                 "sushi", "ramen", "noodles", "cafe", "café", "bar", "beer", "drinks", "takeout", "doordash", "uber eats",
                 "starbucks", "snack", "boba", "咖啡", "奶茶", "午饭", "午餐", "晚饭", "晚餐", "早饭", "早餐", "外卖",
                 "吃饭", "火锅", "饭", "面条", "拉面", "啤酒", "喝酒"],
        "Grocery": ["grocery", "groceries", "supermarket", "costco", "trader joe", "whole foods", "超市", "买菜", "菜市场", "水果"],
        "Transport": ["uber", "lyft", "taxi", "cab", "bus", "subway", "metro", "train", "gas", "fuel", "parking", "toll",
                      "打车", "滴滴", "地铁", "公交", "加油", "停车", "高铁", "火车"],
        "Shopping": ["amazon", "clothes", "shoes", "shirt", "jacket", "衣服", "鞋", "淘宝", "京东", "购物"],
        "Housing": ["rent", "furniture", "repair", "房租", "家具", "维修"],
        "Entertainment": ["movie", "cinema", "concert", "netflix", "spotify", "game", "tickets", "电影", "演唱会", "游戏"],
        "Health": ["pharmacy", "medicine", "doctor", "dentist", "gym", "cvs", "walgreens", "药", "医院", "健身"],
        "Utilities": ["electric", "electricity", "water bill", "internet", "wifi", "phone bill", "电费", "水费", "网费", "话费"]
    ]

    /// The category familiar words point to. Longer words are checked first,
    /// so "uber eats" is food and "uber" is a ride.
    static func keywordCategory(for text: String) -> String? {
        let lowered = text.lowercased()
        let pairs = keywords.flatMap { category, words in words.map { ($0, category) } }
            .sorted { $0.0.count > $1.0.count }
        for (word, category) in pairs {
            if word.unicodeScalars.allSatisfy(\.isASCII) {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "s?\\b"
                if lowered.range(of: pattern, options: .regularExpression) != nil { return category }
            } else if lowered.contains(word) {
                return category
            }
        }
        return nil
    }

    // MARK: Helpers

    /// Replaces a matched span with spaces, so later rules don't read it
    /// again and positions stay the same.
    private static func blank(_ range: NSRange, in text: NSMutableString) {
        text.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
    }

    private static func mask(in text: NSMutableString, patterns: [String]) {
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in expression.matches(in: text as String, range: NSRange(location: 0, length: text.length)).reversed() {
                blank(match.range, in: text)
            }
        }
    }
}

// MARK: - Reading with the on-device model

/// What the model adds to the rules' reading: a category and, when it is
/// grounded in the words, a better title such as the store's name.
nonisolated struct QuickEntryRefinement: Equatable, Sendable {
    var category: String?
    var title: String?
}

nonisolated extension QuickEntry {
    mutating func apply(_ refinement: QuickEntryRefinement) {
        if let category = refinement.category {
            self.category = category
            categoryIsFromModel = true
        }
        if let title = refinement.title, !title.isEmpty {
            self.title = title
            titleIsFromModel = true
        }
    }
}

nonisolated struct QuickEntryReader {
    /// Reads the words: rules first, then the model picks the category when
    /// Apple Intelligence is ready. The model never changes an amount or date.
    func read(_ text: String, now: Date = Date()) async -> QuickEntry {
        var entry = QuickEntryParser.parse(text, now: now)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), ReceiptIntelligenceStatus.current == .ready,
           let refinement = try? await QuickEntryCategoryReader().read(text) {
            entry.apply(refinement)
        }
        #endif
        return entry
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "The spending category of one expense")
nonisolated struct GeneratedQuickEntryCategory {
    @Guide(description: "Spending category. Food: restaurants, cafes, bars, takeout, food delivery, meals and drinks. Grocery: supermarkets, grocery and convenience stores. Shopping: clothing, electronics, household goods, general retail. Transport: rides, taxis, transit, fuel, parking, flights. Housing: rent, furniture, home repair. Entertainment: movies, concerts, events, games, streaming. Health: pharmacy, medical, dental, fitness. Utilities: electricity, water, gas, phone, internet. Other: anything else.",
           .anyOf(["Food", "Grocery", "Shopping", "Transport", "Housing", "Entertainment", "Health", "Utilities", "Other"]))
    var category: String

    @Guide(description: "A short title for this expense. The store, restaurant, or business name if the note mentions one, such as KFC or Apple. Otherwise 1 to 3 words for what was bought, such as Coffee or Lunch with Alex. Use only words from the note. Never include amounts or dates.")
    var title: String
}

@available(iOS 26.0, *)
nonisolated struct QuickEntryCategoryReader {
    static let instructions = """
    You read a short note someone wrote about one thing they paid for, and choose its spending category and a short title. The note may be in English or Chinese and may include amounts, dates, or people.
    """

    /// Uses a session prepared while the person was typing, when there is one.
    func read(_ text: String, session prepared: LanguageModelSession? = nil) async throws -> QuickEntryRefinement {
        let session = prepared ?? LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: "Note: \(text)",
            generating: GeneratedQuickEntryCategory.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        let title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return QuickEntryRefinement(category: response.content.category,
                                    title: QuickEntryParser.isGrounded(title, in: text) ? title : nil)
    }
}
#endif

/// Starts the model as soon as the person taps the field, so the category
/// arrives sooner. Each entry gets its own fresh session.
@MainActor
final class QuickEntryCategoryHelper {
    private var prepared: AnyObject?

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return ReceiptIntelligenceStatus.current == .ready }
        #endif
        return false
    }

    func prepare() {
        #if canImport(FoundationModels)
        guard prepared == nil, Self.isAvailable, #available(iOS 26.0, *) else { return }
        let session = LanguageModelSession(instructions: QuickEntryCategoryReader.instructions)
        session.prewarm()
        prepared = session
        #endif
    }

    /// The model's category and title, or nil when it isn't available or doesn't answer.
    func refine(_ text: String) async -> QuickEntryRefinement? {
        #if canImport(FoundationModels)
        guard Self.isAvailable, #available(iOS 26.0, *) else { return nil }
        let session = prepared as? LanguageModelSession
        prepared = nil
        return try? await QuickEntryCategoryReader().read(text, session: session)
        #else
        return nil
        #endif
    }
}
