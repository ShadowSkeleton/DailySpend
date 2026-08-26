import SwiftUI
import SwiftData
import CloudKit
import UserNotifications
import UniformTypeIdentifiers
import LocalAuthentication

// MARK: - Settings View
struct SettingsView: View {
    var themeColor: Color
    
    // 全局设置
    @AppStorage("isBudgetEnabled") private var isBudgetEnabled = false
    @AppStorage("budgetAmount") private var budgetAmount = 0.0
    @AppStorage("alertThreshold") private var alertThreshold = 100.0
    @AppStorage("dailyNotify") private var dailyNotify = false
    @AppStorage("notifyTime") private var notifyTime: Double = 0
    @AppStorage("isAppLockEnabled") private var isAppLockEnabled = false
    @AppStorage(LoveLedgerApp.cloudKitStoreFallbackKey) private var isUsingLocalStoreFallback = false
    
    @State private var timeDate: Date = Date()
    @FocusState private var isInputFocused: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Query private var allExpenses: [Expense]
    @Query private var categoryBudgets: [CategoryBudget]
    
    @State private var showFileImporter = false
    @State private var showFileExporter = false
    @State private var showBackupPassphraseSheet = false
    @State private var showRestorePassphraseSheet = false
    @State private var isPreparingBackup = false
    @State private var isPreparingRestore = false
    @State private var showRestoreAlert = false
    @State private var showSuccessAlert = false
    @State private var showBackupSavedAlert = false
    @State private var showFinalReplaceConfirmation = false
    @State private var showErrorAlert = false
    @State private var showAppLockUnavailableAlert = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var importedBackup: ImportedBackup?
    @State private var jsonDocument: JSONBackupDocument?
    @State private var pendingEncryptedBackupData: Data?
    @State private var backupFilename = "DailySpend_Backup"
    @State private var showCategoryBudgetSheet = false
    
    // 控制 About 页面
    @State private var showAboutSheet = false
    
    @State private var iCloudStatusText: String = L10n.iCloudVerifying
    @State private var iCloudIconColor: Color = .gray

    private enum BackupExportPurpose {
        case standard
        case safetyBeforeReplace
    }

