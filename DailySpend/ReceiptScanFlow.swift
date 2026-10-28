import PhotosUI
import SwiftUI
import UIKit

enum ReceiptCaptureSource {
    case camera
    case photos
}

/// Owns one scan from capture to a finished draft. Each screen that scans
/// keeps its own controller, so a scan never fills a form it didn't start in.
@MainActor
@Observable
final class ReceiptScanController {
    var isCameraPresented = false
    var isPhotoPickerPresented = false
    var isCameraTipPresented = false
    var photoSelection: PhotosPickerItem?
    var errorMessage: String?
    private(set) var isReading = false

    @ObservationIgnored var onDraft: ((ReceiptDraft) -> Void)?
    @ObservationIgnored private let reader: any ReceiptReading
    @ObservationIgnored private var readingTask: Task<Void, Never>?

    init(reader: any ReceiptReading = ReceiptReader()) {
        self.reader = reader
    }

    func start(_ source: ReceiptCaptureSource) {
        #if DEBUG
        // UI tests can't drive the photo picker; this reads the next image
        // file passed at launch with the real on-device reader.
        if let page = ReceiptDraft.nextUITestReceiptFile() {
            read([page])
            return
        }
        // UI tests and screenshots can't drive the camera; this feeds a fixed
        // synthetic receipt through the same review path instead.
        if ProcessInfo.processInfo.arguments.contains(ReceiptDraft.uiTestLaunchArgument) {
            guard ProcessInfo.processInfo.arguments.contains(ReceiptDraft.uiTestSlowArgument) else {
                onDraft?(ReceiptDraft.uiTestSample)
                return
            }
            // Holds the reading overlay on screen long enough to inspect it.
            isReading = true
            readingTask = Task {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                isReading = false
                onDraft?(ReceiptDraft.uiTestSample)
            }
            return
        }
        #endif
        ReceiptReader.prepare()
        switch source {
        case .camera:
            if UserDefaults.standard.object(forKey: "showScanTip") as? Bool ?? true {
                isCameraTipPresented = true
            } else {
                isCameraPresented = true
            }
        case .photos:
            isPhotoPickerPresented = true
        }
    }

    func read(_ pages: [ReceiptPage]) {
        readingTask?.cancel()
        isReading = true
        readingTask = Task {
            do {
                let draft = try await reader.read(pages)
                guard !Task.isCancelled else { return }
                isReading = false
                onDraft?(draft)
            } catch is CancellationError {
                isReading = false
            } catch {
                isReading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func readSelectedPhoto() {
        guard let item = photoSelection else { return }
        photoSelection = nil
        isReading = true
        readingTask?.cancel()
        readingTask = Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let cgImage = image.cgImage else {
                isReading = false
                errorMessage = L10n.isZh ? "无法打开这张照片。" : "This photo couldn’t be opened."
                return
            }
            guard !Task.isCancelled else { return }
            isReading = false
            read([ReceiptPage(image: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))])
        }
    }

    func cancel() {
        readingTask?.cancel()
        readingTask = nil
        isReading = false
    }
}

extension View {
    /// Presents the camera, photo picker, reading progress, and errors for a
    /// receipt scan started from this view.
    func receiptScanning(_ controller: ReceiptScanController, themeColor: Color) -> some View {
        modifier(ReceiptScanningModifier(controller: controller, themeColor: themeColor))
    }
}

private struct ReceiptScanningModifier: ViewModifier {
    @Bindable var controller: ReceiptScanController
    let themeColor: Color
    @AppStorage("showScanTip") private var showScanTip = true

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $controller.isCameraPresented) {
                ReceiptScannerView(
                    onCapture: { pages in
                        controller.isCameraPresented = false
                        controller.read(pages)
                    },
                    onCancel: { controller.isCameraPresented = false },
                    onError: { message in
                        controller.isCameraPresented = false
                        controller.errorMessage = message
                    }
                )
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $controller.isPhotoPickerPresented,
                          selection: $controller.photoSelection,
                          matching: .images)
            .onChange(of: controller.photoSelection) { _, item in
                if item != nil { controller.readSelectedPhoto() }
            }
            .overlay {
                if controller.isReading {
                    ReceiptReadingOverlay(themeColor: themeColor, onCancel: controller.cancel)
                        .transition(.opacity)
                }
            }
            .animation(.snappy, value: controller.isReading)
            .alert(L10n.scanTipTitle, isPresented: $controller.isCameraTipPresented) {
                Button(L10n.dontShowAgain) { showScanTip = false; controller.isCameraPresented = true }
                Button(L10n.gotIt) { controller.isCameraPresented = true }
            } message: { Text(L10n.scanTipMessage) }
            .alert(L10n.isZh ? "无法读取收据" : "Couldn’t Read Receipt", isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )) {
                Button(L10n.ok, role: .cancel) { controller.errorMessage = nil }
            } message: {
                Text(controller.errorMessage ?? "")
            }
    }
}

