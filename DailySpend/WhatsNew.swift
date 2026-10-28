import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - When the tour shows

/// The one-time tour of what 2.0 added. Whether it was seen lives in
/// preferences, never in the expense store.
enum WhatsNew {
    /// The tour's own version. Bump it only for a release with a new tour, so
    /// bug-fix updates don't show this one again.
    static let version = "2.0"
    static let seenKey = "whatsNewSeenVersion"
    static let earlierUseKey = "whatsNewHadEarlierUse"
    /// Shows the tour in UI tests and debug runs, even after it was seen.
    static let showArgument = "-show-whats-new"

    /// Preferences an earlier DailySpend wrote. 1.0 writes the first one at
    /// every launch, so any of them means this iPhone used DailySpend before.
    static let earlierUseKeys = [
        DailySpendApp.cloudKitStoreFallbackKey, "isBudgetEnabled", "budgetAmount", "alertThreshold",
        "dailyNotify", "notifyTime", "isAppLockEnabled", "showScanTip"
    ]

    enum Kind: Equatable {
        /// Updated from 1.0: starts by offering a backup.
        case upgrade(expenseCount: Int)
        /// A new install: starts with a welcome.
        case welcome
        /// Opened again from Settings: the new features only.
        case replay
    }

    enum Page: Hashable {
        case backup, welcome, scan, split, quickAdd, siri, insights
    }

    static func pages(for kind: Kind) -> [Page] {
        let features: [Page] = [.scan, .split, .quickAdd, .siri, .insights]
        switch kind {
        case .upgrade: return [.backup] + features
        case .welcome: return [.welcome] + features
        case .replay: return features
        }
    }

    /// Notes whether DailySpend was used on this iPhone before. Call it before
    /// this launch writes any preference of its own.
    static func recordEarlierUse(
        defaults: UserDefaults = .standard,
        widgetDefaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroup)
    ) {
        guard defaults.string(forKey: seenKey) == nil, defaults.object(forKey: earlierUseKey) == nil else { return }
        let usedBefore = earlierUseKeys.contains { defaults.object(forKey: $0) != nil }
            || widgetDefaults?.object(forKey: WidgetSnapshot.storageKey) != nil
        defaults.set(usedBefore, forKey: earlierUseKey)
    }

    static func needsTour(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isTesting: Bool = DailySpendApp.isRunningAutomatedTests
    ) -> Bool {
        if arguments.contains(showArgument) { return true }
        return !isTesting && defaults.string(forKey: seenKey) != version
    }

    /// Records on this iPhone count as an upgrade even when the preferences
    /// were never written, for example by someone who never opened Settings.
    static func kind(expenseCount: Int, defaults: UserDefaults = .standard) -> Kind {
        expenseCount > 0 || defaults.bool(forKey: earlierUseKey) ? .upgrade(expenseCount: expenseCount) : .welcome
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: seenKey)
        defaults.removeObject(forKey: earlierUseKey)
    }
}

// MARK: - The tour

struct WhatsNewTour: View {
    let kind: WhatsNew.Kind
    let themeColor: Color
    let onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @AppStorage("isBudgetEnabled") private var isBudgetEnabled = false
    @AppStorage("budgetAmount") private var budgetAmount = 0.0
    @AppStorage("alertThreshold") private var alertThreshold = 100.0
    @AppStorage("dailyNotify") private var dailyNotify = false
    @AppStorage("notifyTime") private var notifyTime: Double = 0

    @State private var index = 0
    @State private var backup = BackupProgress.notStarted
    @State private var showPassphrase = false
    @State private var showExporter = false
    @State private var backupDocument: JSONBackupDocument?
    @State private var backupFilename = "DailySpend_Encrypted_Backup"

