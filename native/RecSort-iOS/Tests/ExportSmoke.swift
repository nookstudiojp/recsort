import Foundation
import AVFoundation
@main
struct ExportSmoke {
    @MainActor static func main() async throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let original = try Data(contentsOf: source)
        let asset = AVURLAsset(url: source)
        let result = try await VideoExportOperation().run(asset: asset, quality: .compact, prefix: "test", directory: directory, before: Int64(original.count))
        let output = AVURLAsset(url: result.url)
        let duration = try await output.load(.duration).seconds
        let videos = try await output.loadTracks(withMediaType: .video)
        let audio = try await output.loadTracks(withMediaType: .audio)
        precondition(!videos.isEmpty && !audio.isEmpty)
        let size = try await videos[0].load(.naturalSize)
        precondition(max(size.width, size.height) <= 960)
        precondition(duration > 3.5 && duration < 4.5)
        precondition(result.after < original.count)
        let unchanged = try Data(contentsOf: source)
        precondition(unchanged == original)
        let copy = try await VideoExportOperation().run(asset: asset, quality: .copy, prefix: "copy", directory: directory, before: Int64(original.count))
        precondition(FileManager.default.fileExists(atPath: copy.url.path))
        let operation = VideoExportOperation()
        let task = Task { try await operation.run(asset: asset, quality: .compact, prefix: "cancel", directory: directory, before: nil) }
        await Task.yield(); task.cancel()
        do { _ = try await task.value; throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cancellation unexpectedly succeeded"]) } catch is CancellationError {} catch { if !task.isCancelled { throw error } }
        let report: [String: Any] = ["inputBytes": original.count, "outputBytes": result.after, "duration": duration, "width": size.width, "height": size.height, "audioTracks": audio.count, "output": result.url.path, "copy": copy.url.path]
        try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted).write(to: directory.appendingPathComponent("report.json"))
        print("Export smoke passed: 540p compression, audio, duration, original retained, copy and cancellation")
        print(String(data: try JSONSerialization.data(withJSONObject: report), encoding: .utf8)!)
    }
}