    @State private var backupExportPurpose = BackupExportPurpose.standard

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { isAppLockEnabled },
            set: { shouldEnable in
                guard shouldEnable else {
                    isAppLockEnabled = false
                    return
                }

                let context = LAContext()
                var error: NSError?
                guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                    showAppLockUnavailableAlert = true
                    return
                }
                isAppLockEnabled = true
            }
        )
    }
    
    var backupDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }
    
    var restorePreviewMessage: String {
        guard let importedBackup else { return L10n.restoreAlertMessage }
        let backup = importedBackup.backup
        let base = L10n.isZh
            ? "将导入 \(backup.expenses.count) 笔账单和 \(backup.categoryBudgets.count) 个分类预算。"
            : "This backup contains \(backup.expenses.count) expenses and \(backup.categoryBudgets.count) category budgets."
        let legacyNote = importedBackup.isLegacy
            ? (L10n.isZh ? "\n旧版重复账单会从下一次计划周期继续；已生成的记录会保留，且不会重复创建。" : "\nLegacy recurring entries resume on their next scheduled cycle; existing generated entries are kept without duplication.")
            : ""
        let safetyNote = L10n.isZh
            ? "\n安全合并只会添加缺失项目，保留本机已有项目。"
            : "\nSafe Merge adds missing items only and preserves matching local records."
        return base + safetyNote + legacyNote
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

                    Button(action: checkiCloudStatus) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(themeColor)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("refresh-icloud-status")
                    .accessibilityLabel(L10n.isZh ? "刷新 iCloud 状态" : "Refresh iCloud status")
                    .accessibilityHint(L10n.isZh ? "检查此设备是否可访问私有 iCloud 数据库" : "Checks whether this device can access its private iCloud database.")

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
                    
                    Button {
                        isInputFocused = false
                        showCategoryBudgetSheet = true
                    } label: {
                        HStack {
                            Text(L10n.isZh ? "分类预算 (可选)" : "Category Limits (Optional)")
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if !categoryBudgets.isEmpty {
                                Text("\(categoryBudgets.count) set").foregroundStyle(.secondary).font(.caption)
                            }
                            Image(systemName: "chevron.right").font(.caption).fontWeight(.bold).foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Toggle(L10n.dailyNotification, isOn: $dailyNotify)
                        .tint(themeColor)
                        .onChange(of: dailyNotify) { _, isEnabled in
                            if isEnabled { NotificationManager.shared.requestPermission() }
                        }
                    if dailyNotify {
                        DatePicker(L10n.notificationTime, selection: $timeDate, displayedComponents: .hourAndMinute)
                            .onChange(of: timeDate) { _, newValue in notifyTime = newValue.timeIntervalSince1970 }
                    }
                }
            }
            
            // MARK: - Privacy
            Section(header: Text(L10n.isZh ? "隐私" : "Privacy")) {
                Toggle(L10n.isZh ? "打开时要求设备认证" : "Require Device Authentication", isOn: appLockBinding)
                    .tint(themeColor)
                    .accessibilityHint(L10n.isZh
                        ? "重新打开 DailySpend 时要求 Face ID、Touch ID 或设备密码。"
                        : "Requires Face ID, Touch ID, or your device passcode when DailySpend reopens.")

                Text(L10n.isZh
                    ? "开启后，DailySpend 在重新打开时会锁定；应用切换器中也会隐藏财务记录。"
                    : "When enabled, DailySpend locks when reopened. Financial records are also hidden in the app switcher.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Data Management
            Section(header: Text(L10n.dataManagement)) {
                Button(action: requestEncryptedBackup) {
                    Label(L10n.isZh ? "创建加密备份" : "Create Encrypted Backup", systemImage: "lock.doc")
                        .foregroundStyle(themeColor)
                }
                .disabled(isPreparingBackup)
                .accessibilityIdentifier("create-json-backup")
                .accessibilityHint(L10n.isZh ? "创建可保存到文件的完整 JSON 备份" : "Creates a complete JSON backup that you can save to Files.")
                
                Button(action: presentFileImporter) {
                    Label(L10n.restoreData, systemImage: "square.and.arrow.down")
                        .foregroundStyle(.orange)
                }
                .disabled(isPreparingRestore)
                .accessibilityIdentifier("restore-json-backup")
                .accessibilityHint(L10n.isZh ? "选择先前保存的 JSON 备份" : "Select a previously saved JSON backup.")

                Text(L10n.isZh
                    ? "新备份使用您的密码加密。密码不会被保存或恢复；替换恢复前会要求先保存一份当前数据。"
                    : "New backups are encrypted with your password. DailySpend never stores or recovers it; replacement restore first requires saving your current data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // MARK: - About
            Section {
                Button {
                    isInputFocused = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showAboutSheet = true
                } label: {
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
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(L10n.settings)
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                KeyboardDismissButton { isInputFocused = false }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if notifyTime == 0 { var components = Calendar.current.dateComponents([.year, .month, .day], from: Date()); components.hour = 10; components.minute = 0; let defaultTime = Calendar.current.date(from: components) ?? Date(); timeDate = defaultTime; notifyTime = defaultTime.timeIntervalSince1970 } else { timeDate = Date(timeIntervalSince1970: notifyTime) }
            checkiCloudStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            checkiCloudStatus()
        }
        .sheet(isPresented: $showCategoryBudgetSheet) { CategoryBudgetSettingView(themeColor: themeColor) }
        .sheet(isPresented: $showAboutSheet) { AboutView() }
        .fileExporter(isPresented: $showFileExporter, document: jsonDocument, contentType: .json, defaultFilename: backupFilename) { result in
            handleBackupExport(result)
        }
        .sheet(isPresented: $showBackupPassphraseSheet) {
            BackupPassphraseSheet(
                title: backupExportPurpose == .standard
                    ? (L10n.isZh ? "加密备份" : "Encrypt Backup")
                    : (L10n.isZh ? "保护恢复前备份" : "Protect Safety Backup"),
                message: L10n.isZh
                    ? "创建一个至少 12 个字符的密码。DailySpend 无法保存或找回这个密码。"
                    : "Create a passphrase with at least 12 characters. DailySpend never stores or recovers it.",
                requiresConfirmation: true
            ) { passphrase in
                prepareEncryptedBackup(passphrase: passphrase)
            }
        }
        .sheet(isPresented: $showRestorePassphraseSheet) {
            BackupPassphraseSheet(
                title: L10n.isZh ? "解锁加密备份" : "Unlock Encrypted Backup",
                message: L10n.isZh
                    ? "输入创建此备份时使用的密码。"
                    : "Enter the passphrase used when this backup was created.",
                requiresConfirmation: false
            ) { passphrase in
                unlockImportedBackup(with: passphrase)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard fileSize <= Self.maximumBackupFileSize else {
                            throw BackupFileError.tooLarge
                        }
                        let data = try Data(contentsOf: url)
                        handleImportedBackupData(data)
                    } catch { self.errorMessage = "Error: \(error.localizedDescription)"; self.showErrorAlert = true }
                }
            case .failure(let error): self.errorMessage = error.localizedDescription; self.showErrorAlert = true
            }
        }
        .alert(L10n.restoreAlertTitle, isPresented: $showRestoreAlert) {
            Button(L10n.cancel, role: .cancel) { }
            Button(L10n.isZh ? "安全合并" : "Safe Merge") { performRestore(mode: .merge) }
            Button(L10n.isZh ? "替换现有数据" : "Replace Current Data", role: .destructive) { exportSafetyBackupBeforeReplace() }
        } message: { Text(restorePreviewMessage) }
        .alert(L10n.isZh ? "确认替换当前数据？" : "Replace Current Data?", isPresented: $showFinalReplaceConfirmation) {
            Button(L10n.cancel, role: .cancel) { }
            Button(L10n.isZh ? "替换数据" : "Replace Data", role: .destructive) { performRestore(mode: .replace) }
        } message: {
            Text(L10n.isZh
                ? "当前数据的安全备份已保存。继续将用所选备份替换本机数据；此更改会在 iCloud 可用时同步。"
                : "Your current data safety backup was saved. Continuing replaces local data with the selected backup; this change syncs when iCloud is available.")
        }
        .alert(L10n.success, isPresented: $showSuccessAlert) { Button(L10n.ok) { } } message: { Text(successMessage) }
        .alert(L10n.isZh ? "无法开启 App Lock" : "App Lock Unavailable", isPresented: $showAppLockUnavailableAlert) {
            Button(L10n.ok, role: .cancel) { }
        } message: {
            Text(L10n.isZh
                ? "请先在此设备上设置设备密码、Face ID 或 Touch ID，然后再开启 App Lock。"
                : "Set up a device passcode, Face ID, or Touch ID before turning on App Lock.")
        }
        .alert(L10n.isZh ? "备份已保存" : "Backup Saved", isPresented: $showBackupSavedAlert) { Button(L10n.ok) { } } message: {
            Text(L10n.isZh ? "请将此 JSON 文件保存在安全的私人位置。" : "Keep this JSON file in a secure, private location.")
        }
        .alert(L10n.errorTitle, isPresented: $showErrorAlert) { Button(L10n.ok) { } } message: { Text(errorMessage) }
    }
    
    private func checkiCloudStatus() {
        // UI tests intentionally run without CloudKit entitlements and an
        // in-memory store. Constructing CKContainer in that environment traps
        // before it can report an error, so provide a deterministic test state.
        if LoveLedgerApp.isRunningAutomatedTests {
            iCloudStatusText = L10n.isZh
                ? "自动化测试中未连接 iCloud"
                : "iCloud is unavailable in UI tests"
            iCloudIconColor = .gray
            return
        }

        if isUsingLocalStoreFallback {
            iCloudStatusText = L10n.isZh
                ? "同步暂不可用；本机数据仍安全保存"
                : "Sync needs attention; local data remains saved"
            iCloudIconColor = .orange
            return
        }

        CKContainer(identifier: LoveLedgerApp.cloudKitContainerIdentifier).accountStatus { status, error in
            DispatchQueue.main.async {
                if error != nil {
                    self.iCloudStatusText = L10n.isZh
                        ? "暂时无法验证；本机数据仍安全保存"
                        : "Can’t verify now; local data remains saved"
                    self.iCloudIconColor = .gray
                    return
                }

                switch status {
                case .available:
                    self.iCloudStatusText = L10n.isZh
                        ? "iCloud 可用；联网时自动同步"
                        : "iCloud available; syncs when online"
                    self.iCloudIconColor = .blue
                case .noAccount:
                    self.iCloudStatusText = L10n.isZh ? "未登录 iCloud；本机数据仍可使用" : "Signed out; local data still works"
                    self.iCloudIconColor = .red
                case .restricted:
                    self.iCloudStatusText = L10n.isZh ? "iCloud 受限；本机数据仍可使用" : "iCloud restricted; local data still works"
                    self.iCloudIconColor = .orange
                case .temporarilyUnavailable:
                    self.iCloudStatusText = L10n.isZh ? "iCloud 暂不可用；稍后会重试同步" : "iCloud is temporarily unavailable; sync retries later"
                    self.iCloudIconColor = .orange
                case .couldNotDetermine:
                    self.iCloudStatusText = L10n.isZh ? "无法确认 iCloud 状态；请稍后刷新" : "Can’t determine iCloud status; refresh later"
                    self.iCloudIconColor = .gray
                @unknown default:
                    self.iCloudStatusText = L10n.isZh ? "iCloud 状态未知" : "iCloud status unknown"
                    self.iCloudIconColor = .gray
                }
            }
        }
    }
    
    private static let maximumBackupFileSize = 25 * 1024 * 1024

    private enum BackupFileError: LocalizedError {
        case tooLarge

        var errorDescription: String? {
            "This backup is too large to open safely."
        }
    }

    private func requestEncryptedBackup() {
        guard !isPreparingBackup else { return }
        backupExportPurpose = .standard
        isInputFocused = false
        showBackupPassphraseSheet = true
    }

    private func prepareEncryptedBackup(passphrase: String) -> String? {
        guard !isPreparingBackup else { return nil }
        isPreparingBackup = true

        do {
            let plaintext = try makeBackupData()
            jsonDocument = JSONBackupDocument(data: try SecureBackupCodec.encrypt(plaintext, passphrase: passphrase))
            backupFilename = backupFilename(
                prefix: backupExportPurpose == .standard
                    ? "DailySpend_Encrypted_Backup"
                    : "DailySpend_Before_Restore"
            )
            presentFileExporterWhenReady()
            return nil
        } catch {
            isPreparingBackup = false
            return "Backup failed: \(error.localizedDescription)"
        }
    }

    private func exportSafetyBackupBeforeReplace() {
        guard !isPreparingBackup else { return }
        backupExportPurpose = .safetyBeforeReplace
        showBackupPassphraseSheet = true
    }

    /// Present system document controllers on the following run-loop turn. This
    /// keeps SwiftUI from presenting a picker while the Form is also processing
    /// the originating touch/focus update, which can otherwise yield a blank
    /// first presentation on newer iOS releases.
    private func presentFileExporterWhenReady() {
        Task { @MainActor in
            // Allow the passphrase sheet to finish dismissing before the Files
            // exporter presents. Without this handoff, iOS can reject the
            // second presentation on compact devices.
            try? await Task.sleep(nanoseconds: 200_000_000)
            showFileExporter = true
            isPreparingBackup = false
        }
    }

    private func presentFileImporter() {
        guard !isPreparingRestore else { return }
        isPreparingRestore = true
        isInputFocused = false

        Task { @MainActor in
            await Task.yield()
            showFileImporter = true
            isPreparingRestore = false
        }
    }

    private func handleBackupExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            switch backupExportPurpose {
            case .standard:
                showBackupSavedAlert = true
            case .safetyBeforeReplace:
                showFinalReplaceConfirmation = true
            }
        case .failure(let error):
            if backupExportPurpose == .safetyBeforeReplace {
                errorMessage = L10n.isZh
                    ? "未保存安全备份，已取消替换。请重新导入备份后再试。"
                    : "Safety backup wasn’t saved, so replacement was cancelled. Re-import the backup to try again."
            } else {
                errorMessage = "Backup failed: \(error.localizedDescription)"
            }
            showErrorAlert = true
        }
    }

    private func makeBackupData() throws -> Data {
        let fetchDescriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let expenses = try modelContext.fetch(fetchDescriptor)
        let budgets = try modelContext.fetch(FetchDescriptor<CategoryBudget>())
        let items = expenses.map {
            ExpenseBackupItem(
                id: $0.id,
                amount: $0.normalizedAmount,
                amountMinorUnits: $0.money.minorUnits,
                category: $0.category,
                note: $0.note,
                date: $0.date,
                frequency: $0.safeFrequency,
                lastProcessedDate: $0.lastProcessedDate,
                isRecurringChild: $0.isRecurringChild
            )
        }
        let backup = AppBackup(
            expenses: items,
            categoryBudgets: budgets.map {
                CategoryBudgetBackupItem(
                    category: $0.category,
                    amount: $0.normalizedAmount,
                    amountMinorUnits: $0.money.minorUnits
                )
            },
            settings: BackupSettings(
                isBudgetEnabled: isBudgetEnabled,
                budgetAmount: budgetAmount,
                alertThreshold: alertThreshold,
                dailyNotify: dailyNotify,
                notifyTime: notifyTime
            )
        )
        let encoder = JSONEncoder()
        // V2 uses an absolute ISO 8601 timestamp so changing time zones
        // between export and restore cannot move an expense to another day.
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(backup)
    }

    private func backupFilename(prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return "\(prefix)_\(formatter.string(from: Date()))"
    }

    private func handleImportedBackupData(_ data: Data) {
        if SecureBackupCodec.isEncryptedBackup(data) {
            pendingEncryptedBackupData = data
            showRestorePassphraseSheet = true
        } else {
            importDecryptedBackupData(data)
        }
    }

    private func unlockImportedBackup(with passphrase: String) -> String? {
        guard let pendingEncryptedBackupData else {
            return L10n.isZh ? "未找到加密备份，请重新选择文件。" : "No encrypted backup was selected. Choose the file again."
        }

        do {
            let data = try SecureBackupCodec.decrypt(pendingEncryptedBackupData, passphrase: passphrase)
            self.pendingEncryptedBackupData = nil
            importDecryptedBackupData(data)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func importDecryptedBackupData(_ data: Data) {
        do {
            let imported = try decodeBackup(from: data)
            importedBackup = imported
            showRestoreAlert = true
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func decodeBackup(from data: Data) throws -> ImportedBackup {
        let modernDecoder = JSONDecoder()
        modernDecoder.dateDecodingStrategy = .iso8601

        if let backup = try? modernDecoder.decode(AppBackup.self, from: data) {
            guard backup.formatVersion <= AppBackup.currentFormatVersion else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return ImportedBackup(backup: backup, isLegacy: false)
        }

        let formattedDecoder = JSONDecoder()
        formattedDecoder.dateDecodingStrategy = .formatted(backupDateFormatter)

        // Retain compatibility with development exports created before V2's
        // ISO 8601 format as well as the original array-only format.
        if let backup = try? formattedDecoder.decode(AppBackup.self, from: data) {
            guard backup.formatVersion <= AppBackup.currentFormatVersion else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return ImportedBackup(backup: backup, isLegacy: false)
        }

        if let items = try? formattedDecoder.decode([ExpenseBackupItem].self, from: data) {
            return legacyImportedBackup(items)
        }

        let secondsDecoder = JSONDecoder()
        secondsDecoder.dateDecodingStrategy = .secondsSince1970
        if let items = try? secondsDecoder.decode([ExpenseBackupItem].self, from: data) {
            return legacyImportedBackup(items)
        }

        throw CocoaError(.fileReadCorruptFile)
    }

    private func legacyImportedBackup(_ items: [ExpenseBackupItem]) -> ImportedBackup {
        return ImportedBackup(
            backup: BackupMigration.upgradeLegacyExpenses(items),
            isLegacy: true
        )
    }

    private func performRestore(mode: BackupRestoreMode) {
        guard let importedBackup else { return }

        do {
            if let settings = try BackupRestorer.apply(importedBackup, mode: mode, in: modelContext) {
                isBudgetEnabled = settings.isBudgetEnabled
                budgetAmount = settings.budgetAmount
                alertThreshold = settings.alertThreshold
                dailyNotify = settings.dailyNotify
                notifyTime = settings.notifyTime
            }

            self.importedBackup = nil
            successMessage = mode == .merge
                ? (L10n.isZh ? "已安全合并缺失数据；当前数据和设置保持不变。" : "Missing data was safely merged; current data and settings were preserved.")
                : L10n.restoreSuccess
            showSuccessAlert = true
        } catch {
            modelContext.rollback()
            errorMessage = "Restore failed: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}

private struct BackupPassphraseSheet: View {
    let title: String
    let message: String
    let requiresConfirmation: Bool
    let onSubmit: (String) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    private var isReady: Bool {
        if requiresConfirmation {
            return passphrase.count >= 12 && passphrase == confirmation
        }
        return !passphrase.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(
                        requiresConfirmation ? "Passphrase" : "Backup passphrase",
                        text: $passphrase
                    )
                    .textContentType(requiresConfirmation ? .newPassword : .password)

                    if requiresConfirmation {
                        SecureField("Confirm passphrase", text: $confirmation)
                            .textContentType(.newPassword)
                    }
                } footer: {
                    Text(message)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(requiresConfirmation ? "Encrypt" : "Unlock") {
                        if let error = onSubmit(passphrase) {
                            errorMessage = error
                        } else {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isReady)
                }
            }
        }
    }
}

// MARK: - ✨ About View (Corrected Info & Auto Build)
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivacyPolicy = false
    
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
                        
                        Text("Private by Design")
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
                    
                    // 4. Production support channel
                    Button(action: {
                        if let url = URL(string: "mailto:jacksonfeng0130@yahoo.com?subject=DailySpend%20Support") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "envelope.fill")
                            Text(L10n.isZh ? "联系支持" : "Contact Support")
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

                    Button {
                        showPrivacyPolicy = true
                    } label: {
                        Label(L10n.isZh ? "隐私政策" : "Privacy Policy", systemImage: "hand.raised.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    
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
            .sheet(isPresented: $showPrivacyPolicy) {
                InAppPrivacyPolicyView()
            }
        }
    }
}

private struct InAppPrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Effective August 25, 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("DailySpend is free, has no ads, subscriptions, in-app purchases, third-party analytics, or tracking.")
                }

                Section("Your data") {
                    Text("DailySpend stores the spending records, budgets, notes, recurring entries, and split-bill details that you enter to provide its features.")
                    Text("Your data stays in protected app storage and, when available, your private iCloud database. The developer cannot access your private expense history.")
                    Text("You can turn on App Lock to require device authentication whenever DailySpend is reopened. DailySpend also hides financial records in the app switcher.")
                }

                Section("Receipt scanning and backups") {
                    Text("Receipt scanning uses your camera and on-device text recognition to suggest a total. DailySpend does not retain receipt images or send them to the developer.")
                    Text("Current backup exports are encrypted with a passphrase you choose. DailySpend does not store that passphrase and cannot recover it.")
                }

                Section("Widgets and notifications") {
                    Text("Widgets use app-shared storage to show spending and budget information where you choose to place them. Optional reminders are scheduled locally on your device.")
                }

                Section("Your choices") {
                    Text("You can delete expenses and category budgets in DailySpend at any time. If you use iCloud, those deletions sync when iCloud is available. Deleting DailySpend removes its local data from that device.")
                    Text("Camera and notification access are optional and can be changed in the iOS Settings app. DailySpend does not operate user accounts or hold a server-side copy of your personal expense history.")
                }

                Section("Contact") {
                    Link("jacksonfeng0130@yahoo.com", destination: URL(string: "mailto:jacksonfeng0130@yahoo.com?subject=DailySpend%20Privacy")!)
                }
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    KeyboardDismissButton {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
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
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    
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
        .alert(L10n.errorTitle, isPresented: $showSaveError) {
            Button(L10n.ok, role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
    
    private func loadBudget() {
        let name = category.name
        let fetchDescriptor = FetchDescriptor<CategoryBudget>(predicate: #Predicate { $0.category == name })
        if let record = try? modelContext.fetch(fetchDescriptor).first {
            if record.normalizedAmount > 0 { amountText = String(format: "%.0f", record.normalizedAmount) }
        }
    }
    
    private func saveBudget() {
        let cleanText = amountText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldRemoveBudget = cleanText.isEmpty || cleanText == "0"
        let amount = Double(cleanText)

        if !shouldRemoveBudget {
            guard let amount, ExpenseInputValidator.isValidLineItemAmount(amount) else {
                saveErrorMessage = L10n.isZh ? "请输入有效且大于 0 的预算金额。" : "Enter a valid budget amount greater than zero."
                showSaveError = true
                return
            }
        }

        let targetCategoryName = category.name
        let fetchDescriptor = FetchDescriptor<CategoryBudget>(predicate: #Predicate { $0.category == targetCategoryName })
        do {
            let results = try modelContext.fetch(fetchDescriptor)
            let currentRecord = results.first
            var didChange = false
            if let record = currentRecord {
                if shouldRemoveBudget { modelContext.delete(record); didChange = true }
                else if let amount, record.normalizedAmount != Money(amount).amount {
                    record.setAmount(amount)
                    didChange = true
                }
            } else if let amount, !shouldRemoveBudget {
                let newBudget = CategoryBudget(category: targetCategoryName, amount: amount)
                modelContext.insert(newBudget); didChange = true
            }
            if didChange { try modelContext.save() }
        } catch {
            modelContext.rollback()
            saveErrorMessage = L10n.isZh ? "分类预算未保存：\(error.localizedDescription)" : "Category budget wasn't saved: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}
