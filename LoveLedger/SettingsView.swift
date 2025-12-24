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
    
    @State private var timeDate: Date = Date()
    @FocusState private var isInputFocused: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Query private var allExpenses: [Expense]
    // 实时查询分类预算数量
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
    
    @State private var iCloudStatusText: String = L10n.iCloudVerifying
    @State private var iCloudIconColor: Color = .gray
    
    var backupDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }
    
    var body: some View {
        Form {
            // MARK: - iCloud Section
            Section {
                HStack {
                    Image(systemName: "icloud.fill").font(.title2).foregroundStyle(iCloudIconColor)
                    VStack(alignment: .leading) {
                        Text("iCloud").font(.headline)
                        Text(iCloudStatusText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            
            // MARK: - Budget Section
            Section(header: Text("Budget")) {
                Toggle(L10n.budgetEnable, isOn: $isBudgetEnabled)
                    .tint(themeColor)
                    .onChange(of: isBudgetEnabled) { _, enabled in
                        if !enabled { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["dailyBudget"]) }
                    }
                
                if isBudgetEnabled {
                    // 1. 总预算输入
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
                    
                    // 分类预算入口
                    HStack {
                        Text(L10n.isZh ? "分类预算 (可选)" : "Category Limits (Optional)")
                            .foregroundStyle(Color.primary)
                        Spacer()
                        if !categoryBudgets.isEmpty {
                            Text("\(categoryBudgets.count) set")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideKeyboard()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showCategoryBudgetSheet = true
                        }
                    }
                    
                    Toggle(L10n.dailyNotification, isOn: $dailyNotify).tint(themeColor)
                    
                    if dailyNotify {
                        DatePicker(L10n.notificationTime, selection: $timeDate, displayedComponents: .hourAndMinute)
                            .onChange(of: timeDate) { _, newValue in notifyTime = newValue.timeIntervalSince1970 }
                    }
                }
            }
            
            // MARK: - Data Management Section
            Section(header: Text(L10n.dataManagement)) {
                // 备份按钮
                HStack {
                    Label(L10n.backupData, systemImage: "square.and.arrow.up")
                        .foregroundStyle(themeColor)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    hideKeyboard()
                    prepareBackup()
                }
                
                // 恢复按钮
                HStack {
                    Label(L10n.restoreData, systemImage: "square.and.arrow.down")
                        .foregroundStyle(.orange)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    hideKeyboard()
                    showFileImporter = true
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
        // Sheets & Alerts
        .sheet(isPresented: $showCategoryBudgetSheet) {
            CategoryBudgetSettingView(themeColor: themeColor)
        }
        .fileExporter(isPresented: $showFileExporter, document: jsonDocument, contentType: .json, defaultFilename: "DailySpend_Backup") { result in
            switch result {
            case .success: print("Export success")
            case .failure(let error):
                self.errorMessage = "System Error: \(error.localizedDescription)"
                self.showErrorAlert = true
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let data = try Data(contentsOf: url)
                        let decoder = JSONDecoder()
                        var items: [ExpenseBackupItem] = []
                        
                        // 尝试 1: 新格式 (带日期字符串)
                        decoder.dateDecodingStrategy = .formatted(backupDateFormatter)
                        do {
                            items = try decoder.decode([ExpenseBackupItem].self, from: data)
                        } catch {
                            // 尝试 2: 旧格式
                            let legacyDecoder = JSONDecoder()
                            legacyDecoder.dateDecodingStrategy = .secondsSince1970
                            items = try legacyDecoder.decode([ExpenseBackupItem].self, from: data)
                        }
                        
                        DispatchQueue.main.async {
                            self.importedData = items
                            self.showRestoreAlert = true
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.errorMessage = "Format Error: Data might be corrupted.\n\(error.localizedDescription)"
                            self.showErrorAlert = true
                        }
                    }
                } else {
                    self.errorMessage = "Permission denied."
                    self.showErrorAlert = true
                }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                self.showErrorAlert = true
            }
        }
        // ✨ 优化：将 Alert 挂载到 Form 上，防止冲突
        .alert(L10n.restoreAlertTitle, isPresented: $showRestoreAlert) {
            Button(L10n.cancel, role: .cancel) { }
            Button(L10n.restoreData, role: .destructive) { performRestore() }
        } message: { Text(L10n.restoreAlertMessage) }
        
        // ✨ 将 Success Alert 单独挂载，避免与 Restore Alert 冲突
        .alert(L10n.success, isPresented: $showSuccessAlert) {
            Button(L10n.ok) { }
        } message: { Text(L10n.restoreSuccess) }
        
        .alert(L10n.errorTitle, isPresented: $showErrorAlert) {
            Button(L10n.ok) { }
        } message: { Text(errorMessage) }
    }
    
    func checkiCloudStatus() {
        CKContainer.default().accountStatus { status, error in
            DispatchQueue.main.async {
                switch status {
                case .available: self.iCloudStatusText = L10n.iCloudAvailable; self.iCloudIconColor = .blue
                case .noAccount: self.iCloudStatusText = L10n.iCloudUnavailable; self.iCloudIconColor = .red
                case .restricted: self.iCloudStatusText = L10n.iCloudRestricted; self.iCloudIconColor = .orange
                default: self.iCloudStatusText = "Unknown"; self.iCloudIconColor = .gray
                }
            }
        }
    }
    
    // ✨ 关键修复：使用 FetchDescriptor 安全地获取数据
    func prepareBackup() {
        do {
            // 使用 FetchDescriptor 直接从数据库获取，避免使用可能有问题的 @Query 缓存
            let fetchDescriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            let expenses = try modelContext.fetch(fetchDescriptor)
            
            var items: [ExpenseBackupItem] = []
            
            for expense in expenses {
                // ✨ 使用 safeFrequency 安全访问
                let item = ExpenseBackupItem(
                    amount: expense.amount,
                    category: expense.category,
                    note: expense.note,
                    date: expense.date,
                    frequency: expense.safeFrequency
                )
                items.append(item)
            }
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .formatted(backupDateFormatter)
            encoder.outputFormatting = .prettyPrinted
            let encoded = try encoder.encode(items)
            
            DispatchQueue.main.async {
                self.jsonDocument = JSONBackupDocument(data: encoded)
                self.showFileExporter = true
            }
        } catch {
            self.errorMessage = "Backup failed: \(error.localizedDescription)"
            self.showErrorAlert = true
        }
    }
    
    func performRestore() {
        guard let items = importedData else { return }
        
        // ✨ 关键修复：使用 FetchDescriptor 重新获取数据，避免使用可能过期的 @Query 结果
        do {
            // 1. 从数据库直接获取所有记录（而非使用 @Query 缓存）
            let fetchDescriptor = FetchDescriptor<Expense>()
            let existingExpenses = try modelContext.fetch(fetchDescriptor)
            
            // 2. 删除所有旧数据
            for expense in existingExpenses {
                modelContext.delete(expense)
            }
            
            // 3. 立即保存删除操作，确保数据库状态一致
            try modelContext.save()
            
            // 4. 插入新数据
            for item in items {
                let newExpense = Expense(
                    amount: item.amount,
                    category: item.category,
                    note: item.note,
                    date: item.date,
                    frequency: item.frequency ?? .none
                )
                modelContext.insert(newExpense)
            }
            
            // 5. 保存插入操作
            try modelContext.save()
            
            // 6. 延迟弹出成功提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showSuccessAlert = true
            }
            
        } catch {
            self.errorMessage = "Restore failed: \(error.localizedDescription)"
            self.showErrorAlert = true
        }
    }
}

// MARK: - Custom Month Picker Component
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
                        let budget = budgets.first(where: { $0.category == category.name })
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
