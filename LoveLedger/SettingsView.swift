import SwiftUI
import SwiftData
import CloudKit
import UserNotifications
import UniformTypeIdentifiers

// MARK: - Helper Extension for Keyboard Dismissal
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    var themeColor: Color
    
    // 全局设置
    @AppStorage("isBudgetEnabled") private var isBudgetEnabled = false
    @AppStorage("budgetAmount") private var budgetAmount = 0.0
    @AppStorage("alertThreshold") private var alertThreshold = 100.0
    @AppStorage("dailyNotify") private var dailyNotify = false
    @AppStorage("notifyTime") private var notifyTime: Double = 0
    @AppStorage("lastSyncTimestamp") private var lastSyncTimestamp: Double = 0
    
    @State private var timeDate: Date = Date()
    @FocusState private var isInputFocused: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Query private var allExpenses: [Expense]
    @Query private var categoryBudgets: [CategoryBudget]
    
    @State private var showFileImporter = false
    @State private var showFileExporter = false
    @State private var showRestoreAlert = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var importedData: [ExpenseBackupItem]?
    @State private var jsonDocument: JSONBackupDocument?
    @State private var showCategoryBudgetSheet = false
    
    // 控制 About 页面
    @State private var showAboutSheet = false
    
    @State private var iCloudStatusText: String = L10n.iCloudVerifying
    @State private var iCloudIconColor: Color = .gray
    
    var backupDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }
    
    var lastSyncFormatted: String {
        if lastSyncTimestamp == 0 { return "--" }
        let date = Date(timeIntervalSince1970: lastSyncTimestamp)
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        Form {
            // MARK: - iCloud Section
            Section {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: iCloudIconColor == .blue ? [.blue, .cyan] : [Color.gray.opacity(0.3), Color.gray.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "icloud.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.isZh ? "iCloud 同步" : "iCloud Sync")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(iCloudIconColor)
                                .frame(width: 8, height: 8)
                            Text(iCloudStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if iCloudIconColor == .blue {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(L10n.isZh ? "上次同步" : "Last Synced")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(lastSyncFormatted)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            
            // MARK: - Budget Section
            Section(header: Text("Budget")) {
                Toggle(L10n.budgetEnable, isOn: $isBudgetEnabled)
                    .tint(themeColor)
                    .onChange(of: isBudgetEnabled) { _, enabled in
                        if !enabled { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["dailyBudget"]) }
                    }
                
                if isBudgetEnabled {
                    HStack {
                        Text(L10n.budgetAmount)
                        Spacer()
                        TextField("0", value: $budgetAmount, format: .number)
                            .keyboardType(.decimalPad)
                            .focused($isInputFocused)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(themeColor)
                            .bold()
                    }
                    
                    if budgetAmount == 0 {
                        Text(L10n.budgetRequired).font(.caption).foregroundStyle(.red)
                    }
                    
                    HStack {
                        Text(L10n.alertThreshold)
                        Spacer()
                        TextField("0", value: $alertThreshold, format: .number)
                            .keyboardType(.decimalPad)
                            .focused($isInputFocused)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.orange)
                    }
                    
                    HStack {
                        Text(L10n.isZh ? "分类预算 (可选)" : "Category Limits (Optional)")
                            .foregroundStyle(Color.primary)
                        Spacer()
                        if !categoryBudgets.isEmpty {
                            Text("\(categoryBudgets.count) set").foregroundStyle(.secondary).font(.caption)
                        }
                        Image(systemName: "chevron.right").font(.caption).fontWeight(.bold).foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideKeyboard()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showCategoryBudgetSheet = true }
                    }
                    
                    Toggle(L10n.dailyNotification, isOn: $dailyNotify).tint(themeColor)
                    if dailyNotify {
                        DatePicker(L10n.notificationTime, selection: $timeDate, displayedComponents: .hourAndMinute)
                            .onChange(of: timeDate) { _, newValue in notifyTime = newValue.timeIntervalSince1970 }
                    }
                }
            }
            
            // MARK: - Data Management
            Section(header: Text(L10n.dataManagement)) {
                HStack {
                    Label(L10n.backupData, systemImage: "square.and.arrow.up").foregroundStyle(themeColor)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { hideKeyboard(); prepareBackup() }
                
                HStack {
                    Label(L10n.restoreData, systemImage: "square.and.arrow.down").foregroundStyle(.orange)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { hideKeyboard(); showFileImporter = true }
            }
            
            // MARK: - ✨ About Section (Optimized Touch)
            Section {
                // 修复：不再使用 Button，改用 HStack + contentShape + onTapGesture
                // 这样整个行都是点击热区，反应更灵敏
                HStack {
                    Label {
                        Text(L10n.isZh ? "关于 DailySpend" : "About DailySpend")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(.pink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle()) // 关键：确保整行可点击
                .onTapGesture {
                    hideKeyboard()
                    // 增加一点微小的触觉反馈
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    showAboutSheet = true
                }
            }
        }
        .navigationTitle(L10n.settings)
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { hideKeyboard() }
        .onAppear {
            if notifyTime == 0 { var components = Calendar.current.dateComponents([.year, .month, .day], from: Date()); components.hour = 10; components.minute = 0; let defaultTime = Calendar.current.date(from: components) ?? Date(); timeDate = defaultTime; notifyTime = defaultTime.timeIntervalSince1970 } else { timeDate = Date(timeIntervalSince1970: notifyTime) }
            checkiCloudStatus()
        }
        .sheet(isPresented: $showCategoryBudgetSheet) { CategoryBudgetSettingView(themeColor: themeColor) }
        .sheet(isPresented: $showAboutSheet) { AboutView() }
        .fileExporter(isPresented: $showFileExporter, document: jsonDocument, contentType: .json, defaultFilename: "DailySpend_Backup") { _ in }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let data = try Data(contentsOf: url)
                        let decoder = JSONDecoder()
                        var items: [ExpenseBackupItem] = []
                        decoder.dateDecodingStrategy = .formatted(backupDateFormatter)
                        do { items = try decoder.decode([ExpenseBackupItem].self, from: data) }
                        catch {
                            let legacyDecoder = JSONDecoder(); legacyDecoder.dateDecodingStrategy = .secondsSince1970
                            items = try legacyDecoder.decode([ExpenseBackupItem].self, from: data)
                        }
                        DispatchQueue.main.async { self.importedData = items; self.showRestoreAlert = true }
                    } catch { self.errorMessage = "Error: \(error.localizedDescription)"; self.showErrorAlert = true }
                }
            case .failure(let error): self.errorMessage = error.localizedDescription; self.showErrorAlert = true
            }
        }
        .alert(L10n.restoreAlertTitle, isPresented: $showRestoreAlert) {
            Button(L10n.cancel, role: .cancel) { }
            Button(L10n.restoreData, role: .destructive) { performRestore() }
        } message: { Text(L10n.restoreAlertMessage) }
        .alert(L10n.success, isPresented: $showSuccessAlert) { Button(L10n.ok) { } } message: { Text(L10n.restoreSuccess) }
        .alert(L10n.errorTitle, isPresented: $showErrorAlert) { Button(L10n.ok) { } } message: { Text(errorMessage) }
    }
    
    func checkiCloudStatus() {
        CKContainer.default().accountStatus { status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self.iCloudStatusText = L10n.iCloudAvailable
                    self.iCloudIconColor = .blue
                    self.lastSyncTimestamp = Date().timeIntervalSince1970
                case .noAccount: self.iCloudStatusText = L10n.iCloudUnavailable; self.iCloudIconColor = .red
                case .restricted: self.iCloudStatusText = L10n.iCloudRestricted; self.iCloudIconColor = .orange
                default: self.iCloudStatusText = "Unknown"; self.iCloudIconColor = .gray
                }
            }
        }
    }
    
    func prepareBackup() {
        do {
            let fetchDescriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            let expenses = try modelContext.fetch(fetchDescriptor)
            var items: [ExpenseBackupItem] = []
            for expense in expenses {
                items.append(ExpenseBackupItem(amount: expense.amount, category: expense.category, note: expense.note, date: expense.date, frequency: expense.safeFrequency))
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .formatted(backupDateFormatter)
            encoder.outputFormatting = .prettyPrinted
            let encoded = try encoder.encode(items)
            DispatchQueue.main.async { self.jsonDocument = JSONBackupDocument(data: encoded); self.showFileExporter = true }
        } catch { self.errorMessage = "Backup failed: \(error.localizedDescription)"; self.showErrorAlert = true }
    }
    
    func performRestore() {
        guard let items = importedData else { return }
        do {
            let existing = try modelContext.fetch(FetchDescriptor<Expense>())
            for exp in existing { modelContext.delete(exp) }
            try modelContext.save()
            for item in items {
                modelContext.insert(Expense(amount: item.amount, category: item.category, note: item.note, date: item.date, frequency: item.frequency ?? .none))
            }
            try modelContext.save()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showSuccessAlert = true }
        } catch { self.errorMessage = "Restore failed"; self.showErrorAlert = true }
    }
}