/// Opens the camera, or offers Photos as well when both are available.
struct ReceiptScanButton: View {
    let controller: ReceiptScanController
    let themeColor: Color
    var title = L10n.isZh ? "扫描收据" : "Scan Receipt"

    var body: some View {
        Group {
            if ReceiptScannerView.isSupported {
                Menu {
                    Button { controller.start(.camera) } label: {
                        Label(L10n.isZh ? "用相机扫描" : "Scan with Camera", systemImage: "camera")
                    }
                    Button { controller.start(.photos) } label: {
                        Label(L10n.isZh ? "从照片中选择" : "Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                } label: { label }
            } else {
                Button { controller.start(.photos) } label: { label }
            }
        }
        .accessibilityIdentifier("scan-receipt")
        .accessibilityHint(L10n.isZh ? "在设备上读取收据并填写金额" : "Reads a receipt on this device and fills in the amounts.")
    }

    private var label: some View {
        Label(title, systemImage: "doc.text.viewfinder")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(themeColor)
            .background(themeColor.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
    }
}

private struct ReceiptReadingOverlay: View {
    let themeColor: Color
    let onCancel: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            VStack(spacing: 10) {
                ReceiptReadingAnimation(themeColor: themeColor)
                    .padding(.bottom, 2)
                ReceiptReadingStatus()
                Label(L10n.isZh ? "在此设备上处理" : "Processed on this device", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n.cancel, action: onCancel)
                    .font(.subheadline.weight(.semibold))
                    .tint(themeColor)
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(minWidth: 240)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .scaleEffect(appeared ? 1 : 0.88)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.isZh ? "正在读取收据" : "Reading receipt")
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { appeared = true }
        }
    }
}

/// Steps through what the reader is doing, so a few seconds of waiting
/// feel like progress rather than a stall.
private struct ReceiptReadingStatus: View {
    @State private var start = Date()

    private let steps = L10n.isZh
        ? ["正在读取收据…", "正在识别项目…", "正在查找总额…", "正在核对金额…"]
        : ["Reading receipt…", "Finding the items…", "Spotting the total…", "Checking the math…"]

    var body: some View {
        TimelineView(.periodic(from: start, by: 1.6)) { context in
            let step = min(Int(context.date.timeIntervalSince(start) / 1.6), steps.count - 1)
            Text(steps[step])
                .font(.headline)
                .id(step)
                .frame(maxWidth: .infinity)
                .transition(.push(from: .bottom))
                .animation(.snappy, value: step)
        }
        .frame(height: 24)
        .clipped()
    }
}

/// A receipt floating on a soft halo while a beam sweeps down it. Lines
/// light up in the theme color as they are read, and sparkles twinkle
/// around it. Reduce Motion shows the same picture standing still.
private struct ReceiptReadingAnimation: View {
    let themeColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private let paperSize = CGSize(width: 72, height: 94)
    private let lineWidths: [CGFloat] = [0.5, 0.82, 0.64, 0.74, 0.56]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = reduceMotion ? 0.9 : context.date.timeIntervalSince(start)
            // Down the receipt and back, easing at each end like a scanner.
            let sweep = (1 - cos(time * 2.4)) / 2
            ZStack {
                Circle()
                    .fill(themeColor.opacity(0.14))
                    .frame(width: 118, height: 118)
                    .scaleEffect(1 + 0.05 * sin(time * 2.4))
                Circle()
                    .stroke(themeColor.opacity(0.18), lineWidth: 1.5)
                    .frame(width: 118, height: 118)
                    .scaleEffect(1 + 0.18 * (time * 0.6).truncatingRemainder(dividingBy: 1))
                    .opacity(reduceMotion ? 0 : 1 - (time * 0.6).truncatingRemainder(dividingBy: 1))

                paper(sweep: sweep)
                    .rotationEffect(.degrees(-4 + 3 * sin(time * 1.2)))
                    .offset(y: -3 * sin(time * 2.4))

                sparkle(size: 15, time: time, phase: 0).offset(x: 46, y: -40)
                sparkle(size: 10, time: time, phase: 2.1).offset(x: -48, y: -22)
                sparkle(size: 12, time: time, phase: 4.2).offset(x: 44, y: 38)
            }
            .frame(width: 140, height: 132)
        }
        .accessibilityHidden(true)
    }