    private var pages: [WhatsNew.Page] { WhatsNew.pages(for: kind) }
    private var page: WhatsNew.Page { pages[min(index, pages.count - 1)] }
    private var isLast: Bool { index >= pages.count - 1 }
    private var offersBackup: Bool { page == .backup && backup != .saved }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(L10n.isZh ? "跳过" : "Skip", action: onFinish)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .opacity(isLast ? 0 : 1)
                    .disabled(isLast)
                    .accessibilityIdentifier("whats-new-skip")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(minHeight: 44)

            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element) { offset, page in
                    TourPageView(
                        page: page,
                        kind: kind,
                        isActive: offset == index,
                        isLast: offset == pages.count - 1,
                        themeColor: themeColor,
                        backup: backup
                    )
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 14) {
                PageDots(count: pages.count, index: index, themeColor: themeColor)

                if offersBackup {
                    Button { showPassphrase = true } label: {
                        Label(L10n.isZh ? "立即备份" : "Back Up Now", systemImage: "lock.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .tourPrimaryButton(themeColor)
                    .accessibilityIdentifier("whats-new-back-up")
                } else {
                    Button(action: advance) {
                        Text(primaryTitle).frame(maxWidth: .infinity)
                    }
                    .tourPrimaryButton(themeColor)
                    .accessibilityIdentifier("whats-new-continue")
                }

                // Always laid out, so the pages above keep the same height.
                Button(L10n.isZh ? "以后再说" : "Not Now", action: advance)
                    .fontWeight(.medium)
                    .foregroundStyle(themeColor)
                    .opacity(offersBackup ? 1 : 0)
                    .disabled(!offersBackup)
                    .accessibilityHidden(!offersBackup)
                    .accessibilityIdentifier("whats-new-not-now")
            }
            // Phone-width buttons on iPad and the open iPhone Duo too.
            .frame(maxWidth: 480)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .interactiveDismissDisabled()
        // Keep each control's own identifier; the tour only groups them.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whats-new")
        .sheet(isPresented: $showPassphrase) {
            BackupPassphraseSheet(
                title: L10n.isZh ? "加密备份" : "Encrypt Backup",
                message: L10n.isZh
                    ? "创建一个至少 12 个字符的密码。DailySpend 无法保存或找回这个密码。"
                    : "Create a passphrase with at least 12 characters. DailySpend never stores or recovers it.",
                requiresConfirmation: true,
                onSubmit: prepareBackup
            )
        }
        .fileExporter(
            isPresented: $showExporter,
            document: backupDocument,
            contentType: .json,
            defaultFilename: backupFilename
        ) { result in
            switch result {
            case .success:
                withAnimation(.smooth) { backup = .saved }
            case .failure(let error):
                // Closing Files without saving is a choice, not a failure.
                if (error as? CocoaError)?.code != .userCancelled {
                    backup = .failed(error.localizedDescription)
                }
            }
        }
    }

    private var primaryTitle: String {
        if !isLast { return L10n.isZh ? "继续" : "Continue" }
        if kind == .replay { return L10n.isZh ? "完成" : "Done" }
        return L10n.isZh ? "开始使用" : "Get Started"
    }

    private func advance() {
        if isLast {
            onFinish()
        } else {
            withAnimation(.smooth) { index += 1 }
        }
    }

    /// The same encrypted file Settings saves.
    private func prepareBackup(_ passphrase: String) -> String? {
        do {
            let data = try AppBackup.data(
                from: modelContext,
                settings: BackupSettings(
                    isBudgetEnabled: isBudgetEnabled,
                    budgetAmount: budgetAmount,
                    alertThreshold: alertThreshold,
                    dailyNotify: dailyNotify,
                    notifyTime: notifyTime
                )
            )
            backupDocument = JSONBackupDocument(data: try SecureBackupCodec.encrypt(data, passphrase: passphrase))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd_HHmm"
            backupFilename = "DailySpend_Encrypted_Backup_\(formatter.string(from: Date()))"
            Task { @MainActor in
                // Let the passphrase sheet finish closing before Files opens.
                try? await Task.sleep(for: .milliseconds(350))
                showExporter = true
            }
            return nil
        } catch {
            return "Backup failed: \(error.localizedDescription)"
        }
    }
}

enum BackupProgress: Equatable {
    case notStarted
    case saved
    case failed(String)
}

