import SwiftUI
import Vision
import VisionKit

/// Selects a receipt's payable total from Vision OCR lines.
///
/// Vision intentionally stays responsible for reading the receipt. This parser
/// only ranks the already-recognized lines, so amounts are deterministic,
/// inspectable, and never sent off-device.
nonisolated enum ReceiptAmountParser {
    struct Line: Equatable, Sendable {
        let text: String
        let boundingBox: CGRect
    }

    private static let centsPattern = #"(?:[$€£¥]\s*)?((?:\d{1,3}(?:,\d{3})*|\d+)\.\d{2})(?!\d)"#
    static func bestAmount(from lines: [Line]) -> Double? {
        let candidates = lines.compactMap { line -> (line: Line, amount: Double, priority: Int)? in
            guard let amount = currencyAmount(in: line.text) else { return nil }
            let priority = labelPriority(for: line.text)
            return (line, amount, priority)
        }

        // A printed total should always beat a subtotal. When two lines carry
        // equally good labels, use the lower one on the receipt—the final
        // payable total conventionally appears after intermediate totals.
        if let labeledTotal = candidates
            .filter({ $0.priority > 0 })
            .max(by: { lhs, rhs in
                lhs.priority == rhs.priority
                    ? lhs.line.boundingBox.minY > rhs.line.boundingBox.minY
                    : lhs.priority < rhs.priority
            }) {
            return labeledTotal.amount
        }

        // Some printers put a label on one line and the currency on the next.
        // Only use an unlabeled line directly beneath a strong label.
        let strongLabels = lines
            .filter { labelPriority(for: $0.text) >= 900 }
            .sorted { lhs, rhs in
                if labelPriority(for: lhs.text) != labelPriority(for: rhs.text) {
                    return labelPriority(for: lhs.text) > labelPriority(for: rhs.text)
                }
                return lhs.boundingBox.minY < rhs.boundingBox.minY
            }

        for label in strongLabels where currencyAmount(in: label.text) == nil {
            let amountBelowLabel = candidates
                .filter { candidate in
                    let verticalDistance = label.boundingBox.minY - candidate.line.boundingBox.maxY
                    return verticalDistance >= -0.01 && verticalDistance < 0.06
                }
                .min(by: { lhs, rhs in
                    let lhsDistance = label.boundingBox.minY - lhs.line.boundingBox.maxY
                    let rhsDistance = label.boundingBox.minY - rhs.line.boundingBox.maxY
                    return lhsDistance < rhsDistance
                })

            if let amountBelowLabel { return amountBelowLabel.amount }
        }

        // Last resort for receipts whose labels were not recognized. Exclude
        // intermediate amounts and prefer the largest price near the bottom.
        let fallbackCandidates = candidates.filter {
            $0.priority >= 0 && $0.line.boundingBox.minY < 0.5
        }
        return fallbackCandidates.max(by: { $0.amount < $1.amount })?.amount
    }

    static func currencyAmount(in text: String) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        guard let expression = try? NSRegularExpression(pattern: centsPattern),
              let match = expression.matches(in: text, range: range).last,
              let amountRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return Double(text[amountRange].replacingOccurrences(of: ",", with: ""))
    }

    private static func labelPriority(for text: String) -> Int {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let excludedLabels = ["subtotal", "sub-total", "sales tax", " tax", "tip", "gratuity", "change", "discount", "小计", "税", "服务费"]
        guard !excludedLabels.contains(where: normalized.contains) else { return -1 }

        let strongLabels = ["grand total", "total due", "total amount", "amount due", "balance due", "payment due", "amount payable", "合计", "总额", "应付", "实付"]
        if strongLabels.contains(where: normalized.contains) { return 1_000 }

        if normalized.range(of: #"\btotal\b"#, options: .regularExpression) != nil || normalized.contains("总计") {
            return 900
        }
        if normalized.contains("balance") || normalized.contains("amount") || normalized.contains("payment") {
            return 700
        }
        return 0
    }
}

/// Presents the system document camera and returns every captured page.
/// Reading happens after the camera closes, so its progress can be shown and
/// cancelled in DailySpend's own interface.
struct ReceiptScannerView: UIViewControllerRepresentable {
    var onCapture: ([ReceiptPage]) -> Void
    var onCancel: () -> Void
    var onError: (String) -> Void

    /// The document camera is unavailable in Simulator and on some iPads.
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: ReceiptScannerView

        init(_ parent: ReceiptScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Long receipts are often captured in several pages. A small cap
            // keeps reading fast and the recognized text within model limits.
            let pages = (0..<min(scan.pageCount, 4)).compactMap { index in
                scan.imageOfPage(at: index).cgImage.map { ReceiptPage(image: $0, orientation: .up) }
            }
            if pages.isEmpty {
                parent.onError(L10n.isZh ? "没有拍到收据。你可以手动输入金额。" : "No receipt was captured. You can enter the amount manually.")
            } else {
                parent.onCapture(pages)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onError(L10n.isZh
                ? "DailySpend 无法使用相机。请在“设置”中检查相机权限后重试。"
                : "DailySpend couldn’t use the camera. Check Camera access in Settings, then try again.")
        }
    }
}
