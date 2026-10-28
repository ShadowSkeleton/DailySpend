// Generates fictional receipt photos for manually testing DailySpend's scanner.
//
//   swift scripts/test-receipts/make_test_receipts.swift
//
// Every store, person, and amount is invented. Totals are computed here, so the
// expected values in docs/test-receipts/README.md always match the images.
import AppKit
import CoreImage

struct Row {
    var left: String
    var middle = ""
    var right = ""
    var centered = false
}

struct Receipt {
    let file: String
    let rows: [Row]
    var tilt: CGFloat = 0
    var faded = false
}

func usd(_ cents: Int) -> String {
    (cents < 0 ? "-" : "") + String(format: "%d.%02d", abs(cents) / 100, abs(cents) % 100)
}

func euro(_ cents: Int) -> String {
    String(format: "%d,%02d €", cents / 100, cents % 100)
}

func center(_ text: String) -> Row { Row(left: text, centered: true) }
func item(_ name: String, _ cents: Int, quantity: String = "") -> Row { Row(left: name, middle: quantity, right: usd(cents)) }
func percent(_ cents: Int, _ basisPoints: Int) -> Int { Int((Double(cents) * Double(basisPoints) / 10_000).rounded()) }

var receipts: [Receipt] = []

// 01 — Restaurant with a printed suggested-tip table that was not charged.
do {
    let lines = [("Dumplings", 1800, "2"), ("Spicy Beef Noodles", 1650, ""), ("Jasmine Tea", 450, "")]
    let subtotal = lines.reduce(0) { $0 + $1.1 }
    let tax = percent(subtotal, 900)
    receipts.append(Receipt(file: "01-restaurant-suggested-tip", rows: [
        center("HARBOR NOODLE HOUSE"), center("88 Pier St, Seattle WA"), center("(206) 555-0142"),
        Row(left: "10/24/2026", right: "7:42 PM"), Row(left: "Server: Kim", right: "Table 12"),
    ] + lines.map { item($0.0, $0.1, quantity: $0.2) } + [
        item("Subtotal", subtotal), item("Tax 9%", tax), item("Total", subtotal + tax),
        Row(left: "Suggested Tip:", middle: "18% $\(usd(percent(subtotal, 1800)))", right: "20% $\(usd(percent(subtotal, 2000)))"),
        Row(left: "VISA ****1234", right: usd(subtotal + tax)), center("Thank you!")
    ], tilt: -0.02))
}

// 02 — Restaurant merchant copy with a tip already charged.
do {
    let lines = [("Margherita Pizza", 1600), ("Rigatoni Vodka", 1900), ("Caesar Salad", 1300)]
    let subtotal = lines.reduce(0) { $0 + $1.1 }
    let tax = percent(subtotal, 888)
    let tip = 900
    receipts.append(Receipt(file: "02-restaurant-tip-charged", rows: [
        center("OSTERIA LUME"), center("410 Grand Ave, Brooklyn NY"), Row(left: "Oct 23 2026", right: "8:15 PM"),
    ] + lines.map { item($0.0, $0.1) } + [
        item("Subtotal", subtotal), item("Sales Tax", tax), item("Tip", tip), item("TOTAL", subtotal + tax + tip),
        Row(left: "MASTERCARD ****8890", right: usd(subtotal + tax + tip)), center("MERCHANT COPY")
    ], tilt: 0.015))
}

// 03 — Long grocery receipt with quantities, coupons, and tax on some items.
do {
    let lines: [(String, Int, String)] = [
        ("BANANAS", 129, ""), ("AVOCADO", 258, "2 @ 1.29"), ("ORGANIC MILK 1GAL", 549, ""),
        ("SOURDOUGH LOAF", 449, ""), ("FREE RANGE EGGS 12CT", 499, ""), ("GREEK YOGURT", 189, ""),
        ("BABY SPINACH", 349, ""), ("CHICKEN THIGHS", 1124, ""), ("PASTA PENNE", 358, "2 @ 1.79"),
        ("MARINARA SAUCE", 399, ""), ("PARMESAN WEDGE", 699, ""), ("APPLES GALA", 412, ""),
        ("OAT CEREAL", 529, ""), ("PAPER TOWELS*", 899, ""), ("DISH SOAP*", 349, ""),
        ("SPARKLING WATER*", 599, "")
    ]
    let coupons = [("COUPON EGGS", -100), ("MEMBER SAVINGS", -50)]
    let itemsTotal = lines.reduce(0) { $0 + $1.1 }
    let subtotal = itemsTotal + coupons.reduce(0) { $0 + $1.1 }
    let tax = percent(899 + 349 + 599, 875)
    receipts.append(Receipt(file: "03-grocery-long-coupons", rows: [
        center("GREEN BASKET MARKET"), center("Store #214  Portland OR"), Row(left: "10-22-2026", right: "18:04"),
    ] + lines.map { item($0.0, $0.1, quantity: $0.2) } + coupons.map { item($0.0, $0.1) } + [
        item("SUBTOTAL", subtotal), item("TAX 8.75% (*)", tax), item("TOTAL", subtotal + tax),
        item("DEBIT", subtotal + tax), item("CHANGE", 0), center("* taxable item")
    ], tilt: -0.03))
}

