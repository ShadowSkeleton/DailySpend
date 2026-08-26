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
            return L10n.isZh ? "按项目和参与者分配，再一键记录。" : "Assign items to people, then record each share."
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
                // Clear Form Button (Trash Icon)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showNewSplitConfirmation = true }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel(L10n.isZh ? "开始新的一单" : "Start a new split")
                }
            }
            
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
            .alert("Couldn’t Prepare Receipt", isPresented: $showShareError) {
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

            let receiptView = ReceiptView(data: data)
                .frame(width: 375)
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .environment(\.displayScale, displayScale)
            
            let renderer = ImageRenderer(content: receiptView)
            
            renderer.scale = displayScale
            renderer.proposedSize = ProposedViewSize(width: 375, height: nil)
            renderer.isOpaque = true

            if let image = renderer.uiImage,
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

private struct ShareReceipt: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Receipt View (Enhanced for Groups)

struct ReceiptView: View {
    let data: ReceiptData
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "receipt")
                    .font(.system(size: 40))
                    .foregroundStyle(.black)
                    .padding(.bottom, 8)
                
                Text("DailySpend")
                    .font(.system(.title2, design: .serif))
                    .fontWeight(.bold)
                    .tracking(1)
                
                Text(data.title.uppercased())
                    .font(.caption)
                    .fontWeight(.medium)
                    .tracking(2)
                    .foregroundStyle(.gray)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)
            
            DashedLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .frame(height: 1)
                .foregroundStyle(.gray.opacity(0.3))
                .padding(.bottom, 24)
            
            // Items List
            VStack(spacing: 8) { // Tighter spacing for detailed list
                ForEach(data.items.indices, id: \.self) { index in
                    let item = data.items[index]
                    
                    // Logic to detect headers: If value text is empty, treat as Header
                    let isHeader = item.value == .text("") || item.value == .text(L10n.isZh ? "未命名" : "")
                    
                    if isHeader {
                        // Header Style (Person Name)
                        HStack {
                            Text(item.label)
                                .font(.system(.headline, design: .serif))
                                .fontWeight(.bold)
                                .padding(.top, 12) // Add extra space before new person
                            Spacer()
                        }
                    } else {
                        // Standard Item Style
                        HStack {
                            Text(item.label)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(item.label.contains("Total") || item.label.contains("总计") ? .primary : .secondary)
                            Spacer()
                            Text(item.value.displayString)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(item.label.contains("Total") || item.label.contains("总计") ? .bold : .regular)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
            
            DashedLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .frame(height: 1)
                .foregroundStyle(.gray.opacity(0.3))
                .padding(.bottom, 24)
            
            VStack(spacing: 12) {
                if let sub = data.subtotal {
                    ReceiptRow(label: "Subtotal", value: sub)
                }
                if let tax = data.tax, tax > 0 {
                    ReceiptRow(label: "Tax", value: tax)
                }
                if data.tip > 0 {
                    ReceiptRow(label: "Tip", value: data.tip)
                }
                
                Divider().padding(.vertical, 8)
                
                HStack {
                    Text("TOTAL")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.black)
                    Spacer()
                    Text(data.total.formatted(.currency(code: L10n.currencyCode)))
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.black)
                }
            }
            
            Spacer()
            
            Text(data.footer)
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.6))
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 40)
        .frame(width: 375)
        .background(Color.white)
        .foregroundColor(.black)
    }
}

private struct ReceiptRow: View {
    let label: String
    let value: Double
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(.gray)
            Spacer()
            Text(value.formatted(.currency(code: L10n.currencyCode)))
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(.black)
        }
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
