import CoreGraphics
import Foundation
import ImageIO
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether receipts can be read item by item on this device. Every path is
/// on-device: DailySpend uses Apple's system model only, never a server model.
nonisolated enum ReceiptIntelligenceStatus: Equatable, Sendable {
    case ready
    case appleIntelligenceOff
    case modelDownloading
    case deviceNotSupported
    case systemTooOld

    static var current: ReceiptIntelligenceStatus {
        #if DEBUG
        // Matches `ReceiptDraft.uiTestLaunchArgument`: UI tests feed a fixed
        // receipt, so they need the itemized controls on every simulator.
        if ProcessInfo.processInfo.arguments.contains("-ui-test-receipt") { return .ready }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceOff
            case .unavailable(.modelNotReady):
                return .modelDownloading
            case .unavailable:
                return .deviceNotSupported
            @unknown default:
                return .deviceNotSupported
            }
        }
        #endif
        return .systemTooOld
    }

    var canReadItems: Bool { self == .ready }

    var title: String {
        switch self {
        case .ready:
            return L10n.isZh ? "已开启 · 在设备上处理" : "On · Processed on this device"
        case .appleIntelligenceOff:
            return L10n.isZh ? "请在系统设置中开启 Apple 智能" : "Turn on Apple Intelligence in Settings"
        case .modelDownloading:
            return L10n.isZh ? "Apple 智能模型正在下载" : "Apple Intelligence is still downloading"
        case .deviceNotSupported:
            return L10n.isZh ? "此设备仅支持识别总额" : "This device reads totals only"
        case .systemTooOld:
            return L10n.isZh ? "升级到 iOS 26 以识别明细" : "Update to iOS 26 to read items"
        }
    }
}

/// One captured receipt page. Orientation is carried separately because
/// photos are often stored sideways with an orientation flag.
nonisolated struct ReceiptPage: @unchecked Sendable {
    let image: CGImage
    let orientation: CGImagePropertyOrientation
}

enum ReceiptReadingError: LocalizedError, Equatable {
    case noText
    case nothingFound

    var errorDescription: String? {
        switch self {
        case .noText:
            return L10n.isZh ? "没有在图片中找到文字。请在光线充足处拍摄完整的收据。" : "No text was found. Try again with the whole receipt in good light."
        case .nothingFound:
            return L10n.isZh ? "没有找到收据总额。你可以手动输入金额。" : "No total was found on this receipt. You can enter the amount manually."
        }
    }
}

protocol ReceiptReading: Sendable {
    func read(_ pages: [ReceiptPage]) async throws -> ReceiptDraft
}

