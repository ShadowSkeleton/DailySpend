import SwiftUI
import Vision
import VisionKit

/// Selects a receipt's payable total from Vision OCR lines.
///
/// Vision intentionally stays responsible for reading the receipt. This parser
/// only ranks the already-recognized lines, so amounts are deterministic,
/// inspectable, and never sent off-device.
enum ReceiptAmountParser {
    struct Line: Equatable {
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

struct ReceiptScannerView: UIViewControllerRepresentable {
    @Binding var scannedAmount: Double?
    @Binding var scanErrorMessage: String?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var parent: ReceiptScannerView
        
        init(_ parent: ReceiptScannerView) {
            self.parent = parent
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount >= 1 else {
                finish(controller, errorMessage: "No receipt was captured. You can enter the amount manually.")
                return
            }
            
            let image = scan.imageOfPage(at: 0)
            processImage(image, controller: controller)
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            finish(
                controller,
                errorMessage: "DailySpend couldn’t use the camera. Check Camera access in Settings, then try again."
            )
        }
        
        // MARK: - 核心 AI 算法
        func processImage(_ image: UIImage, controller: VNDocumentCameraViewController) {
            guard let cgImage = image.cgImage else {
                finish(controller, errorMessage: "This receipt image couldn’t be read. You can enter the amount manually.")
                return
            }
            
            let request = VNRecognizeTextRequest { [weak self] request, error in
                guard let self = self else { return }
                
                guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                    self.finish(
                        controller,
                        errorMessage: "DailySpend couldn’t read that receipt. You can enter the amount manually."
                    )
                    return
                }
                
                var recognizedLines: [ReceiptAmountParser.Line] = []
                
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    recognizedLines.append(
                        ReceiptAmountParser.Line(
                            text: candidate.string,
                            boundingBox: observation.boundingBox
                        )
                    )
                }
                
                let bestGuess = ReceiptAmountParser.bestAmount(from: recognizedLines)
                
                if let result = bestGuess {
                    DispatchQueue.main.async {
                        self.parent.scannedAmount = result
                        controller.dismiss(animated: true)
                    }
                } else {
                    self.finish(
                        controller,
                        errorMessage: "No total was found on this receipt. You can enter the amount manually."
                    )
                }
            }
            
            // 配置 OCR 参数
            request.recognitionLevel = .accurate // 必须用精准模式
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"] // 支持中文小票
            
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    self.finish(
                        controller,
                        errorMessage: "DailySpend couldn’t process that receipt. You can enter the amount manually."
                    )
                }
            }
        }

        private func finish(_ controller: VNDocumentCameraViewController, errorMessage: String) {
            DispatchQueue.main.async {
                self.parent.scanErrorMessage = errorMessage
                controller.dismiss(animated: true)
            }
        }
        
    }
}
