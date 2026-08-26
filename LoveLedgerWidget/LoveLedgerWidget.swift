import WidgetKit
import SwiftUI

// MARK: - 1. Widget Bundle
@main
struct LoveLedgerWidgets: WidgetBundle {
    var body: some Widget {
        QuickAddWidget()
        DashboardWidget()
    }
}

// MARK: - 2. 数据模型 (Shared Data)
struct WidgetData {
    static let appGroup = "group.com.jackson.LoveLedger"
    
    let total: Double
    let budget: Double
    let isBudgetEnabled: Bool
    let chartData: [Double]
    let lastUpdated: Date
    
    static func load() -> WidgetData {
        if let store = UserDefaults(suiteName: appGroup) {
            return WidgetData(
                total: store.double(forKey: "widget_total"),
                budget: store.double(forKey: "widget_budget"),
                isBudgetEnabled: store.bool(forKey: "widget_isBudgetEnabled"),
                chartData: store.array(forKey: "widget_chartData") as? [Double] ?? [],
                lastUpdated: store.object(forKey: "widget_lastUpdated") as? Date ?? Date()
            )
        }
        return WidgetData(total: 0, budget: 0, isBudgetEnabled: false, chartData: [], lastUpdated: Date())
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), data: WidgetData.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), data: WidgetData.load())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let data = WidgetData.load()
        let entry = SimpleEntry(date: Date(), data: data)
        let nextUpdateDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
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
                ZStack {
                    Circle().fill(.white).shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    Image(systemName: "plus").font(.system(size: 28, weight: .heavy)).foregroundColor(themeColor)
                }.frame(width: 50, height: 50)
                Text(labelText).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white).shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
        }.widgetURL(URL(string: "loveledger://add"))
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
        .configurationDisplayName("Quick Add")
        .description("Quickly add a new expense.")
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
    let textSecondary = Color.gray
    let textTertiary = Color.gray.opacity(0.6)
    
    var currencySymbol: String {
        Locale.current.currencySymbol ?? Locale(identifier: "en_US").currencySymbol ?? "$"
    }
    
    var weekDayLabels: [String] {
        let calendar = Calendar.current
        let today = Date()
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
            if family == .systemMedium { mediumLayout } else { smallLayout }
        }
        .widgetURL(URL(string: "loveledger://home"))
        // 关键：强制组件内容使用深色模式的配色逻辑（白字）
        .colorScheme(.dark)
    }
    
    // MARK: - Small Layout
    var smallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.data.isBudgetEnabled ? "REMAINING" : "THIS MONTH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(textSecondary)
                    .textCase(.uppercase)
                    .padding(.bottom, 2)
                
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(currencySymbol).font(.title3).bold().foregroundStyle(themeColor)
                    let amount = entry.data.isBudgetEnabled ? (entry.data.budget - entry.data.total) : entry.data.total
                    Text(String(format: "%.0f", amount))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(textPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
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
                Text("THIS MONTH").font(.caption).bold().foregroundStyle(textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(currencySymbol).font(.title3).bold().foregroundStyle(themeColor)
                    Text(String(format: "%.0f", entry.data.total))
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(textPrimary)
                        .minimumScaleFactor(0.8)
                }
                Text(entry.data.lastUpdated.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 分割线：深灰色
            Divider().overlay(Color.white.opacity(0.15)).padding(.vertical, 12).padding(.horizontal, 16)
            
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
            Text("7 DAY TREND")
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
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(isToday ? themeColor : textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
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
                    Text("LAST 7 DAYS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(textSecondary)
                    Text(currencySymbol + String(format: "%.0f", sevenDayTotal))
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
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(isToday ? themeColor : textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
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
                Text(isOver ? "OVER" : "\(Int(progress * 100))%")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isOver ? statusColor : textSecondary)
                Spacer()
                Text("/ \(Int(entry.data.budget))")
                    .font(.system(size: 9))
                    .foregroundStyle(textTertiary)
            }
        }
    }
    
    var budgetInfoView: some View {
        let left = entry.data.budget - entry.data.total
        let progress = entry.data.total / max(entry.data.budget, 1.0)
        let isOver = entry.data.total > entry.data.budget
        
        return VStack(alignment: .leading, spacing: 4) {
            Text("BUDGET").font(.caption).bold().foregroundStyle(textSecondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(isOver ? "Over" : "Left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textSecondary)
                Text(String(format: "%.0f", abs(left)))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor)
            }
            
            Spacer().frame(height: 8)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(statusColor).frame(width: min(geo.size.width * progress, geo.size.width))
                }
            }.frame(height: 8)
            
            HStack {
                Text("\(Int(min(progress, 1.0) * 100))% used")
                    .font(.caption2).bold().foregroundStyle(statusColor)
                Spacer()
                Text(String(format: "%.0f", entry.data.budget))
                    .font(.caption2).foregroundStyle(textTertiary)
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
        .configurationDisplayName("Monthly Dashboard")
        .description("View spending trends or budget status.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
