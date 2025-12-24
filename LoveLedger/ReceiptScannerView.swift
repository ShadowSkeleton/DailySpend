import SwiftUI
import Vision
import VisionKit

struct ReceiptScannerView: UIViewControllerRepresentable {
    @Binding var scannedAmount: Double?
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
            // 只要有一张图，立刻开始处理，并关闭相机
            guard scan.pageCount >= 1 else {
                controller.dismiss(animated: true)
                return
            }
            
            let image = scan.imageOfPage(at: 0)
            processImage(image, controller: controller)
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
        }
        
        // MARK: - 核心 AI 算法
        func processImage(_ image: UIImage, controller: VNDocumentCameraViewController) {
            guard let cgImage = image.cgImage else { return }
            
            let request = VNRecognizeTextRequest { [weak self] request, error in
                guard let self = self else { return }
                
                guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                    DispatchQueue.main.async { controller.dismiss(animated: true) }
                    return
                }
                
                var potentialPrices: [(value: Double, box: CGRect, text: String)] = []
                var keyWords: [CGRect] = []
                
                // 扩展关键词库 (中英文)
                let targetWords = ["total", "amount", "balance", "due", "payment", "合计", "总额", "实付", "应付"]
                
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let text = candidate.string.lowercased()
                    let box = observation.boundingBox // 0~1 归一化坐标 (Y轴 0在下，1在上)
                    
                    // A. 提取潜在金额
                    if let value = self.extractCurrency(from: text) {
                        potentialPrices.append((value, box, text))
                    }
                    
                    // B. 提取关键词位置
                    for word in targetWords {
                        if text.contains(word) {
                            keyWords.append(box)
                            break
                        }
                    }
                }
                
                // 2. 智能筛选
                let bestGuess = self.findBestMatch(prices: potentialPrices, keywords: keyWords)
                
                // 3. 返回结果并关闭
                DispatchQueue.main.async {
                    if let result = bestGuess {
                        self.parent.scannedAmount = result
                    }
                    controller.dismiss(animated: true)
                }
            }
            
            // 配置 OCR 参数
            request.recognitionLevel = .accurate // 必须用精准模式
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"] // 支持中文小票
            
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
        
        // MARK: - 算法策略
        func findBestMatch(prices: [(value: Double, box: CGRect, text: String)], keywords: [CGRect]) -> Double? {
            guard !prices.isEmpty else { return nil }
            
            // 1. 过滤掉不合理的数字 (Auth Code 杀手)
            let validPrices = prices.filter { priceTuple in
                let val = priceTuple.value
                
                // 规则A: 排除过大的数字 (Auth Code 通常很大，比如 56472)
                if val > 5000 {
                    return false
                }
                
                // 规则B: 排除看起来像整数的大数字 (如 2025, 8090)
                let isIntegerLooking = !priceTuple.text.contains(".")
                if val > 100 && isIntegerLooking {
                    return false
                }
                
                return true
            }
            
            // 策略 A：关键词行对齐 (强关联)
            for keywordBox in keywords {
                let candidates = validPrices.filter { price in
                    // 计算 Y 轴中心点距离
                    let yDiff = abs(price.box.midY - keywordBox.midY)
                    // 严格判定：必须在同一行 (差异 < 3%)
                    let isSameLine = yDiff < 0.03
                    
                    // 或者在关键词紧挨着的下方 (Total: \n 100.00)
                    let isDirectlyBelow = (keywordBox.minY - price.box.maxY) < 0.05 && (keywordBox.minY - price.box.maxY) > -0.01
                    
                    return isSameLine || isDirectlyBelow
                }
                
                if let match = candidates.max(by: { $0.value < $1.value }) {
                    return match.value
                }
            }
            
            // 策略 B：底部区域最大值 (兜底)
            let bottomPrices = validPrices.filter { $0.box.minY < 0.5 }
            if let maxBottom = bottomPrices.max(by: { $0.value < $1.value }) {
                return maxBottom.value
            }
            
            return nil
        }
        
        func extractCurrency(from text: String) -> Double? {
            // 预处理：只保留数字和小数点，移除逗号和符号
            let clean = text.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
            
            guard let value = Double(clean) else { return nil }
            
            // 基础过滤
            if value < 0.01 { return nil } // 排除 0
            
            // 排除年份干扰 (2020-2030) 且没有小数点的
            if !text.contains(".") && value >= 2020 && value <= 2030 { return nil }
            
            return value
        }
    }
}
