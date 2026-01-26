import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

// MARK: - CSV & JSON
struct CSVDocument: FileDocument, Transferable {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String; init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { guard let data = configuration.file.regularFileContents, let string = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }; text = string }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { let data = text.data(using: .utf8)!; return FileWrapper(regularFileWithContents: data) }
    static var transferRepresentation: some TransferRepresentation { DataRepresentation(contentType: .commaSeparatedText) { document in document.text.data(using: .utf8)! } importing: { data in CSVDocument(text: String(data: data, encoding: .utf8)!) } }
}

struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { return FileWrapper(regularFileWithContents: data) }
}

// ✨ 修改：备份项增加频率字段
struct ExpenseBackupItem: Codable {
    let amount: Double
    let category: String
    let note: String
    let date: Date
    // 使用 Optional 兼容旧备份
    let frequency: RecurrenceFrequency?
}

// MARK: - Enums
enum TimeRange: Int, CaseIterable, Identifiable {
    case thisMonth = 0; case lastMonth = 1; case thisYear = 2; case all = 3
    var id: Int { self.rawValue }
    var displayName: String { L10n.timeRanges[self.rawValue] }
}

// ✨ 关键修复：InsightTab 更新为 Trends 和 Activity
enum InsightTab: String, CaseIterable, Identifiable {
    case trends, activity
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .trends: return L10n.trends
        case .activity: return L10n.activity
        }
    }
}