// MARK: - ✨ About View (Corrected Info & Auto Build)
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    // ✨ 自动获取版本号和 Build 号
    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (Build \(build))"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    
                    // 1. App Info Header
                    VStack(spacing: 16) {
                        Image(systemName: "heart.text.square.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .foregroundStyle(.pink.gradient)
                            .shadow(radius: 10)
                        
                        VStack(spacing: 6) {
                            // 修正名称：DailySpend
                            Text("DailySpend")
                                .font(.largeTitle)
                                .fontWeight(.heavy)
                                .foregroundStyle(.primary)
                            
                            // 修正版本：自动拉取
                            Text(appVersion)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 40)
                    
                    // 2. Developer Credit
                    VStack(spacing: 12) {
                        Text("Designed & Developed by")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(2)
                        
                        Text("Jackson Feng")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.primary)
                        
                        Text("A Personal Project")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.gradient)
                            .clipShape(Capsule())
                    }
                    
                    Divider().padding(.horizontal, 40)
                    
                    // 3. Welcome Message (Updated Name)
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.isZh ? "欢迎使用！" : "Welcome!")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text(L10n.isZh
                             ? "DailySpend 是我出于个人兴趣开发的一款记账应用，旨在提供最纯粹、最隐私的记账体验。\n\n没有广告，没有追踪，只有清晰的财务洞察。"
                             : "DailySpend is a personal passion project designed to make expense tracking simple, private, and insightful.\n\nNo ads, no tracking, just you and your financial goals.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: 500)
                    
                    // 4. TestFlight Feedback Button
                    Button(action: {
                        if let url = URL(string: "itms-beta://") {
                            UIApplication.shared.open(url)
                        } else if let url = URL(string: "https://testflight.apple.com/") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text(L10n.isZh ? "在 TestFlight 中反馈" : "Feedback via TestFlight")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.gradient)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: .orange.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    Text(L10n.isZh
                         ? "您的反馈对我非常重要！如果在测试过程中遇到 Bug 或有任何建议，欢迎随时提交反馈。"
                         : "Your feedback means the world to me! If you spot a bug or have a feature request, please let me know.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    
                    Spacer(minLength: 50)
                    
                    // 修正年份：2026
                    Text("© 2026 Jackson Feng. All rights reserved.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) { dismiss() }
                }
            }
        }
    }
}

