import Foundation

struct VideoRecord: Identifiable, Equatable {
    let id: String
    var name: String
    var created: Date?
    var modified: Date?
    var bytes: Int64?
    var duration: Double
    var favorite: Bool
    static func demo(_ count: Int = 12) -> [VideoRecord] {
        (0..<count).map { i in VideoRecord(id: "demo-\(i)", name: "サンプル動画 \(i + 1)", created: Date().addingTimeInterval(-Double(i % 180) * 86400), modified: nil, bytes: Int64((i % 7 + 1) * 320_000_000), duration: Double(i % 90 + 10), favorite: i % 17 == 0) }
    }
}
enum VideoDecision: String, Codable { case none, keep, later }
enum VideoOrder: String, CaseIterable { case size = "容量が大きい順", oldest = "撮影日が古い順", newest = "撮影日が新しい順" }
enum LibraryFilter: String, CaseIterable { case all = "すべて", candidate = "整理候補", keep = "残す", later = "見直す" }
struct SavedDecision: Codable, Equatable {
    var value: VideoDecision
    var due: Date?
}
struct VideoRules {
    static func reasons(_ r: VideoRecord, now: Date = Date()) -> [String] {
        var result: [String] = []
        if let size = r.bytes, size >= 2 * 1024 * 1024 * 1024 { result.append("2 GB以上") }
        if let date = r.created, now.timeIntervalSince(date) >= 90 * 86400 { result.append("撮影から90日以上") }
        return result
    }
    static func eligible(_ r: VideoRecord, decisions: [String: SavedDecision]) -> Bool { !r.favorite && decisions[r.id]?.value != .keep }
    static func candidate(_ r: VideoRecord, decisions: [String: SavedDecision], now: Date = Date()) -> Bool {
        if !eligible(r, decisions: decisions) { return false }
        if let saved = decisions[r.id], saved.value == .later, let due = saved.due, due > now { return false }
        return !reasons(r, now: now).isEmpty
    }
    static func ordered(_ rows: [VideoRecord], by order: VideoOrder) -> [VideoRecord] {
        rows.sorted { a, b in
            switch order {
            case .size: if a.bytes != b.bytes { return (a.bytes ?? -1) > (b.bytes ?? -1) }
            case .oldest: if a.created != b.created { return (a.created ?? .distantFuture) < (b.created ?? .distantFuture) }
            case .newest: if a.created != b.created { return (a.created ?? .distantPast) > (b.created ?? .distantPast) }
            }
            return a.id < b.id
        }
    }
    static func size(_ bytes: Int64?) -> String { bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "容量未確認" }
}
