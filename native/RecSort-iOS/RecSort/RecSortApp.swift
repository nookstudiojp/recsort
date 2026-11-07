import SwiftUI
import Photos
import PhotosUI
import AVKit

@main
struct RecSortApp: App {
    @StateObject private var store = LibraryStore()
    var body: some Scene { WindowGroup { LibraryView().environmentObject(store).task {
        if ProcessInfo.processInfo.arguments.contains("--demo1700") { store.demo(count: 1700) }
        else if ProcessInfo.processInfo.arguments.contains("--demo") { store.demo() }
        else { store.start() }
    } } }
}
struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var order: VideoOrder = .size
    @State private var filter: LibraryFilter = .all
    @State private var query = ""
    @State private var review: [VideoRecord] = []
    @State private var showReview = false
    @State private var showGuide = false
    private let ink = Color(red: 0.21, green: 0.28, blue: 0.18)
    private var shown: [VideoRecord] {
        VideoRules.ordered(store.records.filter { r in
            let decision = store.decisions[r.id]?.value ?? .none
            let matches: Bool
            switch filter {
            case .all: matches = true
            case .keep: matches = decision == .keep || r.favorite
            case .later: matches = decision == .later
            case .candidate: matches = VideoRules.candidate(r, decisions: store.decisions)
            }
            return matches && (query.isEmpty || r.name.localizedCaseInsensitiveContains(query))
        }, by: order)
    }
    private var dueCount: Int { store.records.filter { r in guard let saved = store.decisions[r.id], saved.value == .later else { return false }; return (saved.due ?? .distantPast) <= Date() }.count }
    var body: some View {
        NavigationStack {
            List {
                Section {
                  VStack(alignment: .leading, spacing: 12) {
                    Text("録画を、すっきり。").font(.title2.bold()).foregroundStyle(ink)
                    Text("大切な動画は残して、まずは5本だけ見直そう。動画は外部へ送信しません。")
                    Text(store.isDemo ? "DEMO・実写真への変更なし" : "写真ライブラリ連携・iOS試作版").font(.caption).foregroundStyle(.secondary)
                    HStack { Text("動画 \(store.records.count) 件"); Spacer(); Text("選択 \(store.selected.count) 件") }
                    Text(store.message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("libraryStatus")
                    if store.loading { ProgressView("動画情報を読み込み中") }
                  }
                }
                Section {
                  DisclosureGroup("写真ライブラリ・サンプル") {
                    if !store.isDemo && (store.authorization == .notDetermined || store.authorization == .denied || store.authorization == .restricted) {
                        Button("写真へのアクセスを許可") { Task { await store.authorize() } }
                        if store.authorization == .denied { Link("設定で写真へのアクセスを変更", destination: URL(string: UIApplication.openSettingsURLString)!) }
                    } else {
                        Button(store.isDemo ? "写真ライブラリへ切り替える" : "写真ライブラリを更新") { Task { if store.authorization == .authorized || store.authorization == .limited { store.start() } else { await store.authorize() } } }.disabled(store.deleting)
                        if !store.isDemo && store.authorization == .limited {
                            Button("許可する写真を変更") { if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, let controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController { PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller) } }
                        }
                        if !store.isDemo {
                            Button(store.measuring ? "容量確認を中止（\(store.measured)件済み）" : "この端末の動画の容量を確認") { if store.measuring { store.cancelMeasurement() } else { store.measureLocalSizes() } }.disabled(store.deleting)
                        }
                    }
                    Button("サンプル12件で試す") { store.demo() }.disabled(store.deleting)
                    Button("サンプル1,700件で試す") { store.demo(count: 1700) }.disabled(store.deleting)
                  }
                }
                Section {
                  DisclosureGroup("少しずつ整理・並べ替え") {
                    Button("今日の5本を選ぶ") {
                        store.selected = Set(shown.filter { VideoRules.candidate($0, decisions: store.decisions) }.prefix(5).map(\.id))
                    }
                    if dueCount > 0 { Button("見直し時期になった動画 \(dueCount) 件") { filter = .later; order = .oldest } }
                    Text("「7日後に見直す」の期限はアプリ内に表示します。通知は送りません。").font(.caption).foregroundStyle(.secondary)
                    Picker("表示", selection: $filter) { ForEach(LibraryFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Picker("並べ替え", selection: $order) { ForEach(VideoOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                  }
                }
                Section("\(shown.count) 件を表示") {
                    ForEach(shown) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: row.favorite ? "heart.fill" : "video").foregroundStyle(ink)
                                Text(row.name).font(.headline).lineLimit(2)
                                Spacer()
                                Toggle("\(row.name)を選択", isOn: Binding(get: { store.selected.contains(row.id) }, set: { if $0 { store.selected.insert(row.id) } else { store.selected.remove(row.id) } })).labelsHidden().disabled(!VideoRules.eligible(row, decisions: store.decisions) || store.deleting)
                            }
                            Text("\(VideoRules.size(row.bytes)) ・ 撮影 \(row.created?.formatted(date: .abbreviated, time: .omitted) ?? "不明")").font(.subheadline)
                            Text(row.favorite ? "お気に入り・削除対象外" : store.decisions[row.id]?.value == .keep ? "残す・削除対象外" : VideoRules.reasons(row).joined(separator: " / ")).font(.caption).foregroundStyle(.secondary)
                            if let saved = store.decisions[row.id], saved.value == .later { Text("見直し日：\(saved.due?.formatted(date: .abbreviated, time: .omitted) ?? "未設定")").font(.caption).foregroundStyle(.orange) }
                            HStack {
                                Button("残す") { store.setDecision(.keep, for: row) }.tint(store.decisions[row.id]?.value == .keep ? .green : ink)
                                Button("7日後に見直す") { store.setDecision(.later, for: row) }
                                Menu("その他") {
                                    Button("今日見直す") { store.setDecision(.later, for: row, days: 0) }
                                    Button("判断を解除") { store.setDecision(.none, for: row) }
                                    Button("プレビュー") { Task { await store.preview(row) } }
                                }
                            }.buttonStyle(.borderless).font(.caption).disabled(store.deleting)
                        }.padding(.vertical, 5)
                    }
                }
                Section {
                    Button("削除以外の整理方法") { showGuide = true }
                    Text("容量未確認は0バイトではありません。表示容量は取得できた元動画のファイルサイズで、iPhone全体の使用量や削除後の空き容量と一致するとは限りません。").font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden).background(Color(red: 0.975, green: 0.975, blue: 0.94))
            .navigationTitle("RecSort").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "動画名で検索")
            .safeAreaInset(edge: .bottom) {
                Button("選択した \(store.selected.count) 件を確認") { store.cancelMeasurement(); store.reviewing = true; review = store.records.filter { store.selected.contains($0.id) && VideoRules.eligible($0, decisions: store.decisions) }; showReview = true }
                    .buttonStyle(.borderedProminent).tint(ink).disabled(store.selected.isEmpty || store.deleting).padding().frame(maxWidth: .infinity).background(.regularMaterial)
            }
            .sheet(isPresented: $showReview, onDismiss: { store.finishReview() }) { ReviewView(snapshot: review) }
            .sheet(isPresented: Binding(get: { store.player != nil }, set: { if !$0 { store.player?.pause(); store.player = nil } })) { if let player = store.player { VideoPlayer(player: player) } }
            .sheet(isPresented: $showGuide) { NavigationStack { List {
                Text("迷ったら、削除を急がない") .font(.title2.bold())
                Text("大切な動画は「残す」。迷う動画は見直し日を決めて、少量ずつ確認できます。")
                Text("クラウド・PCへの退避：保存先、費用、転送の手間、バックアップを確認します。同期サービスでは端末での削除がクラウドにも反映される場合があります。")
                Text("圧縮：画質との兼ね合いがあります。RecSortの圧縮・クラウド転送は未実装です。別の手段で作ったコピーを再生確認し、元動画の削除は最後に判断してください。")
                Text("まず確認したいこと：残す理由、許容できる画質、追加費用、整理にかけられる時間。")
            }.navigationTitle("整理方法").toolbar { Button("閉じる") { showGuide = false } } } }
        }.tint(ink)
    }
}
struct ReviewView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let snapshot: [VideoRecord]
    @State private var consent = false
    @State private var confirm = false
    var body: some View {
        NavigationStack {
            List {
                Section("対象 \(snapshot.count) 件") { ForEach(snapshot) { row in VStack(alignment: .leading) { Text(row.name); Text(VideoRules.size(row.bytes)).font(.caption) } } }
                Section {
                    Text(store.isDemo ? "デモの架空データだけを整理します。実際の写真は変更しません。" : "選択した動画を写真ライブラリから削除します。iCloud写真を利用している場合、同期先にも反映されます。空き容量への反映は即時とは限りません。")
                    Toggle("対象の動画を確認しました", isOn: $consent)
                    Button(store.isDemo ? "デモ内で整理する" : "写真から削除する", role: .destructive) { confirm = true }.disabled(!consent || store.deleting)
                    if store.deleting { ProgressView("iOSの確認と処理を待っています") }
                }
            }.navigationTitle("最後に確認")
            .toolbar { Button("戻る") { dismiss() }.disabled(store.deleting) }
            .interactiveDismissDisabled(store.deleting)
            .alert(store.isDemo ? "デモ内で整理しますか？" : "\(snapshot.count)件の動画を削除しますか？", isPresented: $confirm) {
                Button("戻る", role: .cancel) {}
                Button(store.isDemo ? "デモで整理" : "削除を依頼", role: .destructive) { Task { await store.deleteReviewed(snapshot); dismiss() } }
            } message: { Text(store.isDemo ? "実写真には影響しません。" : "アプリ内の確認後、必要に応じてiOSの削除確認が表示されます。お気に入りと「残す」は削除対象外です。") }
        }
    }
}