// ... CategoryBudgetSettingView (Unchanged)
struct CategoryBudgetSettingView: View {
    var themeColor: Color
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var budgets: [CategoryBudget]
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Expense.categories, id: \.name) { category in
                        CategoryBudgetRow(category: category)
                    }
                } footer: {
                    Text(L10n.isZh ? "未设置的分类将不设限，仅受总预算约束。" : "Categories set to 0 or left empty will have no specific limit.")
                        .font(.caption).padding(.top)
                }
            }
            .navigationTitle(L10n.isZh ? "分类预算" : "Category Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { dismiss() }.fontWeight(.bold).tint(themeColor)
                }
            }
        }
    }
}

// Helper Row View
struct CategoryBudgetRow: View {
    let category: (name: String, icon: String, color: Color)
    @Environment(\.modelContext) private var modelContext
    @State private var amountText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack {
            Label { Text(L10n.categoryName(category.name)).fontWeight(.medium) }
            icon: { Image(systemName: category.icon).foregroundStyle(category.color) }
            Spacer()
            TextField("No Limit", text: $amountText)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .onAppear { loadBudget() }
                .onChange(of: isFocused) { _, focused in if !focused { saveBudget() } }
                .onSubmit { saveBudget() }
                .onDisappear { saveBudget() }
            Text(L10n.currencySymbol).foregroundStyle(.secondary).font(.callout)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isFocused { isFocused = true } }
    }
    
    private func loadBudget() {
        let name = category.name
        let fetchDescriptor = FetchDescriptor<CategoryBudget>(predicate: #Predicate { $0.category == name })
        if let record = try? modelContext.fetch(fetchDescriptor).first {
            if record.amount > 0 { amountText = String(format: "%.0f", record.amount) }
        }
    }
    
    private func saveBudget() {
        let cleanText = amountText.replacingOccurrences(of: ",", with: ".")
        let amount = Double(cleanText) ?? 0
        let targetCategoryName = category.name
        let fetchDescriptor = FetchDescriptor<CategoryBudget>(predicate: #Predicate { $0.category == targetCategoryName })
        do {
            let results = try modelContext.fetch(fetchDescriptor)
            let currentRecord = results.first
            var didChange = false
            if let record = currentRecord {
                if amount <= 0 { modelContext.delete(record); didChange = true }
                else if record.amount != amount { record.amount = amount; didChange = true }
            } else if amount > 0 {
                let newBudget = CategoryBudget(category: targetCategoryName, amount: amount)
                modelContext.insert(newBudget); didChange = true
            }
            if didChange { try modelContext.save() }
        } catch { print("❌ Failed to save budget: \(error)") }
    }
}
