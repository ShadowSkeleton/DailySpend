import SwiftUI

// MARK: - Enums
enum SplitMode: String, CaseIterable {
    case evenly
    case byPerson
    
    var title: String {
        switch self {
        case .evenly: return L10n.isZh ? "快速平分" : "Quick Split"
        case .byPerson: return L10n.isZh ? "按项分账" : "By Item"
        }
    }

    var explanation: String {
        switch self {
        case .evenly:
            return L10n.isZh ? "输入总额，系统会将每一分钱公平分配。" : "Enter one total and keep every cent accounted for."
        case .byPerson:
            return L10n.isZh ? "添加或扫描项目，再选择谁分摊每一项。" : "Add or scan items, then choose who shared each one."
        }
    }
}

struct SplitBillView: View {
    var themeColor: Color
    var goHome: (() -> Void)?
    @Environment(\.displayScale) private var displayScale
    
    @State private var splitMode: SplitMode = .evenly
    
    // Image Generation & Sharing State
    @State private var shareReceipt: ShareReceipt?
    @State private var isGeneratingImage = false
    @State private var showShareError = false
    @State private var shareErrorMessage = ""
    @State private var showNewSplitConfirmation = false
    @State private var isKeyboardVisible = false
    
    // Communication with Children
    @State private var currentReceiptData: ReceiptData?
    @State private var triggerReset: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker(L10n.isZh ? "分账方式" : "Split method", selection: $splitMode) {
                        ForEach(SplitMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("split-mode-picker")

                    Text(splitMode.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("split-mode-explanation")
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 12)

                Group {
                    if splitMode == .evenly {
                        SplitBillEvenlyView(
                            themeColor: themeColor,
                            resetTrigger: $triggerReset,
                            onFinish: goHome,
                            onUpdateReceiptData: { data in currentReceiptData = data },
                            onRequestShare: generateAndShareImage,
                            isPreparingShare: isGeneratingImage
                        )
                    } else {
                        SplitBillBasketView(
                            themeColor: themeColor,
                            resetTrigger: $triggerReset,
                            onUpdateReceiptData: { data in currentReceiptData = data },
                            onRequestShare: generateAndShareImage,
                            isPreparingShare: isGeneratingImage
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(L10n.isZh ? "分账助手" : "Split Bill")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
            .animation(.snappy, value: splitMode)
            .toolbar {
                // Starting over is a reset, not a deletion of saved data, so
                // it uses the standard reset symbol rather than a red trash can.
                // While typing, the same spot puts the keyboard away instead,
                // as New Expense does; nothing floats over the keyboard.
                ToolbarItem(placement: .topBarTrailing) {
                    if isKeyboardVisible {
                        KeyboardDismissButton { UIApplication.dismissKeyboard() }
                    } else {
                        Button(action: { showNewSplitConfirmation = true }) {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .tint(.primary)
                        .accessibilityLabel(L10n.isZh ? "开始新的一单" : "Start a new split")
                    }
                }
            }
            .modifier(KeyboardVisibilityReader(isVisible: $isKeyboardVisible))
            
            .sheet(item: $shareReceipt) { receipt in
                ShareSheet(items: [receipt.image]) { completed in
                    guard completed else { return }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        showNewSplitConfirmation = true
                    }
                }
            }
            // Clear Data Confirmation
            .alert(L10n.isZh ? "开始新的一单？" : "Start a New Split?", isPresented: $showNewSplitConfirmation) {
                Button(L10n.isZh ? "保留数据" : "Keep Data", role: .cancel) { }
                Button(L10n.isZh ? "清空表单" : "Clear Form", role: .destructive) {
                    triggerReset = true
                }
            } message: {
                Text(L10n.isZh ? "当前分账会保留，除非你确认清空表单。" : "Your current split stays intact unless you choose Clear Form.")
            }
            .alert(L10n.isZh ? "无法生成收据" : "Couldn’t Prepare Receipt", isPresented: $showShareError) {
                Button(L10n.ok, role: .cancel) { }
            } message: {
                Text(shareErrorMessage)
            }
            .overlay {
                if isGeneratingImage {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.isZh ? "正在准备收据…" : "Preparing receipt…")
                            .font(.footnote.weight(.medium))
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L10n.isZh ? "正在准备分账收据" : "Preparing split receipt")
                }
            }
        }
    }
    
    // MARK: - Image Generation (Robust Fix with Retry)
    
    @MainActor
    private func generateAndShareImage() {
        guard !isGeneratingImage, let data = currentReceiptData else { return }
        isGeneratingImage = true

        Task { @MainActor in
            await Task.yield()

            if let image = ReceiptImageExporter.image(data: data, scale: displayScale, accent: themeColor),
               image.size.width > 0,
               image.size.height > 0 {
                shareReceipt = ShareReceipt(image: image)
            } else {
                shareErrorMessage = L10n.isZh
                    ? "无法生成收据图片。请稍后重试。"
                    : "The receipt image couldn’t be generated. Please try again."
                showShareError = true
            }

            isGeneratingImage = false
        }
    }
}

@MainActor
enum ReceiptImageExporter {
    static func image(data: ReceiptData, scale: CGFloat, accent: Color = Color(red: 0, green: 0.78, blue: 0.7),
                      dynamicTypeSize: DynamicTypeSize = .large) -> UIImage? {
        let content = ReceiptView(data: data, accent: accent)
            .environment(\.colorScheme, .light)
            .environment(\.displayScale, scale)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 375, height: nil)
        var result: UIImage?
        // Draw into a bitmap context: very tall receipts can exceed the surface
        // size supported by ImageRenderer.uiImage and produce an empty export.
        renderer.render(rasterizationScale: scale) { size, draw in
            guard size.width > 0, size.height > 0,
                  size.width.isFinite, size.height.isFinite,
                  scale.isFinite, scale > 0,
                  size.width * size.height * scale * scale <= 24_000_000 else { return }
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            result = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                draw(context.cgContext)
            }
        }
        return result
    }
}

