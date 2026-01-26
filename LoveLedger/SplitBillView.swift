import SwiftUI

// MARK: - Enums
enum SplitMode: String, CaseIterable {
    case evenly
    case byPerson
    
    var title: String {
        switch self {
        case .evenly: return L10n.isZh ? "平摊" : "Evenly"
        case .byPerson: return L10n.isZh ? "按人" : "By Person"
        }
    }
}

struct SplitBillView: View {
    var themeColor: Color
    var goHome: (() -> Void)?
    
    @State private var splitMode: SplitMode = .evenly
    
    // Shared State for "Record My Share"
    @State private var showAddExpense = false
    @State private var pendingRecordAmount: Double = 0
    @State private var pendingRecordNote: String = ""
    
    // Image Generation & Sharing State
    @State private var generatedReceiptImage: UIImage?
    @State private var showShareSheet = false
    @State private var isGeneratingImage = false
    @State private var showClearDataAlert = false
    
    // Communication with Children
    @State private var currentReceiptData: ReceiptData?
    @State private var triggerReset: Bool = false
    
    // State to force receipt rendering
    // CRITICAL for fixing the black screen issue
    @State private var renderID = UUID()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 1. Hidden Receipt View for rendering
                // Using opacity 0.01 makes it invisible to user but "visible" to system rendering
                // renderID forces it to refresh before we capture it
                if let data = currentReceiptData {
                    ReceiptView(data: data)
                        .frame(width: 375)
                        .background(Color.white)
                        .environment(\.colorScheme, .light) // Always render in Light mode
                        .environment(\.displayScale, UIScreen.main.scale) // Ensure correct scale
                        .opacity(0.01)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .id(renderID)
                }
                
                // 2. Main Content
                VStack(spacing: 0) {
                    // Mode Picker
                    Picker("Split Mode", selection: $splitMode) {
                        ForEach(SplitMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    
                    // Content Switcher
                    Group {
                        if splitMode == .evenly {
                            SplitBillEvenlyView(
                                themeColor: themeColor,
                                resetTrigger: $triggerReset,
                                onFinish: goHome, // Evenly view uses onFinish to navigate home
                                onUpdateReceiptData: { data in currentReceiptData = data },
                                onRequestShare: generateAndShareImage
                            )
                        } else {
                            SplitBillBasketView(
                                themeColor: themeColor,
                                resetTrigger: $triggerReset,
                                // Basket view handles its own recording internally via the sheet,
                                // so we don't need to pass onRecord unless we want the parent to handle it.
                                // If your BasketView definition has onRecord, pass it.
                                // Based on previous file, it DOES have onRecord.
                                onRecord: triggerRecord,
                                onUpdateReceiptData: { data in currentReceiptData = data },
                                onRequestShare: generateAndShareImage
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(L10n.isZh ? "分账助手" : "Split Bill")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
            .animation(.snappy, value: splitMode)
            .toolbar {
                // Clear Form Button (Trash Icon)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showClearDataAlert = true }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            
            // Sheets
            .sheet(isPresented: $showAddExpense) {
                AddExpenseView(
                    themeColor: themeColor,
                    prefilledAmount: pendingRecordAmount,
                    prefilledNote: pendingRecordNote,
                    prefilledCategory: "Food",
                    onSave: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { goHome?() }
                    }
                )
                .id(UUID())
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = generatedReceiptImage {
                    ShareSheet(items: [image]) { completed in
                        if completed {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                showClearDataAlert = true
                            }
                        }
                    }
                }
            }
            // Clear Data Confirmation
            .alert(L10n.isZh ? "导出成功" : "Receipt Shared", isPresented: $showClearDataAlert) {
                Button(L10n.isZh ? "保留数据" : "Keep Data", role: .cancel) { }
                Button(L10n.isZh ? "清空表单" : "Clear Form", role: .destructive) {
                    triggerReset = true
                }
            } message: {
                Text(L10n.isZh ? "是否要清空当前分账数据并开始新的一单？" : "Would you like to clear the current form and start a new bill?")
            }
        }
    }
    
    // MARK: - Actions
    
    func triggerRecord(amount: Double, note: String) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.pendingRecordAmount = amount
            self.pendingRecordNote = note
            self.showAddExpense = true
        }
    }
    
    // MARK: - Image Generation (Robust Fix with Retry)
    
    @MainActor
    private func generateAndShareImage() {
        // 1. Dismiss Keyboard to ensure clean screenshot
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        guard !isGeneratingImage, let data = currentReceiptData else { return }
        isGeneratingImage = true
        
        // CRITICAL: Force the hidden receipt view to refresh its identity
        renderID = UUID()
        
        // 2. Render on Main Actor with retry logic
        Task { @MainActor in
            // Wait for layout to settle
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            
            // Create a dedicated rendering view instance
            let receiptView = ReceiptView(data: data)
                .frame(width: 375)
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .environment(\.displayScale, UIScreen.main.scale)
            
            let renderer = ImageRenderer(content: receiptView)
            
            // Explicitly set scale and size
            renderer.scale = UIScreen.main.scale
            renderer.proposedSize = ProposedViewSize(width: 375, height: nil)
            
            // Retry Mechanism: Try up to 3 times to get a valid image
            for _ in 0..<3 {
                if let image = renderer.uiImage {
                    self.generatedReceiptImage = image
                    self.showShareSheet = true
                    break
                }
                // Small delay before retry
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }
            
            if self.generatedReceiptImage == nil {
                print("Error: ImageRenderer failed after retries")
            }
            
            self.isGeneratingImage = false
        }
    }
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
                
                Text("LoveLedger")
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