private extension View {
    func tourPrimaryButton(_ themeColor: Color) -> some View {
        self
            .fontWeight(.semibold)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(themeColor)
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int
    let themeColor: Color

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { dot in
                Capsule()
                    .fill(dot == index ? themeColor : Color.secondary.opacity(0.3))
                    .frame(width: dot == index ? 20 : 7, height: 7)
            }
        }
        .animation(.smooth, value: index)
        .accessibilityElement()
        .accessibilityLabel(L10n.isZh ? "第 \(index + 1) 页，共 \(count) 页" : "Page \(index + 1) of \(count)")
    }
}

// MARK: - Pages

private struct TourPageView: View {
    let page: WhatsNew.Page
    let kind: WhatsNew.Kind
    let isActive: Bool
    let isLast: Bool
    let themeColor: Color
    let backup: BackupProgress

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Centered when it fits. Short screens, such as an iPhone on its
        // side or the open iPhone Duo, get a smaller picture first, and the
        // page scrolls only when even that doesn't fit.
        ViewThatFits(in: .vertical) {
            content(pictureScale: 1)
            content(pictureScale: 0.64)
            ScrollView { content(pictureScale: 0.64) }
                .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func content(pictureScale: CGFloat) -> some View {
        VStack(spacing: 26 * pictureScale) {
            // The pictures are decorative; at the largest text sizes the
            // words need the room.
            if !typeSize.isAccessibilitySize {
                illustration
                    .frame(maxWidth: 360)
                    .frame(height: 300)
                    .scaleEffect(pictureScale)
                    .frame(height: 300 * pictureScale)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 10) {
                if showsNewBadge {
                    Text(L10n.isZh ? "2.0 新功能" : "NEW IN 2.0")
                        .font(.caption.weight(.bold))
                        .tracking(L10n.isZh ? 0 : 0.6)
                        .foregroundStyle(themeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(themeColor.opacity(0.14), in: .capsule)
                }
                Text(copy.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("whats-new-title")
                Text(copy.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = copy.note {
                    Label(note.text, systemImage: note.symbol)
                        .font(.footnote)
                        .foregroundStyle(note.isWarning ? Color.orange : Color.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .accessibilityIdentifier("whats-new-note")
                }
            }
            .frame(maxWidth: 440)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var showsNewBadge: Bool {
        kind != .welcome && page != .backup
    }

    @ViewBuilder
    private var illustration: some View {
        switch page {
        case .backup:
            BackupScene(count: expenseCount, isSaved: backup == .saved, isActive: isActive, themeColor: themeColor)
        case .welcome:
            WelcomeScene(isActive: isActive, themeColor: themeColor)
        case .scan:
            ScanScene(isActive: isActive, themeColor: themeColor)
        case .split:
            SplitScene(isActive: isActive, themeColor: themeColor)
        case .quickAdd:
            QuickAddScene(isActive: isActive, themeColor: themeColor)
        case .siri:
            SiriScene(isActive: isActive, themeColor: themeColor)
        case .insights:
            InsightsScene(isActive: isActive, themeColor: themeColor)
        }
    }

    private var expenseCount: Int {
        if case .upgrade(let count) = kind { return count }
        return 0
    }

    private struct Note {
        var text: String
        var symbol: String
        var isWarning = false
    }

    private var copy: (title: String, message: String, note: Note?) {
        let zh = L10n.isZh
        let canReadItems = ReceiptIntelligenceStatus.current.canReadItems
        let seeAgain = Note(
            text: zh ? "以后可在“设置”中再次查看。" : "You can see this again in Settings.",
            symbol: "gearshape"
        )

        switch page {
        case .backup:
            switch backup {
            case .saved:
                return (
                    zh ? "备份已保存" : "Backup saved",
                    zh ? "请把这个文件和密码分开妥善保管。以后恢复数据时需要用到它们。"
                       : "Keep the file and its passphrase somewhere safe, apart from each other. You'll need both to restore.",
                    nil
                )
            case .failed(let reason):
                return (
                    backupTitle,
                    backupMessage,
                    Note(text: (zh ? "备份没有保存：" : "The backup wasn’t saved: ") + reason,
                         symbol: "exclamationmark.triangle.fill", isWarning: true)
                )
            case .notStarted:
                return (backupTitle, backupMessage, nil)
            }
        case .welcome:
            return (
                zh ? "让日常花费更清晰" : "Spending, made clear",
                zh ? "记录花费、和朋友分账、看清钱花在了哪里。花一分钟看看 DailySpend 能做什么。"
                   : "Track what you spend, split bills with friends, and see where your money goes. Here's a one‑minute look at what DailySpend can do.",
                nil
            )
        case .scan:
            return (
                zh ? "扫描收据，自动填写" : "Scan a receipt",
                zh ? "点首页 + 旁边的扫描按钮。DailySpend 会填好金额、商家、日期和分类，保存前由你确认。"
                   : "Tap the scan button on Home, next to +. DailySpend fills in the amount, store, date, and category, and you check it before saving.",
                Note(
                    text: zh ? "收据只在这台 iPhone 上读取，图片不会被保存或上传。"
                             : "Receipts are read on this iPhone. Images are never saved or sent.",
                    symbol: "lock.shield"
                )
            )
        case .split:
            return (
                zh ? "用收据直接分账" : "Split a bill from the receipt",
                zh ? "在“分账”里扫描收据：快速分账会填好总额和小费；按项分账可以点选每一项由谁分摊，税和小费自动分好。"
                   : "In Split Bill, scan into Quick Split for the total and tip, or By Item and tap who shared each line. Tax and tip are shared out for you.",
                canReadItems ? nil : Note(
                    text: zh ? "这台设备可以读取总额；按项扫描需要开启 Apple 智能。"
                             : "This device reads the total. Scanning each item needs Apple Intelligence.",
                    symbol: "sparkles"
                )
            )
        case .quickAdd:
            return (
                zh ? "一句话记账" : "Add in plain words",
                zh ? "点 +，在“快速记账”里像说话一样输入，比如“和 Alex 吃午饭 25”或“昨天打车 23 块”。金额、分类和日期会自动识别。"
                   : "Tap + and type it the way you'd say it in Quick Add, like “Lunch with Alex 25” or “Uber 18 yesterday”. The amount, category, and date are picked out for you.",
                nil
            )
        case .siri:
            return (
                zh ? "Siri、快捷指令和控制中心" : "Siri, Shortcuts, and Controls",
                zh ? "对 Siri 说“在DailySpend里记一笔”或“用DailySpend扫描收据”。还可以把 DailySpend 按钮加到控制中心、锁定屏幕或操作按钮。"
                   : "Say “Log an expense in DailySpend” or “Scan a receipt with DailySpend”. You can also add DailySpend to Control Center, the Lock Screen, or the Action button.",
                nil
            )
        case .insights:
            return (
                zh ? "一眼看清本月花费" : "Your month at a glance",
                zh ? "统计页顶部新增速览：本月与上月同期相比多花还是少花，以及变化最大的分类。点“详情”查看完整说明。"
                   : "Insights now opens with a quick look: how this month compares with the same days last month, and what changed most. Tap Details for the full picture.",
                isLast && kind != .replay ? seeAgain : nil
            )
        }
    }

    private var backupTitle: String {
        let count = expenseCount
        if L10n.isZh {
            return count > 0 ? "你的 \(count) 笔账单都在" : "欢迎使用 DailySpend 2.0"
        }
        switch count {
        case 0: return "Welcome to DailySpend 2.0"
        case 1: return "Your expense is all here"
        default: return "Your \(count) expenses are all here"
        }
    }

    private var backupMessage: String {
        L10n.isZh
            ? "开始体验新功能前，建议先把加密备份保存到“文件”App，在 App 之外多留一份完整副本。"
            : "Before you try what's new, save an encrypted backup to Files. It keeps a full copy of your records outside the app."
    }
}

// MARK: - Illustrations

/// Steps a scene through its frames while its page is showing, and shows the
/// finished frame otherwise or when Reduce Motion is on.
private struct Stepped<Content: View>: View {
    let steps: Int
    var interval: Duration = .seconds(1.1)
    let isActive: Bool
    @ViewBuilder let content: (Int) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Int?

    var body: some View {
        content(step ?? steps - 1)
            .task(id: isActive) {
                guard isActive, !reduceMotion else {
                    step = steps - 1
                    return
                }
                step = 0
                while !Task.isCancelled {
                    // The finished frame holds a little longer before starting over.
                    let current = step ?? 0
                    try? await Task.sleep(for: current == steps - 1 ? interval * 2.2 : interval)
                    if Task.isCancelled { break }
                    withAnimation(.spring(duration: 0.55, bounce: 0.18)) {
                        step = (current + 1) % steps
                    }
                }
            }
    }
}

private struct Stage<Content: View>: View {
    let themeColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(LinearGradient(
                    colors: [themeColor.opacity(0.22), themeColor.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            content.padding(22)
        }
    }
}

private extension View {
    func miniCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

private func sampleMoney(_ value: Double, wholeUnits: Bool = false) -> String {
    let style = FloatingPointFormatStyle<Double>.Currency(code: L10n.currencyCode)
    return wholeUnits ? value.formatted(style.precision(.fractionLength(0))) : value.formatted(style)
}

private struct CategoryBubble: View {
    let category: String
    var size: CGFloat = 36

    var body: some View {
        let style = Expense.categories.first { $0.name == category }
        ZStack {
            Circle().fill((style?.color ?? .gray).opacity(0.16))
            Image(systemName: style?.icon ?? "creditcard.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(style?.color ?? .gray)
        }
        .frame(width: size, height: size)
    }
}

private struct BackupScene: View {
    let count: Int
    let isSaved: Bool
    let isActive: Bool
    let themeColor: Color

    var body: some View {
        Stage(themeColor: themeColor) {
            Stepped(steps: 3, isActive: isActive && !isSaved) { step in
                let done = isSaved || step == 2
                VStack(spacing: 22) {
                    HStack(spacing: 0) {
                        tile(symbol: "iphone", tint: themeColor,
                             value: count > 0 ? "\(count)" : "DailySpend",
                             caption: count > 0 ? (L10n.isZh ? "笔账单" : (count == 1 ? "expense" : "expenses")) : nil)
                        ZStack {
                            Capsule()
                                .fill(themeColor.opacity(0.25))
                                .frame(height: 3)
                            Image(systemName: "lock.doc.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(themeColor)
                                .offset(x: step == 0 && !isSaved ? -26 : 26)
                                .opacity(done ? 0 : 1)
                        }
                        .frame(width: 84)
                        tile(symbol: "folder.fill", tint: .blue,
                             value: L10n.isZh ? "文件" : "Files", caption: nil)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(.white, .green)
                                    .offset(x: 8, y: -8)
                                    .scaleEffect(done ? 1 : 0.2)
                                    .opacity(done ? 1 : 0)
                            }
                    }
                    HStack(spacing: 8) {
                        chip(L10n.isZh ? "账单和预算" : "Expenses & budgets", symbol: "list.bullet")
                        chip(L10n.isZh ? "已加密" : "Encrypted", symbol: "lock.fill")
                    }
                }
            }
        }
    }

    private func tile(symbol: String, tint: Color, value: String, caption: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 104, height: 124)
        .miniCard(cornerRadius: 20)
    }

    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .miniCard(cornerRadius: 12)
    }
}

private struct WelcomeScene: View {
    let isActive: Bool
    let themeColor: Color

    var body: some View {
        Stage(themeColor: themeColor) {
            Stepped(steps: 3, interval: .seconds(0.8), isActive: isActive) { step in
                ZStack {
                    Image("DailySpendLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                        .clipShape(.rect(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
                    row("Food", L10n.isZh ? "咖啡" : "Coffee", 4.80)
                        .offset(x: -50, y: -98)
                    row("Grocery", L10n.isZh ? "买菜" : "Groceries", 42.15)
                        .offset(x: 56, y: 88)
                        .opacity(step >= 1 ? 1 : 0)
                        .scaleEffect(step >= 1 ? 1 : 0.85)
                    row("Entertainment", L10n.isZh ? "电影，3 人分" : "Movie, split 3", 12.00)
                        .offset(x: -40, y: 128)
                        .opacity(step >= 2 ? 1 : 0)
                        .scaleEffect(step >= 2 ? 1 : 0.85)
                }
                .offset(y: -10)
            }
        }
    }

    private func row(_ category: String, _ title: String, _ amount: Double) -> some View {
        HStack(spacing: 8) {
            CategoryBubble(category: category, size: 28)
            Text(title).font(.footnote.weight(.semibold)).lineLimit(1)
            Text(sampleMoney(amount)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .miniCard(cornerRadius: 14)
    }
}

private struct ReceiptPaper: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tooth: CGFloat = 8
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tooth))
        var x = rect.maxX
        var down = true
        while x > rect.minX {
            x = max(rect.minX, x - tooth)
            path.addLine(to: CGPoint(x: x, y: down ? rect.maxY : rect.maxY - tooth))
            down.toggle()
        }
        path.closeSubpath()
        return path
    }
}

private struct ScanScene: View {
    let isActive: Bool
    let themeColor: Color

    var body: some View {
        Stage(themeColor: themeColor) {
            Stepped(steps: 4, isActive: isActive) { step in
                ZStack {
                    receipt
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(themeColor)
                                .frame(height: 3)
                                .shadow(color: themeColor, radius: 6)
                                .padding(.horizontal, -6)
                                .offset(y: step >= 1 ? 196 : 8)
                                .opacity(step == 1 ? 1 : 0)
                        }
                        .offset(x: -44, y: step >= 2 ? -24 : 0)
                        .scaleEffect(step >= 2 ? 0.92 : 1)

                    result(step: step)
                        .offset(x: 34, y: step >= 2 ? 82 : 150)
                        .opacity(step >= 2 ? 1 : 0)
                }
            }
        }
    }

    private var receipt: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.isZh ? "街角咖啡" : "CORNER CAFÉ")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            line(L10n.isZh ? "拿铁" : "Latte", 5.50)
            line(L10n.isZh ? "可颂" : "Croissant", 4.25)
            Rectangle()
                .fill(.black.opacity(0.25))
                .frame(height: 1)
                .padding(.vertical, 2)
            line(L10n.isZh ? "合计" : "TOTAL", 9.75, bold: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.black.opacity(0.75))
        .padding(14)
        .padding(.bottom, 8)
        .frame(width: 164, height: 204)
        .background(ReceiptPaper().fill(.white))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }

    private func line(_ name: String, _ amount: Double, bold: Bool = false) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(amount.formatted(.number.precision(.fractionLength(2))))
        }
        .font(.system(size: 11, weight: bold ? .bold : .regular, design: .monospaced))
    }

    private func result(step: Int) -> some View {
        HStack(spacing: 10) {
            CategoryBubble(category: "Food", size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.isZh ? "街角咖啡" : "Corner Café")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                Text(L10n.isZh ? "餐饮 · 今天" : "Food · Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(sampleMoney(9.75))
                    .font(.headline.monospacedDigit())
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .opacity(step >= 3 ? 1 : 0)
                    .scaleEffect(step >= 3 ? 1 : 0.3)
            }
        }
        .padding(12)
        .frame(width: 236)
        .miniCard()
    }
}

private struct SplitScene: View {
    let isActive: Bool
    let themeColor: Color

    private let people: [(initial: String, color: Color)] = [("A", .blue), ("S", .pink), ("J", .orange)]

    var body: some View {
        Stage(themeColor: themeColor) {
            Stepped(steps: 4, isActive: isActive) { step in
                VStack(spacing: 10) {
                    HStack(spacing: 0) {
                        segment(L10n.isZh ? "快速分账" : "Quick Split", selected: false)
                        segment(L10n.isZh ? "按项分账" : "By Item", selected: true)
                    }
                    .padding(3)
                    .background(Color.secondary.opacity(0.14), in: .capsule)
                    .frame(width: 230)

                    VStack(spacing: 0) {
                        item(L10n.isZh ? "意面" : "Pasta", 18, sharedBy: step >= 1 ? [0, 1] : [])
                        Divider().padding(.leading, 12)
                        item(L10n.isZh ? "沙拉" : "Salad", 12, sharedBy: step >= 2 ? [1] : [])
                        Divider().padding(.leading, 12)
                        item(L10n.isZh ? "红酒" : "Wine", 24, sharedBy: step >= 2 ? [0, 1, 2] : [])
                    }
                    .miniCard()

                    HStack(spacing: 6) {
                        share(0, 20.40)
                        share(1, 34.80)
                        share(2, 9.60)
                    }
                    .opacity(step >= 3 ? 1 : 0)
                    .offset(y: step >= 3 ? 0 : 10)
                }
            }
        }
    }

    private func segment(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if selected {
                    Capsule().fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                }
            }
            .foregroundStyle(selected ? .primary : .secondary)
    }

    private func item(_ name: String, _ price: Double, sharedBy: Set<Int>) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.subheadline)
            Text(sampleMoney(price))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            ForEach(people.indices, id: \.self) { index in
                avatar(index, filled: sharedBy.contains(index))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func avatar(_ index: Int, filled: Bool, size: CGFloat = 26) -> some View {
        let person = people[index]
        return Text(person.initial)
            .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? .white : person.color)
            .frame(width: size, height: size)
            .background(filled ? person.color : person.color.opacity(0.14), in: .circle)
    }

