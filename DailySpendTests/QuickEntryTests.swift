import XCTest
@testable import DailySpend

/// Quick add reads amounts, dates, and splits by rules, so these are exact.
/// "Now" is fixed at Monday, October 26, 2026, 3 PM in New York.
final class QuickEntryTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 15))!
    }

    private func parse(_ text: String) -> QuickEntry {
        QuickEntryParser.parse(text, now: now, calendar: calendar)
    }

    private func cents(_ value: Int64) -> Money { Money(minorUnits: value) }

    private func day(_ entry: QuickEntry) -> String? {
        entry.date.map {
            let parts = calendar.dateComponents([.year, .month, .day], from: $0)
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }
    }

    func testAmountsInEnglish() {
        let cases: [(String, Int64?, String?)] = [
            ("coffee 4.50", 450, "Food"),
            ("$12 coffee", 1200, "Food"),
            ("Uber 23.40", 2340, "Transport"),
            ("uber eats 18", 1800, "Food"),
            ("Groceries at Trader Joe's $54.32", 5432, "Grocery"),
            ("Netflix 15.49", 1549, "Entertainment"),
            ("rent 1,800", 180_000, "Housing"),
            ("Croissant 4,50 €", 450, nil),
            ("dinner at 7pm 45", 4500, "Food"),
            ("Uber to 5th avenue 23", 2300, "Transport"),
            ("farmers market 12", 1200, nil),
            ("phone bill 85 dollars", 8500, "Utilities"),
            ("CVS 9.99", 999, "Health"),
            ("movie tickets 30 bucks", 3000, "Entertainment"),
        ]
        for (text, expected, category) in cases {
            let entry = parse(text)
            XCTAssertEqual(entry.amount, expected.map(cents), text)
            XCTAssertEqual(entry.category, category, text)
            XCTAssertEqual(entry.issues, [], text)
        }
        XCTAssertNil(parse("farmers market 12").date, "“market” is not March")
    }

    func testAmountsInChinese() {
        let cases: [(String, Int64, String?)] = [
            ("昨天打车 23 块", 2300, "Transport"),
            ("三十六块 午饭", 3600, "Food"),
            ("奶茶 18 元", 1800, "Food"),
            ("5块5 地铁", 550, "Transport"),
            ("交房租 3500", 350_000, "Housing"),
            ("话费 50", 5000, "Utilities"),
            ("３６元 早餐", 3600, "Food"),
            ("¥128 超市", 12_800, "Grocery"),
            ("见面喝咖啡 32", 3200, "Food"),
        ]
        for (text, expected, category) in cases {
            let entry = parse(text)
            XCTAssertEqual(entry.amount, cents(expected), text)
            XCTAssertEqual(entry.category, category, text)
        }
        XCTAssertNil(QuickEntryParser.keywordCategory(for: "住酒店 600"), "酒店 is a hotel, not a drink")
    }

    func testSplitsRecordYourShare() {
        let lunch = parse("lunch with Alex 36, split 3")
        XCTAssertEqual(lunch.total, cents(3600))
        XCTAssertEqual(lunch.splitCount, 3)
        XCTAssertEqual(lunch.amount, cents(1200))
        XCTAssertTrue(lunch.note.hasPrefix("Lunch with Alex\nlunch with Alex 36, split 3\n"))
        XCTAssertTrue(lunch.note.contains("3"))

        // An uneven split gives the extra cent to the person recording it.
        XCTAssertEqual(parse("dinner 100 split 3 ways").amount, cents(3334))
        XCTAssertEqual(parse("dinner with 2 friends 90").amount, cents(3000), "Two friends and me")
        XCTAssertEqual(parse("pizza 40 for four people").amount, cents(1000))
        XCTAssertEqual(parse("和小王吃火锅 300，3个人AA").amount, cents(10_000))
        XCTAssertEqual(parse("两个人吃饭 88").amount, cents(4400))
        XCTAssertEqual(parse("三百块 火锅 三个人").amount, cents(10_000))

        let noCount = parse("dinner 60 AA")
        XCTAssertEqual(noCount.amount, cents(6000))
        XCTAssertEqual(noCount.issues, [.splitWithoutCount])
        XCTAssertEqual(parse("lunch 20 split").issues, [.splitWithoutCount])
        XCTAssertEqual(parse("一个人吃饭 25").amount, cents(2500), "One person isn't a split")
    }

    func testDatesAreNeverInTheFuture() {
        let cases: [(String, String?)] = [
            ("coffee 4 today", "2026-10-26"),
            ("coffee 4 yesterday", "2026-10-25"),
            ("taxi 30 last night", "2026-10-25"),
            ("lunch 12 day before yesterday", "2026-10-24"),
            ("gas 40 3 days ago", "2026-10-23"),
            ("dinner 50 last Friday", "2026-10-23"),
            ("lunch 10 on Monday", "2026-10-26"),
            ("lunch 10 last Monday", "2026-10-19"),
            ("brunch 30 Sunday", "2026-10-25"),
            ("coffee 5 Oct 24", "2026-10-24"),
            ("gifts 80 12/25", "2025-12-25"),
            ("昨天 午饭 25", "2026-10-25"),
            ("前天 打车 40", "2026-10-24"),
            ("大前天 电影 60", "2026-10-23"),
            ("3天前 超市 45", "2026-10-23"),
            ("上周五 电影 ¥80", "2026-10-23"),
            ("上周一 房租 3000", "2026-10-19"),
            ("周日 早午餐 30", "2026-10-25"),
            ("10月20日 超市 45.6", "2026-10-20"),
            ("coffee 4", nil),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(day(parse(text)), expected, text)
        }
        // Numbers that are part of a date are never the amount.
        XCTAssertEqual(parse("coffee 5 Oct 24").amount, cents(500))
        XCTAssertEqual(parse("3天前 超市 45").amount, cents(4500))
        XCTAssertEqual(parse("10月20日 超市 45.6").amount, cents(4560))
    }

    func testUnclearAmountsAreFlagged() {
        let none = parse("lunch with Alex")
        XCTAssertNil(none.amount)
        XCTAssertEqual(none.issues, [.noAmount])
        XCTAssertEqual(none.note, "Lunch with Alex", "Words that are already a short title aren't repeated")

        let two = parse("coffee 4.5 and bagel 3")
        XCTAssertEqual(two.amount, cents(750))
        XCTAssertEqual(two.issues, [.addedAmounts(count: 2)])

        // A marked amount wins over bare numbers.
        XCTAssertEqual(parse("room 101 dinner $45").amount, cents(4500))
        XCTAssertEqual(parse("table 12 lunch 36元").amount, cents(3600))
    }

    /// What dictation writes when someone says an amount out loud.
    func testSpokenMoney() {
        let cases: [(String, Int64)] = [
            ("coffee four fifty", 450),
            ("Coffee 4:50", 450),
            ("coffee four dollars and fifty cents", 450),
            ("coffee 4 dollars and 50 cents", 450),
            ("coffee 4 dollars 5 cents", 405),
            ("parking fifty cents", 50),
            ("lunch twenty five", 2500),
            ("lunch twenty-five dollars", 2500),
            ("dinner a hundred and twenty", 12_000),
            ("rent one thousand two hundred", 120_000),
            ("taxi twelve thirty", 1230),
            ("one coffee 4.50", 450),
            ("two coffees four fifty", 450),
            ("奶茶四块五", 450),
            ("停车五毛", 50),
            ("打车 23块5毛", 2350),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(parse(text).amount, cents(expected), text)
        }
        // A time stays a time, and counts stay whole numbers.
        XCTAssertEqual(parse("dinner at 7:30 45").amount, cents(4500))
        XCTAssertEqual(parse("dinner 7:30pm 45").amount, cents(4500))
        let split = parse("lunch split three twenty")
        XCTAssertEqual(split.splitCount, 3)
        XCTAssertEqual(split.total, cents(2000))
        XCTAssertEqual(parse("dinner with two friends ninety").amount, cents(3000))
        XCTAssertEqual(day(parse("gas forty, three days ago")), "2026-10-23")
        XCTAssertEqual(parse("gas forty, three days ago").amount, cents(4000))
        XCTAssertEqual(QuickEntryParser.englishNumbers(in: "someone ordered tea"), "someone ordered tea")
    }

    func testChineseNumerals() {
        XCTAssertEqual(QuickEntryParser.chineseNumber("三十六"), 36)
        XCTAssertEqual(QuickEntryParser.chineseNumber("十二"), 12)
        XCTAssertEqual(QuickEntryParser.chineseNumber("一百零五"), 105)
        XCTAssertEqual(QuickEntryParser.chineseNumber("两千五百"), 2500)
        XCTAssertNil(QuickEntryParser.chineseNumber("一起"))
        XCTAssertEqual(QuickEntryParser.normalize("一起吃饭"), "一起吃饭", "Numerals only change before a unit")
    }

    /// The note starts with a short title, like a scanned receipt's store
    /// name, so Home and Insights rows stay one tidy line.
    func testNotesStartWithAShortTitle() {
        let cases: [(String, String)] = [
            ("Lunch at KFC 25", "Lunch at KFC"),
            ("coffee coffee 4.50", "Coffee"),
            ("$12 coffee", "Coffee"),
            ("lunch with Alex 36, split 3", "Lunch with Alex"),
            ("昨天打车 23 块", "打车"),
            ("dinner with my friends from work at the ramen place 80", "Dinner with my friends"),
        ]
        for (text, title) in cases {
            let entry = parse(text)
            XCTAssertEqual(entry.title, title, text)
            XCTAssertEqual(entry.note.split(separator: "\n").first.map(String.init), title, text)
        }
        // The person's own words are kept on the next line.
        XCTAssertEqual(parse("Lunch at KFC 25").note, "Lunch at KFC\nLunch at KFC 25")
        XCTAssertEqual(parse("lunch with Alex 36, split 3").note.split(separator: "\n").last, "Total $36.00 · split 3")
    }

    func testModelTitlesMustComeFromThePersonsWords() {
        XCTAssertTrue(QuickEntryParser.isGrounded("KFC", in: "lunch at kfc 25"))
        XCTAssertTrue(QuickEntryParser.isGrounded("打车", in: "昨天打车 23 块"))
        XCTAssertFalse(QuickEntryParser.isGrounded("Starbucks", in: "coffee 4.50"), "Never names a store that wasn't said")
        XCTAssertFalse(QuickEntryParser.isGrounded("", in: "coffee 4.50"))

        var entry = parse("coffee at blue bottle 6")
        entry.apply(QuickEntryRefinement(category: "Food", title: "Blue Bottle"))
        XCTAssertEqual(entry.note.split(separator: "\n").first, "Blue Bottle")
        XCTAssertEqual(entry.amount, Money(minorUnits: 600), "A title never changes the amount")
    }

    /// The model only chooses the category; amounts and dates stay the rules'.
    func testModelChoosesCategoriesWithoutTouchingAmounts() async throws {
        guard #available(iOS 26.0, *), ReceiptIntelligenceStatus.current == .ready else {
            throw XCTSkip("Apple Intelligence isn't available.")
        }
        // Some simulators report the model ready but can't load it; the app
        // then keeps the rule-based reading, which other tests cover.
        do {
            _ = try await QuickEntryCategoryReader().read("Coffee 4")
        } catch {
            throw XCTSkip("The on-device model couldn't run here: \(error)")
        }
        let cases: [(String, [String])] = [
            ("Dinner at Olive Garden 52", ["Food"]),
            ("Shell station 40", ["Transport"]),
            ("Walgreens vitamins 18.99", ["Health"]),
            ("AT&T bill 85", ["Utilities"]),
            ("Concert tickets 120", ["Entertainment"]),
            ("Target towels 24", ["Shopping"]),
            ("Whole Foods 63.20 yesterday", ["Grocery"]),
            ("滴滴 到机场 86", ["Transport"]),
        ]
        for (text, accepted) in cases {
            let entry = await QuickEntryReader().read(text, now: now)
            XCTAssertTrue(accepted.contains(entry.category ?? "-"), "\(text): \(entry.category ?? "nil")")
            XCTAssertEqual(entry.amount, QuickEntryParser.parse(text, now: now).amount, text)
        }
    }
}
