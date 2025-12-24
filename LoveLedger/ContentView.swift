import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Main Content View (Entry Point)
struct ContentView: View {
    // 这里保留 Query 用于后台同步逻辑
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    
    // AppStorage Settings
    @AppStorage("isBudgetEnabled") private var isBudgetEnabled = false
    @AppStorage("budgetAmount") private var budgetAmount = 0.0
    @AppStorage("dailyNotify") private var dailyNotify = false
    @AppStorage("notifyTime") private var notifyTime: Double = 0
    
    @State private var syncTask: Task<Void, Never>? = nil
    
    let themeColor = Color(red: 0.0, green: 0.78, blue: 0.70)
    let backgroundColor = Color(uiColor: .systemGroupedBackground)
    
    var body: some View {
        TabView {
            HomeView(themeColor: themeColor)
                .tabItem { Label(L10n.home, systemImage: "house.fill") }
            
            NavigationStack {
                ZStack {
                    backgroundColor.ignoresSafeArea()
                    InsightsView(themeColor: themeColor)
                }
            }
            .tabItem { Label(L10n.insights, systemImage: "chart.pie.fill") }
            
            NavigationStack {
                ZStack {
                    backgroundColor.ignoresSafeArea()
                    SettingsView(themeColor: themeColor)
                }
            }
            .tabItem { Label(L10n.settings, systemImage: "gearshape.fill") }
        }
        .tint(themeColor)
        .onAppear {
            NotificationManager.shared.requestPermission()
            performDebouncedSync()
        }
        // 同步逻辑
        .onChange(of: expenses) { _, _ in performDebouncedSync() }
        .onChange(of: budgetAmount) { _, _ in performDebouncedSync() }
        .onChange(of: isBudgetEnabled) { _, _ in performDebouncedSync() }
        .onChange(of: notifyTime) { _, _ in updateNotifications() }
        .onChange(of: dailyNotify) { _, _ in updateNotifications() }
    }
    
    // MARK: - Sync Logic
    var currentMonthTotal: Double {
        let calendar = Calendar.current
        let now = Date()
        return expenses
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
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
            NotificationManager.shared.scheduleDailyNotification(remaining: remaining, time: notifyDate, isEnabled: dailyNotify)
        }
    }
}
