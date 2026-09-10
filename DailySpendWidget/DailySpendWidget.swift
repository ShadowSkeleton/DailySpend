import WidgetKit
import SwiftUI

// MARK: - 1. Widget Bundle
@main
struct DailySpendWidgets: WidgetBundle {
    var body: some Widget {
        QuickAddWidget()
        DashboardWidget()
    }
}

// MARK: - 2. 数据模型 (Shared Data)
typealias WidgetData = WidgetSnapshot

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), data: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), data: context.isPreview ? .preview : WidgetData.load())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let data = WidgetData.load()
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(36 * 3600)
        let nextDay = Calendar.current.startOfDay(for: midnight)
        // Pre-render the stale state for midnight; never relabel yesterday's
        // chart or last month's total as today's data while the app is closed.
        let entries = [SimpleEntry(date: now, data: data), SimpleEntry(date: nextDay, data: data)]
        let timeline = Timeline(entries: entries, policy: .after(min(now.addingTimeInterval(3600), nextDay)))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - 3. Widget: Quick Add (记一笔)
struct QuickAddWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetRenderingMode) private var renderingMode
    let themeColor = Color(red: 0.0, green: 0.78, blue: 0.70)
    var labelText: String { Locale.current.identifier.hasPrefix("zh") ? "记一笔" : "New Expense" }

    var body: some View {
        ZStack {
            // 背景装饰
            GeometryReader { geo in
                ZStack {
                    Circle().fill(.white.opacity(0.1)).frame(width: geo.size.width * 0.9).offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.35)
                    Circle().fill(.white.opacity(0.1)).frame(width: geo.size.width * 0.6).offset(x: geo.size.width * 0.4, y: geo.size.height * 0.4)
                }
            }
            VStack(spacing: 8) {
                Group {
                    if renderingMode == .fullColor {
                        ZStack {
                            Circle().fill(.white).shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                            Image(systemName: "plus").font(.system(size: 28, weight: .heavy)).foregroundColor(themeColor)
                        }
                    } else {
                        // In tinted/clear rendering, a separately colored plus
                        // and filled circle can flatten into the same color.
                        Image(systemName: "plus.circle")
                            .font(.system(size: 46, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }.frame(width: 50, height: 50)
                Text(labelText).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white).shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
        }
        .widgetURL(URL(string: "dailyspend://add"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Locale.current.identifier.hasPrefix("zh") ? "在 DailySpend 中新增支出" : "Add a new expense in DailySpend")
    }
}

struct QuickAddWidget: Widget {
    let kind: String = "QuickAddWidget"
    let gradient = LinearGradient(colors: [Color(red: 0.0, green: 0.78, blue: 0.70), Color(red: 0.0, green: 0.60, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                QuickAddWidgetEntryView(entry: entry).containerBackground(for: .widget) { ContainerRelativeShape().fill(gradient) }
            } else {
                QuickAddWidgetEntryView(entry: entry).padding().background(gradient)
            }
        }
        .configurationDisplayName("DailySpend Quick Add")
        .description("Open DailySpend directly to a new expense.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - 4. Widget: Dashboard (数据面板)
struct DashboardWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    // 品牌色
    let themeColor = Color(red: 0.0, green: 0.78, blue: 0.70)
    
    // ✨ 深色模式下的文字颜色 (强制浅色)
    let textPrimary = Color.white
    let textSecondary = Color.white.opacity(0.78)
    let textTertiary = Color.white.opacity(0.65)
    
    var currencySymbol: String {
        Locale.current.currencySymbol ?? Locale(identifier: "en_US").currencySymbol ?? "$"
    }

    var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var isChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    func amountDigits(_ amount: Double) -> String {
        abs(amount).formatted(.number.grouping(.automatic).precision(.fractionLength(2)))
    }

    func formattedCurrency(_ amount: Double) -> String {
        amount.formatted(.currency(code: currencyCode).precision(.fractionLength(2)))
    }
    
    var weekDayLabels: [String] {
        let calendar = Calendar.current
        let today = entry.data.lastUpdated
        var labels: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        for i in (0..<7).reversed() {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                labels.append(formatter.string(from: date))
            } else {
                labels.append("")
            }
        }
        return labels
    }
    
    // 状态颜色 (在深色背景上，红色和橙色需要足够亮)
    var statusColor: Color {
        guard entry.data.isBudgetEnabled, entry.data.budget > 0 else { return themeColor }
        let progress = entry.data.total / entry.data.budget
        if progress > 1.0 { return Color(hue: 0.0, saturation: 0.8, brightness: 1.0) } // 亮红
        if progress > 0.8 { return Color.orange }
        return themeColor
    }
    
    // ✨ 霓虹图表渐变
    func getBarGradient(isToday: Bool) -> LinearGradient {
        if isToday {
            // 今日：高亮品牌色，带一点点亮光
            return LinearGradient(
                colors: [themeColor, themeColor.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            // 过去：深青灰色，低调但不死黑
            return LinearGradient(
                colors: [themeColor.opacity(0.3), themeColor.opacity(0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    var body: some View {
        Group {
            if entry.data.hidesAmounts {
                messageLayout(icon: "lock.fill", message: isChinese ? "金额已隐藏\n打开应用以查看" : "Amounts hidden\nOpen the app to view")
            } else if !entry.data.hasData {
                emptyLayout
            } else if entry.data.needsRefresh(at: entry.date) {
                messageLayout(icon: "arrow.clockwise", message: isChinese ? "打开应用以刷新支出" : "Open the app to refresh spending")
            } else if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .widgetURL(URL(string: "dailyspend://home"))
        .privacySensitive()
        // 关键：强制组件内容使用深色模式的配色逻辑（白字）
        .colorScheme(.dark)
    }

    var emptyLayout: some View {
        messageLayout(icon: "chart.bar.fill", message: isChinese ? "打开应用以载入最新数据" : "Open the app to load your latest data")
    }

    func messageLayout(icon: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(themeColor)
                .accessibilityHidden(true)
            Text("DailySpend")
                .font(.headline)
                .foregroundStyle(textPrimary)
            Text(message)
                .font(.caption)
                .foregroundStyle(textSecondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
        .accessibilityElement(children: .combine)
    }
    
    // MARK: - Small Layout
    var smallLayout: some View {
        let difference = entry.data.budget - entry.data.total
        let isOver = entry.data.isBudgetEnabled && difference < 0
        let amount = entry.data.isBudgetEnabled ? abs(difference) : entry.data.total

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.data.isBudgetEnabled
                     ? (isOver ? (isChinese ? "超出预算" : "OVER BUDGET") : (isChinese ? "剩余预算" : "REMAINING"))
                     : (isChinese ? "本月支出" : "THIS MONTH"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(textSecondary)
                    .textCase(.uppercase)
                    .padding(.bottom, 2)
                
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(currencySymbol).font(.title3).bold().foregroundStyle(themeColor)
                    Text(amountDigits(amount))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(textPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(formattedCurrency(amount))
            }
            
            Spacer()
            
            if entry.data.isBudgetEnabled && entry.data.budget > 0 {
                budgetProgressBar
            } else {
                smallLabeledTrendChart(height: 28)
            }
        }
        .padding(16)
    }
    
    // MARK: - Medium Layout
    var mediumLayout: some View {
        HStack(spacing: 0) {
            // Left Side
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text(isChinese ? "本月支出" : "THIS MONTH").font(.caption).bold().foregroundStyle(textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(currencySymbol).font(.title3).bold().foregroundStyle(themeColor)
                    Text(amountDigits(entry.data.total))
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(textPrimary)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(formattedCurrency(entry.data.total))
                Text((isChinese ? "更新于 " : "Updated ") + entry.data.lastUpdated.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 分割线：深灰色
            Divider().overlay(Color.white.opacity(0.15)).padding(.vertical, 12).padding(.horizontal, 12)
            
            // Right Side
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                if entry.data.isBudgetEnabled {
                    budgetInfoView
                } else {
                    richTrendChart
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }
    
    // MARK: - Subviews
    
    func smallLabeledTrendChart(height: CGFloat) -> some View {
        let data = entry.data.chartData
        let labels = weekDayLabels
        let maxVal = data.max() ?? 1.0
        let safeMax = maxVal == 0 ? 1.0 : maxVal
        
        return VStack(alignment: .leading, spacing: 4) {
            Text(isChinese ? "近 7 天" : "7 DAY TREND")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(textSecondary)
            
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<min(7, data.count), id: \.self) { index in
                    let val = data[index]
                    let isToday = index == data.count - 1
                    
                    VStack(spacing: 2) {
                        GeometryReader { geo in
                            ZStack(alignment: .bottom) {
                                Color.clear
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(getBarGradient(isToday: isToday))
                                    // 给今日添加霓虹辉光
                                    .shadow(color: isToday ? themeColor.opacity(0.5) : .clear, radius: 4, x: 0, y: 0)
                                    .frame(height: max(3, geo.size.height * (val / safeMax)))
                            }
                        }
                        .frame(height: height)
                        
                        Text(labels.indices.contains(index) ? labels[index] : "")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isToday ? themeColor : textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((isChinese ? "近 7 天支出合计 " : "Seven-day spending total ") + formattedCurrency(data.reduce(0, +)))
    }
    
    var richTrendChart: some View {
        let data = entry.data.chartData
        let labels = weekDayLabels
        let maxVal = data.max() ?? 1.0
        let safeMax = maxVal == 0 ? 1.0 : maxVal
        let sevenDayTotal = data.reduce(0, +)
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(isChinese ? "近 7 天" : "LAST 7 DAYS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(textSecondary)
                    Text(formattedCurrency(sevenDayTotal))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(textPrimary)
                }
            }
            
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<min(7, data.count), id: \.self) { index in
                    let val = data[index]
                    let isToday = index == data.count - 1
                    
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .bottom) {
                                Color.clear
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(getBarGradient(isToday: isToday))
                                    .shadow(color: isToday ? themeColor.opacity(0.5) : .clear, radius: 5, x: 0, y: 0)
                                    .frame(height: max(4, geo.size.height * (val / safeMax)))
                            }
                        }
                        .frame(height: 45)
                        
                        Text(labels.indices.contains(index) ? labels[index] : "")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isToday ? themeColor : textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
    
    var budgetProgressBar: some View {
        let progress = min(entry.data.total / entry.data.budget, 1.0)
        let isOver = entry.data.total > entry.data.budget
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)) // 轨道微亮
                    Capsule().fill(statusColor).frame(width: geo.size.width * progress)
                }
            }.frame(height: 6)
            HStack {
                Text(isOver ? (isChinese ? "超出" : "OVER") : "\(Int(progress * 100))%")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isOver ? statusColor : textSecondary)
                Spacer()
                Text("/ " + formattedCurrency(entry.data.budget))
                    .font(.system(size: 9))
                    .foregroundStyle(textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isChinese
                            ? (isOver ? "超出预算 \(formattedCurrency(entry.data.total - entry.data.budget))" : "已使用预算的 \(Int(progress * 100))%，总预算 \(formattedCurrency(entry.data.budget))")
                            : (isOver ? "Over budget by \(formattedCurrency(entry.data.total - entry.data.budget))" : "\(Int(progress * 100)) percent of a \(formattedCurrency(entry.data.budget)) budget used"))
    }
    
    var budgetInfoView: some View {
        let left = entry.data.budget - entry.data.total
        let progress = entry.data.budget > 0 ? entry.data.total / entry.data.budget : (entry.data.total > 0 ? 1 : 0)
        let isOver = entry.data.total > entry.data.budget
        
        return VStack(alignment: .leading, spacing: 4) {
            Text(isChinese ? "预算" : "BUDGET").font(.caption).bold().foregroundStyle(textSecondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isOver ? (isChinese ? "超出" : "Over") : (isChinese ? "剩余" : "Left"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textSecondary)
                Text(formattedCurrency(abs(left)))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            
            Spacer().frame(height: 8)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(statusColor).frame(width: min(geo.size.width * progress, geo.size.width))
                }
            }.frame(height: 8)
            
            HStack {
                Text(isChinese ? "已使用 \(Int(min(progress, 1.0) * 100))%" : "\(Int(min(progress, 1.0) * 100))% used")
                    .font(.caption2).bold().foregroundStyle(statusColor)
                Spacer()
                Text(formattedCurrency(entry.data.budget))
                    .font(.caption2).foregroundStyle(textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
        }
    }
}

struct DashboardWidget: Widget {
    let kind: String = "DashboardWidget"
    // ✨ 午夜墨绿渐变 (Midnight Teal) - 解决沉闷问题的关键
    // 这种极深的青黑色，比纯黑更有质感，能完美衬托亮绿色的图表
    let darkGradient = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.15, blue: 0.15), // Deep Teal
            Color(red: 0.02, green: 0.05, blue: 0.05)  // Almost Black
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                DashboardWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) { ContainerRelativeShape().fill(darkGradient) }
            } else {
                DashboardWidgetEntryView(entry: entry)
                    .padding()
                    .background(darkGradient)
            }
        }
        .configurationDisplayName("DailySpend Dashboard")
        .description("View your monthly spending, trend, and budget status.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
