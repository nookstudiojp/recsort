import Foundation
@preconcurrency import AVFoundation

enum ExportQuality: String, CaseIterable, Identifiable {
    case copy = "元の画質で書き出す"
    case compact = "小さくする（最大540p）"
    case balanced = "バランス（最大720p）"
    var id: String { rawValue }
    var preset: String {
        switch self {
        case .copy: return AVAssetExportPresetPassthrough
        case .compact: return AVAssetExportPreset960x540
        case .balanced: return AVAssetExportPreset1280x720
        }
    }
}
struct ExportedVideo: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let before: Int64?
    let after: Int64
    let quality: ExportQuality
}
@MainActor
final class VideoExportOperation {
    private var session: AVAssetExportSession?
    private var cancelled = false
    func cancel() { cancelled = true; session?.cancelExport() }
    func run(asset: AVAsset, quality: ExportQuality, prefix: String, directory: URL, before: Int64?) async throws -> ExportedVideo {
        cancelled = false
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let export = AVAssetExportSession(asset: asset, presetName: quality.preset) else { throw NSError(domain: "RecSort", code: 1, userInfo: [NSLocalizedDescriptionKey: "この動画の書き出しに対応していません"]) }
        session = export
        let type: AVFileType = export.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        guard export.supportedFileTypes.contains(type) else { throw NSError(domain: "RecSort", code: 2, userInfo: [NSLocalizedDescriptionKey: "対応する保存形式がありません"]) }
        let safe = String(prefix.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "\n", with: "_").prefix(60))
        let name = "RecSort-\(safe)-\(UUID().uuidString.prefix(8)).\(type == .mp4 ? "mp4" : "mov")"
        let output = directory.appendingPathComponent(name)
        export.outputURL = output; export.outputFileType = type; export.shouldOptimizeForNetworkUse = true
        do {
            try await withTaskCancellationHandler(operation: {
                if #available(iOS 18, macOS 15, *) {
                    try await export.export(to: output, as: type)
                } else {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        export.exportAsynchronously {
                            if export.status == .completed { continuation.resume() }
                            else { continuation.resume(throwing: export.error ?? CancellationError()) }
                        }
                    }
                }
            }, onCancel: { Task { @MainActor in self.cancel() } })
            if cancelled { throw CancellationError() }
            let bytes = Int64(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard bytes > 0 else { throw NSError(domain: "RecSort", code: 3, userInfo: [NSLocalizedDescriptionKey: "書き出し結果が空でした"]) }
            return ExportedVideo(url: output, name: name, before: before, after: bytes, quality: quality)
        } catch {
            // Only this operation's generated temporary copy is removed.
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