    private func share(_ index: Int, _ amount: Double) -> some View {
        HStack(spacing: 5) {
            avatar(index, filled: true, size: 20)
            Text(sampleMoney(amount))
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .miniCard(cornerRadius: 12)
    }
}

private struct QuickAddScene: View {
    let isActive: Bool
    let themeColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var typed: Int?
    @State private var showsResult = true

    private var phrase: String { L10n.isZh ? "和 Alex 吃午饭 25" : "Lunch with Alex 25" }

    var body: some View {
        Stage(themeColor: themeColor) {
            VStack(alignment: .leading, spacing: 14) {
                Label(L10n.isZh ? "快速记账" : "Quick Add", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeColor)

                HStack(spacing: 1) {
                    Text(String(phrase.prefix(typed ?? phrase.count)))
                        .font(.body)
                    Rectangle()
                        .fill(themeColor)
                        .frame(width: 2, height: 22)
                        .opacity(showsResult ? 0 : 1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .miniCard(cornerRadius: 14)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        chip(sampleMoney(25), symbol: "dollarsign.circle.fill", tint: themeColor)
                        chip(L10n.categoryName("Food"), symbol: "fork.knife", tint: .orange)
                        chip(L10n.isZh ? "今天" : "Today", symbol: "calendar", tint: .blue)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "note.text").foregroundStyle(.secondary)
                        Text(L10n.isZh ? "和 Alex 吃午饭" : "Lunch with Alex")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
                .opacity(showsResult ? 1 : 0)
                .offset(y: showsResult ? 0 : 8)
            }
            .frame(maxWidth: 280)
        }
        .task(id: isActive) {
            guard isActive, !reduceMotion else {
                typed = nil
                showsResult = true
                return
            }
            while !Task.isCancelled {
                showsResult = false
                typed = 0
                try? await Task.sleep(for: .milliseconds(500))
                for count in 1...phrase.count {
                    if Task.isCancelled { return }
                    typed = count
                    try? await Task.sleep(for: .milliseconds(85))
                }
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.spring(duration: 0.5, bounce: 0.2)) { showsResult = true }
                try? await Task.sleep(for: .seconds(2.6))
            }
        }
    }

