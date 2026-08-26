import SwiftUI
import SwiftData
import UserNotifications
import LocalAuthentication

// MARK: - Main Content View (Entry Point)
struct ContentView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    
    // AppStorage Settings
    @AppStorage("isBudgetEnabled") private var isBudgetEnabled = false
    @AppStorage("budgetAmount") private var budgetAmount = 0.0
    @AppStorage("alertThreshold") private var alertThreshold = 100.0
    @AppStorage("dailyNotify") private var dailyNotify = false
    @AppStorage("notifyTime") private var notifyTime: Double = 0
    @AppStorage("isAppLockEnabled") private var isAppLockEnabled = false
    
    // Tab 选中状态管理
    @State private var selectedTab = 0
    @State private var syncTask: Task<Void, Never>? = nil
    @State private var isLocked = true
    @State private var isAuthenticating = false
    @State private var unlockErrorMessage: String?
    @State private var canDisableAppLock = false
    @Environment(\.scenePhase) private var scenePhase
    
    let themeColor = Color(red: 0.0, green: 0.78, blue: 0.70)
    let backgroundColor = Color(uiColor: .systemGroupedBackground)
    
    var body: some View {
        // 绑定 selection
        TabView(selection: $selectedTab) {
            // 1. 首页
            HomeView(themeColor: themeColor, onOpenSplitBill: {
                withAnimation(.snappy) { selectedTab = 1 }
            })
                .tabItem { Label(L10n.home, systemImage: "house.fill") }
                .tag(0)
            
            // SplitBillView owns its navigation stack. Keeping one stack avoids
            // nested-navigation behaviour when opening sheets or sharing.
            SplitBillView(themeColor: themeColor, goHome: {
                withAnimation(.snappy) { selectedTab = 0 }
            })
            .tabItem {
                Label(L10n.isZh ? "分账" : "Split Bill", systemImage: "person.2.fill")
            }
            .tag(1)
            
            // 3. 统计
            NavigationStack {
                ZStack {
                    backgroundColor.ignoresSafeArea()
                    InsightsView(themeColor: themeColor)
                }
            }
            .tabItem { Label(L10n.insights, systemImage: "chart.pie.fill") }
            .tag(2)
            
            // 4. 设置
            NavigationStack {
                ZStack {
                    backgroundColor.ignoresSafeArea()
                    SettingsView(themeColor: themeColor)
                }
            }
            .tabItem { Label(L10n.settings, systemImage: "gearshape.fill") }
            .tag(3)
        }
        .tint(themeColor)
        // A visual shield alone is not enough: keep VoiceOver from reaching
        // financial values behind App Lock as well.
        .accessibilityHidden(isAppLockEnabled && isLocked)
        // Never leave transaction content visible in the app switcher. If a
        // person chooses App Lock, require their device authentication again
        // whenever DailySpend becomes active.
        .overlay {
            if scenePhase != .active {
                PrivacyShieldView()
            } else if isAppLockEnabled && isLocked {
                AppLockView(
                    themeColor: themeColor,
                    isAuthenticating: isAuthenticating,
                    errorMessage: unlockErrorMessage,
                    canDisableAppLock: canDisableAppLock,
                    unlock: unlockIfNeeded,
                    disableAppLock: disableAppLock
                )
            }
        }
        .onAppear {
            performDebouncedSync()
            updateNotifications()
            unlockIfNeeded()
        }
        .onChange(of: expenses) { _, _ in
            performDebouncedSync()
            updateNotifications()
        }
        .onChange(of: budgetAmount) { _, _ in
            performDebouncedSync()
            updateNotifications()
        }
        .onChange(of: isBudgetEnabled) { _, _ in
            performDebouncedSync()
            updateNotifications()
        }
        .onChange(of: alertThreshold) { _, _ in updateNotifications() }
        .onChange(of: notifyTime) { _, _ in updateNotifications() }
        .onChange(of: dailyNotify) { _, _ in updateNotifications() }
        .onChange(of: isAppLockEnabled) { _, isEnabled in
            isLocked = isEnabled
            unlockErrorMessage = nil
            canDisableAppLock = false
            if isEnabled { unlockIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                unlockIfNeeded()
            } else if isAppLockEnabled {
                isLocked = true
            }
        }
    }
    
    var currentMonthTotal: Double {
        let calendar = Calendar.current
        let now = Date()
        return expenses
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.normalizedAmount }
    }
    
    private func performDebouncedSync() {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            WidgetDataService.saveToWidget(expenses: expenses, budget: budgetAmount, isBudgetEnabled: isBudgetEnabled)
        }
    }
    
    private func updateNotifications() {
        if isBudgetEnabled && notifyTime != 0 {
            let remaining = budgetAmount - currentMonthTotal
            let notifyDate = Date(timeIntervalSince1970: notifyTime)
            NotificationManager.shared.scheduleDailyNotification(
                remaining: remaining,
                alertThreshold: alertThreshold,
                time: notifyDate,
                isEnabled: dailyNotify
            )
        } else {
            NotificationManager.shared.cancelDailyNotification()
        }
    }

    private func unlockIfNeeded() {
        guard isAppLockEnabled, isLocked, !isAuthenticating else { return }

        isAuthenticating = true
        unlockErrorMessage = nil
        let context = LAContext()
        var availabilityError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            isAuthenticating = false
            canDisableAppLock = true
            unlockErrorMessage = L10n.isZh
                ? "此设备未配置可用的设备认证。"
                : "Device authentication is not available on this device."
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: L10n.isZh
                ? "解锁 DailySpend 中的财务记录"
                : "Unlock your DailySpend financial records"
        ) { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    isLocked = false
                    canDisableAppLock = false
                } else {
                    unlockErrorMessage = error?.localizedDescription ?? (L10n.isZh
                        ? "无法验证身份，请重试。"
                        : "Couldn’t verify your identity. Try again.")
                }
            }
        }
    }

    private func disableAppLock() {
        isAppLockEnabled = false
        isLocked = false
        unlockErrorMessage = nil
        canDisableAppLock = false
    }
}

private struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.title2)
                Text("DailySpend")
                    .font(.headline)
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}

private struct AppLockView: View {
    let themeColor: Color
    let isAuthenticating: Bool
    let errorMessage: String?
    let canDisableAppLock: Bool
    let unlock: () -> Void
    let disableAppLock: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(themeColor)
                Text(L10n.isZh ? "DailySpend 已锁定" : "DailySpend is Locked")
                    .font(.title2.bold())
                Text(L10n.isZh
                     ? "使用设备认证查看您的财务记录。"
                     : "Use device authentication to view your financial records.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 28)
                }
                Button(action: unlock) {
                    if isAuthenticating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label(L10n.isZh ? "解锁" : "Unlock", systemImage: "faceid")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(themeColor)
                .disabled(isAuthenticating)
                .accessibilityHint(L10n.isZh ? "使用 Face ID、Touch ID 或设备密码解锁" : "Uses Face ID, Touch ID, or your device passcode")
                if canDisableAppLock {
                    Button(L10n.isZh ? "关闭 App Lock" : "Turn Off App Lock", role: .destructive, action: disableAppLock)
                        .font(.footnote)
                }
            }
        }
    }
}