/// Reads receipts with Vision, then asks Apple's on-device model to structure
/// the text. Devices without Apple Intelligence keep the earlier behaviour:
/// Vision plus the deterministic total parser.
nonisolated struct ReceiptReader: ReceiptReading {
    func read(_ pages: [ReceiptPage]) async throws -> ReceiptDraft {
        let lines = try await Self.recognizeText(in: pages)
        let rows = lines.flatMap(ReceiptTextLayout.rows(from:))
        guard !rows.isEmpty else { throw ReceiptReadingError.noText }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), ReceiptIntelligenceStatus.current == .ready {
            do {
                let draft = try await ReceiptModelExtractor().extract(rows: rows)
                #if DEBUG
                Self.saveDebugLog(rows: rows, draft: draft)
                #endif
                if draft.amountToRecord != nil || !draft.items.isEmpty { return draft }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Guardrails, an unsupported language, or a busy model should
                // never block scanning. The total parser below still works.
                #if DEBUG
                print("Receipt model fell back to text recognition: \(error)")
                #endif
            }
        }
        #endif

        try Task.checkCancellation()
        // The payable total is usually on the last page of a long receipt.
        // Whole rows keep a "Total" label beside its amount; the original
        // fragments remain a fallback for unusual layouts.
        for pageLines in lines.reversed() {
            if let amount = ReceiptAmountParser.bestAmount(from: ReceiptTextLayout.rowLines(from: pageLines))
                ?? ReceiptAmountParser.bestAmount(from: pageLines) {
                return ReceiptDraft(total: Money(amount), source: .textRecognition)
            }
        }
        throw ReceiptReadingError.nothingFound
    }

    #if DEBUG
    /// Debug builds keep the last scan's recognized rows and reading in the
    /// app's caches, so a misread on a test device can be diagnosed. Release
    /// builds never write receipt text anywhere.
    static func saveDebugLog(rows: [String], draft: ReceiptDraft) {
        guard let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let text = "ROWS\n" + rows.joined(separator: "\n") + "\n\nREAD\n\(draft)\n"
        try? text.write(to: folder.appendingPathComponent("last-receipt-scan.txt"), atomically: true, encoding: .utf8)
    }
    #endif

    /// Starts loading the model while the camera is open, so reading begins
    /// sooner after capture. It does nothing when the model is unavailable.
    static func prepare() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), ReceiptIntelligenceStatus.current == .ready {
            LanguageModelSession(instructions: ReceiptModelExtractor.instructions).prewarm()
        }
        #endif
    }

    /// Recognized, straightened text fragments for each page.
    @concurrent
    static func recognizeText(in pages: [ReceiptPage]) async throws -> [[ReceiptAmountParser.Line]] {
        try pages.map { page in
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // With English listed first and no detection, Chinese receipts
            // came back as unreadable Latin characters. Detection reads both;
            // the person's own language still breaks ties.
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = L10n.isZh
                ? ["zh-Hans", "zh-Hant", "en-US"]
                : ["en-US", "zh-Hans", "zh-Hant"]
            try VNImageRequestHandler(cgImage: page.image, orientation: page.orientation).perform([request])
            let observations = request.results ?? []
            let lines = observations.compactMap { observation in
                observation.topCandidates(1).first.map {
                    ReceiptAmountParser.Line(text: $0.string, boundingBox: observation.boundingBox)
                }
            }
            // Observations use the upright image, so sideways orientations
            // swap the pixel dimensions used to measure tilt.
            let isSideways = [.left, .right, .leftMirrored, .rightMirrored].contains(page.orientation)
            let size = isSideways
                ? CGSize(width: page.image.height, height: page.image.width)
                : CGSize(width: page.image.width, height: page.image.height)
            let angle = ReceiptSkew.angle(
                baselines: observations.map { (left: $0.bottomLeft, right: $0.bottomRight, height: $0.boundingBox.height) },
                imageSize: size
            )
            return ReceiptSkew.straighten(lines, angle: angle, imageSize: size)
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
extension GenerationOptions {
    /// Always the most likely answer, so the same words read the same way.
    /// Xcode 27 renamed the label; CI still builds with Xcode 26.
    static var mostLikely: GenerationOptions {
        #if compiler(>=6.4)
        GenerationOptions(samplingMode: .greedy)
        #else
        GenerationOptions(sampling: .greedy)
        #endif
    }
}

@available(iOS 26.0, *)
@Generable(description: "Values printed on one purchase receipt")
nonisolated struct GeneratedReceipt {
    @Guide(description: "Store, restaurant, or business name as printed, without address or phone")
    var merchant: String?

    @Guide(description: "Purchase date as YYYY-MM-DD, only if printed")
    var date: String?

    @Guide(description: "ISO 4217 currency code only if shown, such as USD, EUR, CNY")
    var currencyCode: String?

    @Guide(description: "Purchased products, dishes, or services in printed order", .maximumCount(60))
    var items: [GeneratedReceiptItem]

    @Guide(description: "Subtotal before tax and tip, exactly as printed")
    var subtotal: String?

    @Guide(description: "Total discount or coupon amount as a number, only if printed on its own summary row")
    var discount: String?

    @Guide(description: "Total tax, VAT, or GST as a number. Not a service charge.")
    var tax: String?

    @Guide(description: "Tip, gratuity, or service charge (服务费) actually charged, as a number. Ignore suggested tip tables.")
    var tip: String?

    @Guide(description: "Final amount paid or due, exactly as printed")
    var total: String?

    @Guide(description: "True only for a restaurant, bar, cafe, food delivery, or ride where a tip is customary. False for supermarkets, grocery stores, pharmacies, and other shops.")
    var isTippedService: Bool

    @Guide(description: "Spending category. Food: restaurants, cafes, bars, takeout, food delivery. Grocery: supermarkets, grocery and convenience stores. Shopping: clothing, electronics, household goods, general retail. Transport: rides, taxis, transit, fuel, parking. Housing: rent, furniture, home repair. Entertainment: movies, concerts, events, games, streaming. Health: pharmacy, medical, dental, fitness. Utilities: electricity, water, gas, phone, internet. Other: anything else.",
           .anyOf(["Food", "Grocery", "Shopping", "Transport", "Housing", "Entertainment", "Health", "Utilities", "Other"]))
    var category: String
}

@available(iOS 26.0, *)
@Generable(description: "One purchased line on a receipt")
nonisolated struct GeneratedReceiptItem {
    @Guide(description: "Item name as printed, without SKU codes or prices")
    var name: String

    @Guide(description: "How many units were bought. A number printed before the item name, or a separate quantity column, is the quantity; 1 if none is printed. Pack sizes and weights such as 12CT, 10枚, or 5kg are part of the name, not the quantity.", .range(1...99))
    var quantity: Int

    @Guide(description: "Line total printed at the right of the row, such as 12.50, not a unit price")
    var price: String
}

@available(iOS 26.0, *)
nonisolated struct ReceiptModelExtractor {
    static let instructions = """
    You read the text of one receipt. The text came from OCR: each line is one printed row, and " | " separates columns on the same row.
    Copy values exactly as printed. Never calculate, estimate, convert, or invent a value. If a value is not printed, leave it empty.
    Every amount is a number only, such as 12.50, never a word or label.
    Items are the products, dishes, or services bought. Do not list subtotal, tax, tip, service charge, total, payment, card, cash, change, or loyalty rows as items.
    """

    func extract(rows: [String]) async throws -> ReceiptDraft {
        let first = try await generatedDraft(rows: rows).grounded(in: rows).reconciled()
        guard first.issueSeverity >= 2 else { return first }
        // A reading that doesn't check out gets one more careful read, told
        // what went wrong; whichever has fewer problems is kept.
        try Task.checkCancellation()
        guard let second = try? await generatedDraft(rows: rows, hint: Self.hint(for: first))
            .grounded(in: rows).reconciled() else { return first }
        return second.issueSeverity < first.issueSeverity ? second : first
    }

    /// What to look at again, in the model's terms.
    static func hint(for draft: ReceiptDraft) -> String {
        var notes = ["Read every amount again exactly as printed."]
        for issue in draft.issues {
            switch issue {
            case .totalNotFound:
                notes.append("Find the amount on the Total row.")
            case .totalNotPrinted(let total):
                notes.append("The total \(total.amount) is not printed on the receipt. Use the amount on the Total row.")
            case .totalMismatch:
                notes.append("Subtotal, tax, and tip must match the amounts printed on those rows, and the total must be the Total row.")
            case .itemsAdjusted:
                notes.append("List every item row once with its printed line price; don't add or repeat items.")
            case .differentCurrency, .textTruncated:
                break
            }
        }
        return notes.joined(separator: " ")
    }

    /// The model's reading as is, before it is checked against the rows.
    private func generatedDraft(rows: [String], hint: String? = nil) async throws -> ReceiptDraft {
        var budget = ReceiptTextLayout.defaultCharacterBudget
        while true {
            let prompt = ReceiptTextLayout.prompt(fromRows: rows, characterBudget: budget)
            // A fresh session per receipt: earlier receipts must never leak
            // into the next one through the conversation transcript.
            let session = LanguageModelSession(instructions: Self.instructions)
            do {
                let response = try await session.respond(
                    to: (hint.map { "Note: \($0)\n\n" } ?? "") + "Receipt text:\n\(prompt.text)",
                    generating: GeneratedReceipt.self,
                    options: .mostLikely
                )
                return ReceiptDraft(response.content, truncated: prompt.truncated)
            } catch let error where Self.isContextOverflow(error) && budget > 1_200 {
                budget = budget * 6 / 10
            }
        }
    }

    private static func isContextOverflow(_ error: Error) -> Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *), let error = error as? LanguageModelError,
           case .contextSizeExceeded = error {
            return true
        }
        #endif
        if let error = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = error {
            return true
        }
        return false
    }
}

@available(iOS 26.0, *)
extension ReceiptDraft {
    nonisolated init(_ generated: GeneratedReceipt, truncated: Bool) {
        self.init(
            merchant: generated.merchant,
            date: ReceiptNumberParser.date(from: generated.date),
            currencyCode: generated.currencyCode,
            items: generated.items.compactMap { item in
                ReceiptNumberParser.money(from: item.price).map {
                    LineItem(name: item.name, quantity: item.quantity, price: $0)
                }
            },
            subtotal: ReceiptNumberParser.money(from: generated.subtotal),
            discount: ReceiptNumberParser.money(from: generated.discount),
            tax: ReceiptNumberParser.money(from: generated.tax),
            tip: ReceiptNumberParser.money(from: generated.tip),
            total: ReceiptNumberParser.money(from: generated.total),
            category: generated.category,
            isTippedService: generated.isTippedService,
            source: .appleIntelligence,
            wasTextTruncated: truncated
        )
    }
}
#endif