    private func paper(sweep: Double) -> some View {
        let rows = lineWidths.count + 1
        return ZStack(alignment: .topLeading) {
            ReceiptPaperShape()
                .fill(.white)
                .shadow(color: .black.opacity(0.14), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(lineWidths.indices, id: \.self) { index in
                    line(width: lineWidths[index], height: 4, lit: lit(row: index, of: rows, sweep: sweep))
                }
                HStack {
                    line(width: 0.3, height: 6, lit: lit(row: rows - 1, of: rows, sweep: sweep))
                    Spacer(minLength: 0)
                    line(width: 0.36, height: 6, lit: lit(row: rows - 1, of: rows, sweep: sweep))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 13)

            LinearGradient(colors: [themeColor.opacity(0), themeColor.opacity(0.32)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(themeColor)
                        .frame(height: 2)
                        .shadow(color: themeColor, radius: 4)
                }
                .offset(y: sweep * (paperSize.height - 12) - 12)
        }
        .frame(width: paperSize.width, height: paperSize.height)
        .clipShape(ReceiptPaperShape())
    }

    /// How brightly a row glows: full once the beam has passed it.
    private func lit(row: Int, of rows: Int, sweep: Double) -> Double {
        let position = (Double(row) + 0.5) / Double(rows)
        return min(max((sweep - position) * 6 + 0.5, 0), 1)
    }

    private func line(width: CGFloat, height: CGFloat, lit: Double) -> some View {
        Capsule()
            .fill(Color.black.opacity(0.12))
            .overlay(Capsule().fill(themeColor).opacity(lit))
            .frame(width: (paperSize.width - 24) * width, height: height)
    }

    private func sparkle(size: CGFloat, time: Double, phase: Double) -> some View {
        let pulse = reduceMotion ? 0.8 : (sin(time * 3 + phase) + 1) / 2
        return Image(systemName: "sparkle")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(themeColor)
            .scaleEffect(0.6 + 0.5 * pulse)
            .rotationEffect(.degrees(pulse * 40))
            .opacity(0.35 + 0.65 * pulse)
    }
}

/// A paper slip with rounded top corners and a torn, zigzag bottom edge.
private struct ReceiptPaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 8
        let tooth: CGFloat = 5
        let teeth = 7
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - tooth))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tooth))
        let step = rect.width / CGFloat(teeth)
        for index in stride(from: teeth, to: 0, by: -1) {
            let x = rect.minX + CGFloat(index) * step
            path.addLine(to: CGPoint(x: x - step / 2, y: rect.maxY))
            path.addLine(to: CGPoint(x: x - step, y: rect.maxY - tooth))
        }
        path.closeSubpath()
        return path
    }
}

/// Shows what a scan filled in and anything that needs a second look.
struct ReceiptDraftBanner: View {
    enum Context {
        case expense
        case split
    }

    let draft: ReceiptDraft
    let context: Context
    let themeColor: Color
    let onDismiss: () -> Void