// 04 — Pharmacy with a multi-unit line and a reward coupon.
do {
    let subtotal = 949 + 1299 + 698 - 200
    let tax = 189
    receipts.append(Receipt(file: "04-pharmacy-unit-price", rows: [
        center("WELLWAY PHARMACY"), Row(left: "#4521", right: "1200 Market St"), Row(left: "OCT 21 2026", right: "3:12PM"),
        item("PAIN RELIEF 24CT", 949), item("VITAMIN D3", 1299), Row(left: "2 @ 3.49", middle: "COUGH DROPS", right: usd(698)),
        item("REWARD", -200), item("SUBTOTAL", subtotal), item("SALES TAX 8.5%", tax), item("TOTAL", subtotal + tax),
        item("CREDIT", subtotal + tax)
    ], tilt: -0.025))
}

// 05 — Café with a charged tip.
receipts.append(Receipt(file: "05-cafe-tip", rows: [
    center("BLUE DOOR COFFEE"), Row(left: "Oct 22, 2026", right: "08:15"),
    item("Latte", 575), item("Croissant", 425), item("Subtotal", 1000), item("Tax", 90), item("Tip", 200),
    item("Total", 1290), item("Card", 1290)
]))

// 06 — Chinese hotpot with a service charge.
receipts.append(Receipt(file: "06-chinese-hotpot-service", rows: [
    center("蜀香火锅"), Row(left: "2026-10-20", right: "19:30"),
    Row(left: "番茄锅底", middle: "1", right: "68.00"), Row(left: "肥牛", middle: "2", right: "96.00"),
    Row(left: "虾滑", middle: "1", right: "38.00"), Row(left: "小计", right: "202.00"),
    Row(left: "服务费 10%", right: "20.20"), Row(left: "合计", right: "222.20"), Row(left: "微信支付", right: "222.20")
], tilt: 0.02))

// 07 — Chinese supermarket with a discount.
receipts.append(Receipt(file: "07-chinese-supermarket", rows: [
    center("惠民超市"), center("欢迎光临"), Row(left: "2026-10-19", right: "10:05"),
    Row(left: "鸡蛋 10枚", right: "12.80"), Row(left: "大米 5kg", right: "39.90"), Row(left: "酱油", right: "9.50"),
    Row(left: "苹果", middle: "1.25kg", right: "14.95"), Row(left: "牛奶", middle: "2", right: "11.00"),
    Row(left: "合计", right: "88.15"), Row(left: "会员优惠", right: "-5.00"), Row(left: "实付", right: "83.15"),
    Row(left: "支付宝", right: "83.15")
], tilt: -0.015))

// 08 — Euro café: decimal commas and VAT already included in the total.
receipts.append(Receipt(file: "08-euro-cafe-vat-included", rows: [
    center("CAFÉ LUMIÈRE"), center("12 rue des Lilas, Paris"), Row(left: "24/10/2026", right: "09:40"),
    Row(left: "Croissant", right: euro(250)), Row(left: "Café crème", right: euro(420)), Row(left: "Jus d'orange", right: euro(530)),
    Row(left: "TOTAL TTC", right: euro(1200)), Row(left: "dont TVA 10%", right: euro(109)), Row(left: "CB", right: euro(1200)),
    center("Merci !")
], tilt: 0.01))

// 09 — Ride receipt with a booking fee and tip.
receipts.append(Receipt(file: "09-ride-fee-tip", rows: [
    center("METRO RIDE"), center("Thanks for riding, Jordan"), center("October 19, 2026"),
    item("Trip fare", 1840), item("Booking fee", 285), item("Tip", 193), item("Total", 2318),
    Row(left: "Visa ****4021", right: usd(2318))
]))

// 10 — Group dinner for itemized splitting, with an automatic service charge.
do {
    let lines: [(String, Int, String)] = [
        ("Pad Thai", 2800, "2"), ("Green Curry", 1550, ""), ("Spring Rolls", 800, ""),
        ("Thai Iced Tea", 1350, "3"), ("Mango Sticky Rice", 900, "")
    ]
    let subtotal = lines.reduce(0) { $0 + $1.1 }
    let tax = percent(subtotal, 888)
    let service = percent(subtotal, 1800)
    receipts.append(Receipt(file: "10-group-dinner-service-charge", rows: [
        center("LUCKY THAI KITCHEN"), Row(left: "10/25/2026", right: "7:05 PM"), Row(left: "Party of 4", right: "Table 7"),
    ] + lines.map { item($0.0, $0.1, quantity: $0.2) } + [
        item("Subtotal", subtotal), item("Tax", tax), item("Service Charge 18%", service),
        item("Total", subtotal + tax + service), center("Service charge added for parties of 4+")
    ], tilt: 0.025))
}

