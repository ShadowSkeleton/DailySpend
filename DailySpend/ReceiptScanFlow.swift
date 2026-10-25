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
        // UI tests and screenshots can't drive the camera; this feeds a fixed
        // synthetic receipt through the same review path instead.
        if ProcessInfo.processInfo.arguments.contains(ReceiptDraft.uiTestLaunchArgument) {
            onDraft?(ReceiptDraft.uiTestSample)
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

    var body: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(themeColor)
                Text(L10n.isZh ? "正在读取收据…" : "Reading receipt…")
                    .font(.headline)
                Label(L10n.isZh ? "在此设备上处理" : "Processed on this device", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n.cancel, action: onCancel)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(minWidth: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.isZh ? "正在读取收据" : "Reading receipt")
        }
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: draft.source == .appleIntelligence ? "sparkles" : "doc.text.viewfinder")
                .font(.title3)
                .foregroundStyle(themeColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.isZh ? "已从收据填写" : "Filled from receipt")
                    .font(.subheadline.weight(.semibold))
                if !summary.isEmpty {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(warnings, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
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
                Text(L10n.isZh ? "保存前请核对。" : "Check the details before saving.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("receipt-draft-banner")
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
        draft.issues.compactMap(message(for:))
    }

    /// What the scan did on the person's behalf; nothing here is a problem.
    private var notes: [String] {
        var messages: [String] = []
        if context == .split, let discount = draft.discount, discount > .zero, !draft.items.isEmpty {
            let amount = discount.amount.formatted(.currency(code: L10n.currencyCode))
            messages.append(L10n.isZh
                ? "\(amount) 的折扣已按价格比例分摊到各项目。"
                : "A \(amount) discount is spread across items by price.")
        }
        if context == .split, draft.expectsNoTip {
            messages.append(L10n.isZh ? "这类消费通常不付小费，小费已设为“不加”。" : "Tip set to None: tips aren’t usual for this kind of purchase.")
        }
        if draft.source == .textRecognition {
            messages.append(context == .split
                ? (L10n.isZh ? "只读取到总额。开启 Apple 智能后可识别明细。" : "Only the total was read. Turn on Apple Intelligence to read items.")
                : (L10n.isZh ? "只读取到总额，请选择分类。" : "Only the total was read. Choose a category."))
        }
        return messages
    }

    private func message(for issue: ReceiptDraft.Issue) -> String? {
        func currency(_ money: Money) -> String { money.amount.formatted(.currency(code: L10n.currencyCode)) }
        switch issue {
        case .totalNotFound:
            return L10n.isZh ? "没有找到总额，请输入金额。" : "No total was found. Enter the amount."
        case .totalMismatch(let calculated, let printed):
            return L10n.isZh
                ? "小计、税和小费合计 \(currency(calculated))，但收据总额为 \(currency(printed))。"
                : "Subtotal, tax, and tip add up to \(currency(calculated)), but the receipt total is \(currency(printed))."
        case .itemsAdjusted(let adjustment):
            guard context == .split else { return nil }
            if adjustment > .zero {
                return L10n.isZh
                    ? "有 \(currency(adjustment)) 未能对应到项目，已列为“\(ReceiptDraft.otherItemsName)”。"
                    : "\(currency(adjustment)) didn’t match any item and is listed as \(ReceiptDraft.otherItemsName)."
            }
            return L10n.isZh
                ? "项目合计比小计多 \(currency(Money(minorUnits: -adjustment.minorUnits)))，已按比例调整。"
                : "Items added up to \(currency(Money(minorUnits: -adjustment.minorUnits))) more than the subtotal, so prices were adjusted proportionally."
        case .differentCurrency(let code):
            return L10n.isZh
                ? "这张收据可能使用 \(code)。金额会按原数字记录，不做换算。"
                : "This receipt may be in \(code). Amounts are recorded as printed, without conversion."
        case .textTruncated:
            return L10n.isZh ? "收据很长，可能有部分项目未读取。" : "This receipt is long; some items may be missing."
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
            source: .appleIntelligence
        )
    }
}
#endif