    var body: some View {
        let warnings = self.warnings
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol(warnings: warnings))
                .font(.title3)
                .foregroundStyle(statusColor(warnings: warnings))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle(warnings: warnings))
                        .font(.subheadline.weight(.semibold))
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if warnings.isEmpty && draft.isVerified {
                    Text(L10n.isZh ? "小计、税和小费与收据上的总额一致。" : "Subtotal, tax, and tip add up to the total printed on the receipt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(warnings, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(notes, id: \.self) { message in
                    Label(message, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(disclaimer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityIdentifier("receipt-ai-disclaimer")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.isZh ? "关闭提示" : "Dismiss")
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if !warnings.isEmpty {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("receipt-draft-banner")
    }

    // MARK: Status

    /// Three plain states: checked and consistent, something to look at, or
    /// filled in without a way to check it.
    private func statusTitle(warnings: [String]) -> String {
        if !warnings.isEmpty {
            return L10n.isZh
                ? "保存前请核对 \(warnings.count) 处"
                : (warnings.count == 1 ? "Check 1 thing before saving" : "Check \(warnings.count) things before saving")
        }
        if draft.isVerified { return L10n.isZh ? "金额已核对" : "Amounts check out" }
        return L10n.isZh ? "已从收据填写" : "Filled from receipt"
    }

    private func statusSymbol(warnings: [String]) -> String {
        if !warnings.isEmpty { return "exclamationmark.triangle.fill" }
        if draft.isVerified { return "checkmark.seal.fill" }
        return draft.source == .appleIntelligence ? "sparkles" : "doc.text.viewfinder"
    }

    private func statusColor(warnings: [String]) -> Color {
        if !warnings.isEmpty { return .orange }
        if draft.isVerified { return .green }
        return themeColor
    }

    private var disclaimer: String {
        draft.source == .appleIntelligence
            ? (L10n.isZh ? "由 Apple 智能在本机读取。AI 可能出错，请核对重要信息。"
                         : "Read on this device by Apple Intelligence. AI can make mistakes, so check important details.")
            : (L10n.isZh ? "在本机读取。保存前请核对金额。" : "Read on this device. Check the amount before saving.")
    }

    private var summary: String {
        var parts: [String] = []
        if let merchant = draft.merchant { parts.append(merchant) }
        if !draft.items.isEmpty {
            parts.append(L10n.isZh ? "\(draft.items.count) 项" : "\(draft.items.count) \(draft.items.count == 1 ? "item" : "items")")
        }
        if let date = draft.date { parts.append(date.formatted(.dateTime.month().day())) }
        return parts.joined(separator: " · ")
    }

    /// Values that need checking before saving.
    private var warnings: [String] {
        var messages: [String] = []
        // An older receipt saves into its own month, out of view on Home.
        if let date = draft.date, !Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month) {
            let shown = date.formatted(.dateTime.year().month(.wide).day())
            messages.append(L10n.isZh
                ? "收据日期为 \(shown)，将记在那个月份。如需记在今天，请修改日期。"
                : "Dated \(shown), so it will be saved in that month. Change the date to record it today.")
        }
        return messages + draft.issues.compactMap(message(for:))
    }

    /// What the scan did on the person's behalf; nothing here is a problem.
    private var notes: [String] {
        var messages: [String] = []
        if context == .split, let discount = draft.discountSpreadAcrossItems {
            let amount = discount.amount.formatted(.currency(code: L10n.currencyCode))
            messages.append(L10n.isZh
                ? "\(amount) 的折扣已按价格比例分摊到各项目。"
                : "A \(amount) discount is spread across items by price.")
        }
        if context == .split, draft.expectsNoTip, TipPreset.isCustomary {
            messages.append(L10n.isZh ? "这类消费通常不付小费，小费已设为“不加”。" : "Tip set to None: tips aren’t usual for this kind of purchase.")
        }
        if draft.source == .textRecognition {
            messages.append(context == .split
                ? (L10n.isZh ? "只读取到总额。开启 Apple 智能后可识别明细。" : "Only the total was read. Turn on Apple Intelligence to read items.")
                : (L10n.isZh ? "只读取到总额，请选择分类。" : "Only the total was read. Choose a category."))
        }
        return messages
    }

    /// Each warning says what to check first, then why.
    private func message(for issue: ReceiptDraft.Issue) -> String? {
        func currency(_ money: Money) -> String { money.amount.formatted(.currency(code: L10n.currencyCode)) }
        switch issue {
        case .totalNotFound:
            return L10n.isZh ? "请输入总额：收据上没有找到。" : "Enter the total. It couldn’t be found on the receipt."
        case .totalNotPrinted(let total):
            return L10n.isZh
                ? "请核对总额：读到的 \(currency(total)) 在收据上没有出现，可能读错了。"
                : "Check the total. \(currency(total)) doesn’t appear anywhere on the receipt, so it may be misread."
        case .totalMismatch(let calculated, let printed):
            // Show the sum itself, so it's clear which number looks wrong.
            var parts: [String] = []
            if let subtotal = draft.subtotal {
                parts.append((L10n.isZh ? "小计 " : "subtotal ") + currency(subtotal))
            }
            if draft.isDiscountAfterSubtotal, let discount = draft.discount {
                parts.append((L10n.isZh ? "− 折扣 " : "− discount ") + currency(discount))
            }
            if let tax = draft.tax { parts.append((L10n.isZh ? "+ 税 " : "+ tax ") + currency(tax)) }
            if let tip = draft.tip { parts.append((L10n.isZh ? "+ 小费 " : "+ tip ") + currency(tip)) }
            let sum = parts.joined(separator: " ")
            return L10n.isZh
                ? "请核对总额：\(sum) = \(currency(calculated))，但总额读到的是 \(currency(printed))。"
                : "Check the total. The receipt’s parts add up to \(currency(calculated)) (\(sum)), but the total reads \(currency(printed))."
        case .itemsAdjusted(let adjustment):
            guard context == .split else { return nil }
            if adjustment > .zero {
                return L10n.isZh
                    ? "可能漏读了项目：小计中有 \(currency(adjustment)) 没对应到项目，已列为“\(ReceiptDraft.otherItemsName)”。"
                    : "Some items may be missing. \(currency(adjustment)) of the subtotal didn’t match an item, so it’s listed as \(ReceiptDraft.otherItemsName)."
            }
            let excess = Money(minorUnits: -adjustment.minorUnits)
            let subtotal = draft.itemsTotal + adjustment
            return L10n.isZh
                ? "请核对项目：项目合计 \(currency(draft.itemsTotal))，比小计 \(currency(subtotal)) 多 \(currency(excess))，价格已按比例调低。"
                : "Check the items. They add up to \(currency(draft.itemsTotal)), \(currency(excess)) more than the \(currency(subtotal)) subtotal, so prices were lowered to match."
        case .differentCurrency(let code):
            return L10n.isZh
                ? "这张收据可能使用 \(code)。金额按原数字记录，不做换算。"
                : "This receipt looks like it’s in \(code). Amounts are recorded as printed, not converted."
        case .textTruncated:
            return L10n.isZh ? "收据很长，末尾的项目可能没有读到。" : "This receipt is long, so items near the end may be missing."
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

#if DEBUG
extension ReceiptDraft {
    static let uiTestLaunchArgument = "-ui-test-receipt"
    static let uiTestSlowArgument = "-ui-test-receipt-slow"
    /// Followed by comma-separated image paths, read one per scan.
    static let uiTestFilesArgument = "-ui-test-receipt-files"
    @MainActor private static var uiTestFilesRead = 0

    @MainActor static func nextUITestReceiptFile() -> ReceiptPage? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: uiTestFilesArgument), index + 1 < arguments.count else { return nil }
        let paths = arguments[index + 1].split(separator: ",").map(String.init)
        guard uiTestFilesRead < paths.count,
              let image = UIImage(contentsOfFile: paths[uiTestFilesRead])?.cgImage else { return nil }
        uiTestFilesRead += 1
        return ReceiptPage(image: image, orientation: .up)
    }

    /// A fictional restaurant receipt for UI tests and screenshots.
    static var uiTestSample: ReceiptDraft {
        ReceiptDraft(
            merchant: "Harbor Noodle House",
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
            items: [
                LineItem(name: "Spicy Beef Noodles", quantity: 1, price: Money(minorUnits: 1650)),
                LineItem(name: "Dumplings", quantity: 2, price: Money(minorUnits: 1800)),
                LineItem(name: "Jasmine Tea", quantity: 1, price: Money(minorUnits: 450))
            ],
            subtotal: Money(minorUnits: 3900),
            tax: Money(minorUnits: 351),
            total: Money(minorUnits: 4251),
            category: "Food",
            isTippedService: true,
            source: .appleIntelligence
        )
    }
}
#endif