    private func chip(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.semibold))
            .labelStyle(TintedIconLabelStyle(tint: tint))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .miniCard(cornerRadius: 12)
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

private struct SiriScene: View {
    let isActive: Bool
    let themeColor: Color

    var body: some View {
        Stage(themeColor: themeColor) {
            Stepped(steps: 3, isActive: isActive) { step in
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(colors: [.purple, .pink, .orange], startPoint: .leading, endPoint: .trailing)
                            )
                            .symbolEffect(.variableColor.iterative, isActive: isActive && step == 0)
                        Text(L10n.isZh ? "“在DailySpend里记一笔”" : "“Log an expense in DailySpend”")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .miniCard(cornerRadius: 18)

                    HStack(spacing: 10) {
                        CategoryBubble(category: "Food", size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L10n.isZh ? "午饭" : "Lunch").font(.subheadline.weight(.semibold))
                            Text(L10n.isZh ? "已保存" : "Saved").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(sampleMoney(12)).font(.headline.monospacedDigit())
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .padding(12)
                    .frame(maxWidth: 260)
                    .miniCard()
                    .opacity(step >= 1 ? 1 : 0)
                    .offset(y: step >= 1 ? 0 : -8)

                    HStack(spacing: 22) {
                        control("doc.text.viewfinder", L10n.isZh ? "扫描收据" : "Scan Receipt", lit: step >= 2)
                        control("plus", L10n.isZh ? "记一笔" : "Add Expense", lit: step >= 2)
                        control("button.programmable", L10n.isZh ? "操作按钮" : "Action Button", lit: step >= 2)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func control(_ symbol: String, _ title: String, lit: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(lit ? .white : themeColor)
                .frame(width: 52, height: 52)
                .background(lit ? themeColor : Color(uiColor: .secondarySystemGroupedBackground), in: .circle)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 76)
    }
}

private struct InsightsScene: View {
    let isActive: Bool
    let themeColor: Color

    private var monthTitle: String {
        let month = Date().formatted(.dateTime.month(.wide))
        return L10n.isZh ? "\(month)至今" : "\(month) So Far"
    }

    var body: some View {
        Stage(themeColor: themeColor) {
            Stepped(steps: 3, isActive: isActive) { step in
                VStack(alignment: .leading, spacing: 6) {
                    Text(monthTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(L10n.isZh ? "少花 \(sampleMoney(219, wholeUnits: true))" : "\(sampleMoney(219, wholeUnits: true)) less")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(.green)
                        .scaleEffect(step >= 2 ? 1 : 0.9, anchor: .leading)
                        .opacity(step >= 2 ? 1 : 0.25)
                    Text(L10n.isZh ? "与上月同期相比" : "than this time last month")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TrendLines(progress: step >= 1 ? 1 : 0, themeColor: themeColor)
                        .frame(height: 64)
                        .padding(.vertical, 8)

                    Text(L10n.isZh ? "已花 \(sampleMoney(1280, wholeUnits: true))" : "You’ve spent \(sampleMoney(1280, wholeUnits: true))")
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.isZh ? "餐饮少花 \(sampleMoney(96, wholeUnits: true))" : "Food is down \(sampleMoney(96, wholeUnits: true))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: 270, alignment: .leading)
                .miniCard(cornerRadius: 20)
            }
        }
    }
}

private struct TrendLines: View {
    let progress: CGFloat
    let themeColor: Color

    var body: some View {
        ZStack {
            TrendLine(values: [0.14, 0.3, 0.44, 0.55, 0.66, 0.78, 0.86])
                .trim(from: 0, to: progress)
                .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
            TrendLine(values: [0.1, 0.22, 0.3, 0.42, 0.48, 0.55, 0.6])
                .trim(from: 0, to: progress)
                .stroke(themeColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Running totals across the month, as fractions of the chart's height.
private struct TrendLine: Shape {
    let values: [CGFloat]

    func path(in rect: CGRect) -> Path {
        Path { path in
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: rect.maxY - rect.height * value
                )
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }
}