private struct ShareReceipt: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Shared Receipt Image

/// The image shared from either split mode: a paper slip on a soft tinted
/// background, with the headline figure first and, for an itemized split,
/// one card per person. Always drawn light so it reads well in any chat.
struct ReceiptView: View {
    let data: ReceiptData
    var accent: Color = Color(red: 0, green: 0.78, blue: 0.7)

    private let ink = Color(white: 0.11)
    private let muted = Color(white: 0.45)

    private func currency(_ amount: Double) -> String {
        amount.formatted(.currency(code: L10n.currencyCode))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let highlight = data.highlight { headline(highlight) }
                content
                totals
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ShareReceiptPaper()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
            }

            footer
                .padding(.top, 16)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 26)
        .frame(width: 375)
        .background(
            LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.07)],
                           startPoint: .top, endPoint: .bottom)
        )
        .background(Color.white)
        .foregroundStyle(ink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                Text("DAILYSPEND")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.6)
            }
            .foregroundStyle(accent)
            Text(data.title)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            if let date = data.date {
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(muted)
            }
        }
    }

    private func headline(_ highlight: ReceiptHighlight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(highlight.label.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(accent)
            Text(currency(highlight.amount))
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let caption = highlight.caption {
                Text(caption)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Rows grouped into a card per person; rows before any person stand alone.
    private var groups: [(person: String?, rows: [ReceiptItem])] {
        var result: [(person: String?, rows: [ReceiptItem])] = []
        for item in data.items {
            if item.value == .text("") {
                result.append((item.label, []))
            } else if let last = result.indices.last {
                result[last].rows.append(item)
            } else {
                result.append((nil, [item]))
            }
        }
        return result
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if let person = group.person {
                    personCard(name: person, rows: group.rows, colorIndex: index)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                            line(row.label, row.value.displayString)
                        }
                    }
                }
            }
        }
    }

    private static let avatarColors: [Color] = [
        Color(red: 0.0, green: 0.7, blue: 0.64), Color(red: 0.98, green: 0.55, blue: 0.2),
        Color(red: 0.55, green: 0.4, blue: 0.9), Color(red: 0.93, green: 0.36, blue: 0.5),
        Color(red: 0.2, green: 0.55, blue: 0.95), Color(red: 0.4, green: 0.7, blue: 0.25)
    ]

    private func personCard(name: String, rows: [ReceiptItem], colorIndex: Int) -> some View {
        let total = rows.last { $0.style == .personTotal }
        let lines = rows.filter { $0.style != .personTotal && $0.style != .sharedSubtotal }
        let color = Self.avatarColors[colorIndex % Self.avatarColors.count]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color, in: Circle())
                Text(name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let total {
                    Text(total.value.displayString)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .fixedSize()
                }
            }
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 2) {
                            line(row.label, row.value.displayString, secondary: true)
                            if !row.participants.isEmpty {
                                Text(sharedWith(row.participants))
                                    .font(.caption2)
                                    .foregroundStyle(muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(14)
        .background(Color(white: 0.965), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sharedWith(_ names: [String]) -> String {
        let joined = ListFormatter.localizedString(byJoining: names)
        return L10n.isZh ? "与 \(joined) 分摊" : "Shared by \(joined)"
    }

    private func line(_ label: String, _ value: String, secondary: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(secondary ? .subheadline : .body)
                .foregroundStyle(secondary ? Color(white: 0.3) : ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(secondary ? .subheadline : .body.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(secondary ? Color(white: 0.3) : ink)
                .fixedSize()
        }
    }

    private var totals: some View {
        VStack(spacing: 9) {
            DashedLine()
                .stroke(Color(white: 0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(height: 1)
                .padding(.bottom, 4)
            if let subtotal = data.subtotal {
                line(L10n.isZh ? "小计" : "Subtotal", currency(subtotal), secondary: true)
            }
            if let tax = data.tax, tax > 0 {
                line(L10n.isZh ? "税费" : "Tax", currency(tax), secondary: true)
            }
            if data.tip > 0 {
                line(L10n.isZh ? "小费" : "Tip", currency(data.tip), secondary: true)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.isZh ? "总计" : "Total")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                Spacer()
                Text(currency(data.total))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .monospacedDigit()
            }
            .padding(.top, 4)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
            Text(L10n.isZh ? "由 DailySpend 分账" : "Split with DailySpend")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(accent.opacity(0.9))
        .frame(maxWidth: .infinity)
    }
}

/// A paper slip: rounded at the top, torn along the bottom.
private struct ShareReceiptPaper: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tooth: CGFloat = 7
        let teeth = max(Int(rect.width / 18), 1)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - tooth))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
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

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    var onComplete: ((Bool) -> Void)?
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
