import Foundation
import Photos
import AVFoundation
import SwiftUI

@MainActor
final class LibraryStore: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var records: [VideoRecord] = []
    @Published var decisions: [String: SavedDecision] = [:]
    @Published var selected = Set<String>()
    @Published var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var message = "写真へのアクセスを許可すると、許可した動画を一覧にします。"
    @Published var isDemo = false
    @Published var measuring = false
    @Published var deleting = false
    @Published var reviewing = false
    @Published var mediaBusy = false
    @Published var exportResult: ExportedVideo?
    @Published var exportMessage = "元動画を残したコピーを作ります。"
    @Published var exportSaved = false
    @Published var savingExport = false
    private var mediaRequest: PHImageRequestID?
    private var exportOperation: VideoExportOperation?
    private var exportCancelled = false
    private var temporaryExport: URL?
    private var pendingRefresh = false
    private var lastAction = ""
    @Published var player: AVPlayer?
    @Published var measured = 0
    @Published var loading = false
    private var measureTask: Task<Void, Never>?
    private var generation = UUID()
    private var measurementID = UUID()
    private var observerRegistered = false
    private let decisionStorage = "recsort-ios-decisions-v1"
    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: decisionStorage), let saved = try? JSONDecoder().decode([String: SavedDecision].self, from: data) { decisions = saved }
    }
    func start() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if authorization == .authorized || authorization == .limited {
            if !observerRegistered { PHPhotoLibrary.shared().register(self); observerRegistered = true }
            reload()
        }
    }
    func authorize() async {
        message = "写真アクセスの許可を確認しています…"
        authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        start()
        if authorization == .denied || authorization == .restricted { message = "写真へのアクセスがありません。設定から許可するか、サンプルで試せます。" }
    }
    func demo(count: Int = 12) {
        cancelMeasurement(); generation = UUID(); loading = false; isDemo = true; selected.removeAll(); decisions = [:]; records = VideoRecord.demo(count)
        message = "デモ：\(count)件の架空の動画です。実際の写真には影響しません。"
    }
    func reload() {
        guard !deleting, !reviewing, !mediaBusy else { pendingRefresh = true; return }
        cancelMeasurement(); generation = UUID(); if isDemo { selected.removeAll() }; isDemo = false
        if let data = UserDefaults.standard.data(forKey: decisionStorage), let saved = try? JSONDecoder().decode([String: SavedDecision].self, from: data) { decisions = saved } else { decisions = [:] }
        let token = generation
        let old = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        loading = true; message = "許可された動画の情報を読み込んでいます…"
        Task {
            let next: [VideoRecord] = await Task.detached(priority: .userInitiated) {
                let options = PHFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let assets = PHAsset.fetchAssets(with: .video, options: options)
                var next: [VideoRecord] = []
                assets.enumerateObjects { asset, _, _ in
                    let resource = PHAssetResource.assetResources(for: asset).first { $0.type == .video || $0.type == .fullSizeVideo }
                    let previous = old[asset.localIdentifier]
                    let size = previous?.modified == asset.modificationDate ? previous?.bytes : nil
                    next.append(VideoRecord(id: asset.localIdentifier, name: resource?.originalFilename ?? "動画", created: asset.creationDate, modified: asset.modificationDate, bytes: size, duration: asset.duration, favorite: asset.isFavorite))
                }
                return next
            }.value
            guard token == generation, !isDemo else { return }
            records = next; loading = false
            selected = selected.intersection(Set(next.filter { VideoRules.eligible($0, decisions: decisions) }.map(\.id)))
            message = "\(next.count)件の動画。\(authorization == .limited ? "許可した写真のみ表示しています。" : "")容量確認は端末内の動画だけを対象にし、iCloudから自動ダウンロードしません。" + (lastAction.isEmpty ? "" : " " + lastAction)
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in guard let self, !self.isDemo else { return }; self.start() }
    }
    func finishReview() {
        reviewing = false
        if pendingRefresh { pendingRefresh = false; reload() }
    }
    func setDecision(_ value: VideoDecision, for record: VideoRecord, days: Int = 7) {
        decisions[record.id] = value == .none ? nil : SavedDecision(value: value, due: value == .later ? Date().addingTimeInterval(Double(days) * 86400) : nil)
        if value == .keep || value == .later { selected.remove(record.id) }
        if !isDemo, let data = try? JSONEncoder().encode(decisions) { UserDefaults.standard.set(data, forKey: decisionStorage) }
    }
    func cancelMeasurement() { measurementID = UUID(); measureTask?.cancel(); measureTask = nil; measuring = false }
    func measureLocalSizes() {
        guard !isDemo, !measuring, !deleting else { return }
        measuring = true; measured = 0
        let rows = records; let token = generation; let runID = UUID(); measurementID = runID
        measureTask = Task {
            // Bounded batches avoid launching thousands of PhotoKit requests at once.
            for start in stride(from: 0, to: rows.count, by: 4) {
                if Task.isCancelled || token != generation || runID != measurementID { break }
                let chunk = Array(rows[start..<min(start + 4, rows.count)])
                let values = await withTaskGroup(of: (String, Int64?).self) { group in
                    for row in chunk { group.addTask { (row.id, await Self.localSize(row.id)) } }
                    var values: [(String, Int64?)] = []
                    for await value in group { values.append(value) }
                    return values
                }
                if Task.isCancelled || token != generation || runID != measurementID { break }
                for (id, size) in values { if let index = records.firstIndex(where: { $0.id == id }) { records[index].bytes = size }; measured += 1 }
            }
            if token == generation && runID == measurementID { measuring = false; message = "容量確認が終了しました。取得できない動画は「容量未確認」です。iCloudのみの動画や編集済み動画などは確認できない場合があります。" }
        }
    }
    nonisolated private static func localSize(_ id: String) async -> Int64? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions(); options.isNetworkAccessAllowed = false; options.version = .original; options.deliveryMode = .fastFormat
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard let url = (avAsset as? AVURLAsset)?.url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continuation.resume(returning: nil); return }
                continuation.resume(returning: Int64(size))
            }
        }
    }
    func preview(_ row: VideoRecord) async {
        guard !isDemo else { message = "サンプルには実動画がありません。"; return }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [row.id], options: nil).firstObject else { return }
        let options = PHVideoRequestOptions(); options.isNetworkAccessAllowed = false
        let item: AVPlayerItem? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in continuation.resume(returning: item) }
        }
        if let item { player = AVPlayer(playerItem: item) } else { message = "この端末にない動画は再生できません。写真アプリで取得してから再度お試しください。" }
    }
    func clearExport() {
        guard !mediaBusy else { return }
        exportResult = nil; exportSaved = false
        if let url = temporaryExport { try? FileManager.default.removeItem(at: url) }
        temporaryExport = nil
    }
    func cancelExport() {
        exportCancelled = true
        if let id = mediaRequest { PHImageManager.default().cancelImageRequest(id) }
        exportOperation?.cancel()
    }
    func prepareExport(_ row: VideoRecord, quality: ExportQuality, allowNetwork: Bool) async {
        guard !isDemo, !mediaBusy, !deleting else { exportMessage = "実際の動画を写真ライブラリから選んでください。"; return }
        clearExport(); cancelMeasurement(); mediaBusy = true; exportCancelled = false
        exportMessage = allowNetwork ? "必要な場合はiCloudから取得してコピーを作ります…" : "この端末の動画からコピーを作ります…"
        defer { mediaBusy = false; mediaRequest = nil; exportOperation = nil }
        do {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [row.id], options: nil).firstObject else { throw NSError(domain: "RecSort", code: 10, userInfo: [NSLocalizedDescriptionKey: "元動画が見つかりません"]) }
            let options = PHVideoRequestOptions(); options.isNetworkAccessAllowed = allowNetwork; options.version = .original
            let avAsset: AVAsset? = await withCheckedContinuation { continuation in
                mediaRequest = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { value, _, _ in continuation.resume(returning: value) }
            }
            if exportCancelled { throw CancellationError() }
            guard let avAsset else { throw NSError(domain: "RecSort", code: 11, userInfo: [NSLocalizedDescriptionKey: "動画を取得できませんでした。iCloudの動画なら、取得を許可するか写真アプリでダウンロードしてください。"]) }
            let before = (avAsset as? AVURLAsset).flatMap { try? $0.url.resourceValues(forKeys: [.fileSizeKey]).fileSize }.map(Int64.init) ?? row.bytes
            let operation = VideoExportOperation(); exportOperation = operation
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RecSortExports", isDirectory: true)
            let result = try await operation.run(asset: avAsset, quality: quality, prefix: URL(fileURLWithPath: row.name).deletingPathExtension().lastPathComponent, directory: directory, before: before)
            if exportCancelled { try? FileManager.default.removeItem(at: result.url); throw CancellationError() }
            temporaryExport = result.url; exportResult = result
            if quality == .copy { exportMessage = "コピーを作りました。元動画は残っています。保存先で再生を確認してください。" }
            else if let before, result.after >= before { exportMessage = "元動画より小さくなりませんでした。元動画は変更していません。" }
            else { exportMessage = "小さいコピーを作りました。元動画は残っています。画質・音声・向きを確認してください。" }
        } catch { exportMessage = exportCancelled || error is CancellationError ? "中止しました。元動画は変更していません。" : error.localizedDescription }
    }
    func saveExportToPhotos() async {
        guard let result = exportResult, !mediaBusy, !exportSaved else { return }
        mediaBusy = true; savingExport = true; defer { mediaBusy = false; savingExport = false }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: result.url) }
            exportSaved = true; pendingRefresh = true
            exportMessage = "コピーを写真へ保存しました。元動画も残っています。コピーの再生確認後に、必要なら別操作で元動画を整理してください。"
        } catch { exportMessage = "写真へ保存できませんでした：" + error.localizedDescription }
    }
    func deleteReviewed(_ snapshot: [VideoRecord]) async {
        guard !deleting, !snapshot.isEmpty else { return }
        guard snapshot.allSatisfy({ row in records.contains(row) && VideoRules.eligible(row, decisions: decisions) && selected.contains(row.id) }) else { message = "対象や判断が変わりました。選択と確認をやり直してください。"; return }
        if isDemo { let ids = Set(snapshot.map(\.id)); records.removeAll { ids.contains($0.id) }; selected.subtract(ids); message = "デモ内の選択を整理しました。写真ライブラリは変更していません。"; return }
        cancelMeasurement(); deleting = true
        defer { deleting = false }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: snapshot.map(\.id), options: nil)
        guard assets.count == snapshot.count else { message = "動画が変更されたため中止しました。再読み込みして確認してください。"; return }
        var valid = true
        assets.enumerateObjects { asset, _, _ in
            if asset.isFavorite || snapshot.first(where: { $0.id == asset.localIdentifier })?.modified != asset.modificationDate { valid = false }
        }
        guard valid else { message = "お気に入りや更新された動画が含まれるため中止しました。"; return }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets) }
            let ids = Set(snapshot.map(\.id)); records.removeAll { ids.contains($0.id) }; selected.subtract(ids)
            pendingRefresh = true
            lastAction = "選択した動画の削除を写真ライブラリに反映しました。空き容量への反映はiOS・iCloudの状態に依存します。"
            message = lastAction
        } catch { message = "削除していません：\(error.localizedDescription)" }
    }
}