// 11 — Faded thermal paper.
receipts.append(Receipt(file: "11-faded-deli", rows: [
    center("CORNER DELI"), Row(left: "10/18/2026", right: "12:31"),
    item("Turkey Club", 1150), item("Tomato Soup", 525), item("Lemonade", 375),
    item("Subtotal", 2050), item("Tax", 179), item("TOTAL", 2229)
], tilt: -0.01, faded: true))

// 12 — Not a receipt: a shopping list with no prices.
receipts.append(Receipt(file: "12-not-a-receipt", rows: [
    center("Shopping list"), Row(left: "- milk"), Row(left: "- eggs"), Row(left: "- bread"),
    Row(left: "- apples"), Row(left: "- call mom about Sunday")
], tilt: 0.03))

// MARK: - Rendering

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/docs/test-receipts"
try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

// 16 — Restaurant whose tip guide is figured on the total after tax, so a
// split must follow the receipt rather than assume the bill before tax.
do {
    let lines = [("Chicken Tikka Masala", 2150), ("Garlic Naan", 650), ("Mango Lassi", 1200)]
    let subtotal = lines.reduce(0) { $0 + $1.1 }
    let tax = percent(subtotal, 1025)
    let total = subtotal + tax
    receipts.append(Receipt(file: "16-restaurant-tip-after-tax", rows: [
        center("SAFFRON TABLE"), center("1520 Mission St, San Francisco CA"),
        Row(left: "10/24/2026", right: "8:05 PM"), Row(left: "Server: Priya", right: "Table 4"),
    ] + lines.map { item($0.0, $0.1) } + [
        item("Subtotal", subtotal), item("Tax 10.25%", tax), item("Total", total),
        center("TIP GUIDE (on total)")
    ] + [15, 18, 20].map { rate in
        Row(left: "\(rate)%  Tip $\(usd(percent(total, rate * 100)))", right: "Total $\(usd(total + percent(total, rate * 100)))")
    } + [
        Row(left: "Tip: ________"), Row(left: "Total: ________"), center("Thank you!")
    ], tilt: 0.015))
}

for receipt in receipts {
    let paperWidth: CGFloat = 760
    let rowHeight: CGFloat = 46
    let paperHeight = CGFloat(receipt.rows.count) * rowHeight + 170
    let canvas = CGSize(width: paperWidth + 260, height: paperHeight + 260)
    let image = NSImage(size: canvas)
    image.lockFocus()
    NSGradient(starting: NSColor(calibratedWhite: 0.36, alpha: 1), ending: NSColor(calibratedWhite: 0.24, alpha: 1))?
        .draw(in: NSRect(origin: .zero, size: canvas), angle: 90)
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: canvas.width / 2, y: canvas.height / 2)
    context.rotate(by: receipt.tilt)
    context.translateBy(x: -paperWidth / 2, y: -paperHeight / 2)
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(calibratedRed: 0.985, green: 0.975, blue: 0.95, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: paperWidth, height: paperHeight).fill()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    let ink = receipt.faded ? NSColor(calibratedWhite: 0.55, alpha: 1) : NSColor(calibratedWhite: 0.12, alpha: 1)
    let font = NSFont(name: "Menlo", size: 27) ?? NSFont.monospacedSystemFont(ofSize: 27, weight: .regular)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
    for (index, row) in receipt.rows.enumerated() {
        let y = paperHeight - 95 - CGFloat(index) * rowHeight
        if row.centered {
            let text = row.left as NSString
            text.draw(at: NSPoint(x: (paperWidth - text.size(withAttributes: attributes).width) / 2, y: y), withAttributes: attributes)
            continue
        }
        (row.left as NSString).draw(at: NSPoint(x: 50, y: y), withAttributes: attributes)
        if !row.middle.isEmpty {
            (row.middle as NSString).draw(at: NSPoint(x: paperWidth * 0.52, y: y), withAttributes: attributes)
        }
        let right = row.right as NSString
        right.draw(at: NSPoint(x: paperWidth - 50 - right.size(withAttributes: attributes).width, y: y), withAttributes: attributes)
    }
    image.unlockFocus()

    var cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    if receipt.faded, let blurred = CIFilter(name: "CIGaussianBlur", parameters: [
        kCIInputImageKey: CIImage(cgImage: cgImage), kCIInputRadiusKey: 1.6
    ])?.outputImage?.cropped(to: CIImage(cgImage: cgImage).extent) {
        cgImage = CIContext().createCGImage(blurred, from: blurred.extent) ?? cgImage
    }
    let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.82])!
    try data.write(to: URL(fileURLWithPath: "\(outputDirectory)/\(receipt.file).jpg"))
    print("wrote \(receipt.file).jpg")
}
