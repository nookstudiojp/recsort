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
    @State private var showLibrary = false
    @State private var mediaRow: VideoRecord?
    private var shown: [VideoRecord] {
        VideoRules.ordered(store.records.filter { row in
            matches(row, filter) && (query.isEmpty || row.name.localizedCaseInsensitiveContains(query))
        }, by: order)
    }
    private func matches(_ row: VideoRecord, _ view: LibraryFilter) -> Bool {
        let decision = store.decisions[row.id]?.value ?? .none
        switch view {
        case .all: return true
        case .keep: return decision == .keep || row.favorite
        case .later: return decision == .later
        case .candidate: return VideoRules.candidate(row, decisions: store.decisions)
        }
    }
    private var candidates: Int { store.records.filter { matches($0, .candidate) }.count }
    private var dueCount: Int { store.records.filter { r in guard let saved = store.decisions[r.id], saved.value == .later else { return false }; return (saved.due ?? .distantPast) <= Date() }.count }
    private var knownBytes: Int64 { store.records.compactMap(\.bytes).reduce(0, +) }
    private var knownCount: Int { store.records.filter { $0.bytes != nil }.count }
    private var selectedRows: [VideoRecord] { store.records.filter { store.selected.contains($0.id) && VideoRules.eligible($0, decisions: store.decisions) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    hero
                    summary
                    todayCard
                    libraryControls
                    if store.loading { ProgressView("動画情報を読み込み中").frame(maxWidth: .infinity) }
                    if shown.isEmpty { emptyState }
                    ForEach(shown) { row in videoCard(row) }
                    Button { showGuide = true } label: { Label("削除以外の方法も、見てみよう", systemImage: "sparkles") }.buttonStyle(NookButton())
                    VStack(alignment: .leading, spacing: 8) {
                        Label("候補は「不要」という意味ではありません。", systemImage: "info.circle")
                        Text("容量未確認は0バイトではありません。取得できた元動画のサイズを表示し、iPhone全体の使用量や削除後の空き容量は保証しません。")
                        Text("nook. STUDIO  /  iOS PROTOTYPE").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4).padding(.top, 8)
                    }.font(.caption).foregroundStyle(Nook.muted).padding(.vertical, 8)
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(Nook.paper).foregroundStyle(Nook.ink)
            .navigationTitle("RecSort").navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .topBarTrailing) { Button { showLibrary = true } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .semibold)) }.accessibilityLabel("写真ライブラリ・サンプル") }
            }
            .toolbarBackground(Nook.paper, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { selectionBar }
            .sheet(item: $mediaRow, onDismiss: { store.clearExport(); store.finishReview() }) { row in MediaToolsView(record: row) }
            .sheet(isPresented: $showReview, onDismiss: { store.finishReview() }) { ReviewView(snapshot: review) }
            .sheet(isPresented: Binding(get: { store.player != nil }, set: { if !$0 { store.player?.pause(); store.player = nil } })) { if let player = store.player { VideoPlayer(player: player) } }
            .sheet(isPresented: $showGuide) { GuideView() }
            .sheet(isPresented: $showLibrary) { librarySheet }
        }.tint(Nook.ink)
    }
    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("nook. STUDIO / YOUR VIDEO SHELF").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(Nook.muted)
                Text("録画を、\nすっきり。").font(.system(.largeTitle, design: .rounded, weight: .heavy)).tracking(-1)
                Text("大切なものは残して、\nあとは、あなたのペースで。").font(.subheadline).foregroundStyle(Nook.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image("RecSortMark").resizable().scaledToFit().frame(width: 90, height: 90).clipShape(RoundedRectangle(cornerRadius: 24)).rotationEffect(.degrees(5)).accessibilityHidden(true)
        }.padding(.vertical, 2)
    }
    private var summary: some View {
        HStack(spacing: 10) {
            metric("動画", value: "\(store.records.count)", suffix: "本", color: .white)
            metric("確認済み容量", value: knownCount == 0 ? "—" : VideoRules.size(knownBytes), suffix: "\(knownCount)本分", color: Nook.sage)
            metric("整理候補", value: "\(candidates)", suffix: "本", color: Nook.peach)
        }.accessibilityElement(children: .contain)
    }
    private func metric(_ title: String, value: String, suffix: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(.caption2, weight: .medium)).foregroundStyle(Nook.muted)
            Text(value).font(.system(.title3, design: .rounded, weight: .heavy)).minimumScaleFactor(0.7).lineLimit(1)
            Text(suffix).font(.caption2).foregroundStyle(Nook.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(13).background(color, in: RoundedRectangle(cornerRadius: 19)).overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(Nook.line, lineWidth: 1)).accessibilityElement(children: .combine)
    }
    private var todayCard: some View {
        NookCard(fill: Nook.lime.opacity(0.30)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) { Text("まずは、5本だけ。").font(.system(.headline, design: .rounded, weight: .bold)); Text("一度に全部、決めなくていい。").font(.caption).foregroundStyle(Nook.muted) }
                    Spacer(); Image(systemName: "sparkles").font(.title2)
                }
                Button {
                    store.selected = Set(shown.filter { VideoRules.candidate($0, decisions: store.decisions) }.prefix(5).map(\.id))
                } label: { HStack { Text("今日の5本を選ぶ"); Spacer(); Image(systemName: "arrow.up.right") } }.buttonStyle(NookButton(prominent: true)).disabled(!shown.contains { VideoRules.candidate($0, decisions: store.decisions) } || store.deleting || store.mediaBusy)
                if dueCount > 0 { Button("見直し時期になった動画 \(dueCount) 件 →") { filter = .later; order = .oldest }.font(.caption.bold()).frame(minHeight: 36) }
            }
        }
    }
    private var libraryControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ライブラリ").font(.system(.title3, design: .rounded, weight: .bold)); Spacer()
                NookBadge(label: store.isDemo ? "サンプル" : "写真と連携", color: store.isDemo ? Nook.lavender : Nook.sage)
                Menu { Picker("並べ替え", selection: $order) { ForEach(VideoOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) } } } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 44, height: 44) }.accessibilityLabel("並べ替え")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(LibraryFilter.allCases, id: \.self) { item in
                    Button { filter = item } label: {
                        Text("\(item.rawValue) \(store.records.filter { matches($0, item) }.count)").font(.system(.caption, weight: .semibold)).padding(.horizontal, 14).frame(minHeight: 44).foregroundStyle(filter == item ? Nook.paper : Nook.ink).background(filter == item ? Nook.ink : Color.white, in: Capsule()).overlay(Capsule().strokeBorder(Nook.line, lineWidth: filter == item ? 0 : 1))
                    }.accessibilityAddTraits(filter == item ? .isSelected : [])
                } }
            }
            HStack(spacing: 10) { Image(systemName: "magnifyingglass").foregroundStyle(Nook.muted); TextField("動画名で検索", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled(); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("検索を消す") } }.font(.subheadline).padding(13).background(.white, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Nook.line, lineWidth: 1))
            HStack { Text("\(shown.count)本 · \(order.rawValue)"); Spacer(); if !store.selected.isEmpty { Button("選択解除") { store.selected.removeAll() }.frame(minHeight: 30) } }.font(.caption).foregroundStyle(Nook.muted)
        }
    }
    private func videoCard(_ row: VideoRecord) -> some View {
        let kept = row.favorite || store.decisions[row.id]?.value == .keep
        let later = store.decisions[row.id]?.value == .later
        let selected = store.selected.contains(row.id)
        return NookCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 12) {
                    Button { Task { await store.preview(row) } } label: { VideoThumbnail(record: row, demo: store.isDemo) }.buttonStyle(.plain).accessibilityLabel("\(row.name)をプレビュー")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.name).font(.system(.subheadline, weight: .bold)).lineLimit(2)
                        Text(VideoRules.size(row.bytes)).font(.system(.headline, design: .rounded, weight: .bold))
                        Text("撮影 \(row.created?.formatted(date: .abbreviated, time: .omitted) ?? "不明")").font(.caption2).foregroundStyle(Nook.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { if selected { store.selected.remove(row.id) } else { store.selected.insert(row.id) } } label: { Image(systemName: selected ? "checkmark.circle.fill" : kept ? "lock.circle" : "circle").font(.system(size: 26)).foregroundStyle(selected ? Nook.ink : Nook.muted).frame(width: 44, height: 44) }.buttonStyle(.plain).disabled(!VideoRules.eligible(row, decisions: store.decisions) || store.deleting).accessibilityLabel("\(row.name)を選択").accessibilityValue(kept ? "保護されています" : selected ? "選択済み" : "未選択")
                }
                if kept { NookBadge(label: row.favorite ? "♡ お気に入り・削除対象外" : "♡ 残す・削除対象外", color: Nook.sage) }
                else if later, let saved = store.decisions[row.id] { NookBadge(label: "見直す日：\(saved.due?.formatted(date: .abbreviated, time: .omitted) ?? "未設定")", color: Nook.lavender) }
                else if !VideoRules.reasons(row).isEmpty { Text(VideoRules.reasons(row).joined(separator: " · ")).font(.caption).foregroundStyle(Nook.muted) }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { decisionButtons(row, kept: kept); Spacer(minLength: 0); moreMenu(row) }
                    VStack(alignment: .leading, spacing: 8) { decisionButtons(row, kept: kept); moreMenu(row) }
                }.disabled(store.deleting || store.mediaBusy)
            }
        }.overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(selected ? Nook.ink : .clear, lineWidth: 2))
    }
    @ViewBuilder private func decisionButtons(_ row: VideoRecord, kept: Bool) -> some View {
        Button { store.setDecision(kept && !row.favorite ? .none : .keep, for: row) } label: { Label(kept ? "残す ✓" : "残す", systemImage: "heart").font(.caption.bold()).padding(.horizontal, 12).frame(minHeight: 44).background(kept ? Nook.sage : Nook.paper, in: Capsule()) }.buttonStyle(.plain).disabled(row.favorite)
        Button { store.setDecision(.later, for: row) } label: { Label("7日後", systemImage: "clock").font(.caption.bold()).padding(.horizontal, 12).frame(minHeight: 44).background(Nook.paper, in: Capsule()) }.buttonStyle(.plain).disabled(row.favorite).accessibilityLabel("\(row.name)を7日後に見直す")
    }
    private func moreMenu(_ row: VideoRecord) -> some View {
        Menu {
            Button("今日見直す") { store.setDecision(.later, for: row, days: 0) }.disabled(row.favorite)
            Button("判断を解除") { store.setDecision(.none, for: row) }
            Button("プレビュー") { Task { await store.preview(row) } }
            Button("圧縮・書き出し・共有") { store.reviewing = true; mediaRow = row }
        } label: { Image(systemName: "ellipsis").font(.headline).frame(width: 44, height: 44).background(Nook.paper, in: Circle()) }.accessibilityLabel("\(row.name)のその他の操作")
    }
    private var emptyState: some View {
        NookCard {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: store.records.isEmpty ? "photo.stack" : "checkmark.seal").font(.largeTitle)
                Text(store.records.isEmpty ? "あなたの動画棚を、ここに。" : "この条件の動画はありません。").font(.headline)
                Text(store.records.isEmpty ? "写真へのアクセスを許可するか、サンプルで気軽に試してみましょう。" : "検索や表示を変えて、ほかの動画を見てみましょう。").font(.subheadline).foregroundStyle(Nook.muted)
                Button(store.records.isEmpty ? "写真ライブラリ・サンプル" : "すべての動画を見る") { if store.records.isEmpty { showLibrary = true } else { filter = .all; query = "" } }.buttonStyle(NookButton(prominent: true))
            }
        }
    }
    private var selectionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) { Text("\(selectedRows.count)本を選択").font(.system(.subheadline, weight: .bold)); Text("自動では削除しません").font(.caption2).foregroundStyle(Nook.muted) }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                store.cancelMeasurement(); store.reviewing = true; review = selectedRows; showReview = true
            } label: { HStack { Text("確認する"); Image(systemName: "arrow.right") } }.buttonStyle(NookButton(prominent: true)).disabled(selectedRows.isEmpty || store.deleting || store.mediaBusy)
        }.padding(.horizontal, 20).padding(.vertical, 12).background(Nook.paper).overlay(alignment: .top) { Rectangle().fill(Nook.line).frame(height: 1) }
    }
    private var librarySheet: some View {
        NavigationStack {
            NookPage {
                Text("動画棚を、つなぐ。").font(.system(.title, design: .rounded, weight: .bold))
                NookCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("写真ライブラリ", systemImage: "photo.on.rectangle.angled").font(.headline)
                        Text(store.message).font(.subheadline).foregroundStyle(Nook.muted).accessibilityIdentifier("libraryStatus")
                        if !store.isDemo && (store.authorization == .notDetermined || store.authorization == .denied || store.authorization == .restricted) {
                            Button("写真へのアクセスを許可") { Task { await store.authorize() } }.buttonStyle(NookButton(prominent: true))
                            if store.authorization == .denied { Link("設定で写真へのアクセスを変更", destination: URL(string: UIApplication.openSettingsURLString)!) }
                        } else {
                            Button(store.isDemo ? "写真ライブラリへ切り替える" : "写真ライブラリを更新") { Task { if store.authorization == .authorized || store.authorization == .limited { store.start() } else { await store.authorize() } } }.buttonStyle(NookButton(prominent: true)).disabled(store.deleting || store.mediaBusy)
                            if !store.isDemo && store.authorization == .limited { Button("許可する写真を変更") { if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, let controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController?.presentedViewController { PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller) } }.buttonStyle(NookButton()) }
                            if !store.isDemo {
                                Button(store.measuring ? "容量確認を中止（\(store.measured)件済み）" : "この端末の動画の容量を確認") { if store.measuring { store.cancelMeasurement() } else { store.measureLocalSizes() } }.buttonStyle(NookButton()).disabled(store.deleting || store.mediaBusy)
                                if store.measuring { ProgressView("容量確認中：\(store.measured) / \(store.records.count)本") }
                            }
                        }
                        Text("動画は外部へ送信しません。容量確認やサムネイル表示のために、iCloudから自動ダウンロードしません。").font(.caption).foregroundStyle(Nook.muted)
                    }
                }
                NookCard(fill: Nook.lavender.opacity(0.55)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("まずは、気軽にお試し。").font(.headline)
                        Text("サンプルは架空の動画です。実際の写真は変更しません。").font(.caption)
                        Button("サンプル12件で試す") { store.demo(); showLibrary = false }.buttonStyle(NookButton()).disabled(store.deleting || store.mediaBusy)
                        Button("サンプル1,700件で試す") { store.demo(count: 1700); showLibrary = false }.font(.subheadline.bold()).frame(minHeight: 44).disabled(store.deleting || store.mediaBusy)
                    }
                }
                Text("iOS試作版 · 実機検証・一般配布は今後の予定です。").font(.caption).foregroundStyle(Nook.muted)
            }.navigationTitle("ライブラリ設定").navigationBarTitleDisplayMode(.inline).toolbar { Button("閉じる") { showLibrary = false } }
        }.tint(Nook.ink)
    }
}
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            NookPage {
                Text("残し方も、選べる。").font(.system(.largeTitle, design: .rounded, weight: .bold))
                guide("heart", "大切なら、残す。", "「残す」と写真のお気に入りは削除対象外。迷う動画は見直し日を決めて、少量ずつ確認できます。", Nook.sage)
                guide("arrow.down.right.and.arrow.up.left", "小さなコピーで、残す。", "「その他」から圧縮コピーを作れます。画質や音声を確認してから写真へ保存。元動画は自動削除しません。", Nook.lavender)
                guide("square.and.arrow.up", "保存先を、自分で選ぶ。", "共有から「ファイルに保存」などを選べます。費用や通信量、バックアップを確認し、保存先で再生してください。同期サービスでは削除が他の端末にも反映される場合があります。", Nook.peach)
                Text("見直し期限はアプリ内の表示です。通知や自動削除は行いません。").font(.caption).foregroundStyle(Nook.muted)
            }.navigationTitle("整理のヒント").navigationBarTitleDisplayMode(.inline).toolbar { Button("閉じる") { dismiss() } }
        }.tint(Nook.ink)
    }
    private func guide(_ symbol: String, _ title: String, _ body: String, _ color: Color) -> some View {
        NookCard(fill: color.opacity(0.6)) { VStack(alignment: .leading, spacing: 12) { Image(systemName: symbol).font(.title2); Text(title).font(.title3.bold()); Text(body).font(.subheadline).foregroundStyle(Nook.muted) } }
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
            NookPage {
                NookBadge(label: "最後は、あなたの判断で。")
                Text("整理する前に、\n確認を。").font(.system(.largeTitle, design: .rounded, weight: .bold))
                NookCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("対象 \(snapshot.count)本").font(.headline)
                        ForEach(snapshot) { row in HStack { Text(row.name).font(.subheadline).lineLimit(2); Spacer(); Text(VideoRules.size(row.bytes)).font(.caption).foregroundStyle(Nook.muted) } }
                    }
                }
                NookCard(fill: Nook.peach.opacity(0.6)) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(store.isDemo ? "サンプルだけを整理" : "写真ライブラリから削除", systemImage: "exclamationmark.circle").font(.headline)
                        Text(store.isDemo ? "架空のデータだけを整理します。実際の写真は変更しません。" : "iCloud写真を利用している場合は同期先にも反映されます。空き容量への反映は即時とは限りません。").font(.subheadline)
                        Text("お気に入りと「残す」は対象外です。").font(.caption)
                    }
                }
                Toggle("対象の動画を確認しました", isOn: $consent).tint(Nook.ink).padding(.vertical, 8)
                Button(store.isDemo ? "デモ内で整理する" : "写真から削除する", role: .destructive) { confirm = true }.buttonStyle(.borderedProminent).tint(Color(red: 0.67, green: 0.22, blue: 0.19)).frame(maxWidth: .infinity).controlSize(.large).disabled(!consent || store.deleting)
                if store.deleting { ProgressView("iOSの確認と処理を待っています") }
            }.navigationTitle("最後に確認").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("戻る") { dismiss() }.disabled(store.deleting || store.mediaBusy) }
            .interactiveDismissDisabled(store.deleting)
            .alert(store.isDemo ? "デモ内で整理しますか？" : "\(snapshot.count)件の動画を削除しますか？", isPresented: $confirm) {
                Button("戻る", role: .cancel) {}
                Button(store.isDemo ? "デモで整理" : "削除を依頼", role: .destructive) { Task { await store.deleteReviewed(snapshot); dismiss() } }
            } message: { Text(store.isDemo ? "実写真には影響しません。" : "アプリ内の確認後、必要に応じてiOSの削除確認が表示されます。お気に入りと「残す」は削除対象外です。") }
        }.tint(Nook.ink)
    }
}
struct ShareVideoItem: Identifiable { let id = UUID(); let url: URL }
struct VideoShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in Task { @MainActor in completion() } }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
struct MediaToolsView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let record: VideoRecord
    @State private var quality: ExportQuality = .balanced
    @State private var allowNetwork = false
    @State private var shareItem: ShareVideoItem?
    @State private var saveConfirm = false
    @State private var previewPlayer: AVPlayer?
    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("書き出し方法", selection: $quality) { ForEach(ExportQuality.allCases) { Text($0.rawValue).tag($0) } }.disabled(store.mediaBusy)
            Toggle("iCloudからの取得を許可", isOn: $allowNetwork).disabled(store.mediaBusy).tint(Nook.ink)
            Text("許可した場合のみ、必要に応じて通信します。").font(.caption).foregroundStyle(Nook.muted)
            Button { previewPlayer?.pause(); Task { await store.prepareExport(record, quality: quality, allowNetwork: allowNetwork) } } label: { Label("コピーを作る", systemImage: "arrow.down.right.and.arrow.up.left") }.buttonStyle(NookButton(prominent: true)).disabled(store.mediaBusy || store.isDemo)
            if store.mediaBusy { ProgressView(store.savingExport ? "写真へコピーを保存中" : "処理中・元動画は残ります"); if !store.savingExport { Button("中止") { store.cancelExport() }.frame(minHeight: 44) } }
        }
    }
    var body: some View {
        NavigationStack {
            NookPage {
                NookBadge(label: "元動画は、そのまま。", color: Nook.lavender)
                Text("小さくして、\n大切に残す。").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(record.name).font(.subheadline.bold()).lineLimit(2)
                if let result = store.exportResult {
                    NookCard(fill: Nook.sage) {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("コピーができました", systemImage: "checkmark.circle.fill").font(.headline)
                            HStack { VStack(alignment: .leading, spacing: 6) { Text("元動画").font(.caption); Text(VideoRules.size(result.before)).font(.title3.bold()) }; Spacer(); Image(systemName: "arrow.right"); Spacer(); VStack(alignment: .leading, spacing: 6) { Text("コピー").font(.caption); Text(VideoRules.size(result.after)).font(.title3.bold()) } }
                            if let player = previewPlayer { VideoPlayer(player: player).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 15)) }
                            Text(store.exportMessage).font(.caption).foregroundStyle(Nook.muted).accessibilityIdentifier("exportStatus")
                        }
                    }.task(id: result.id) { previewPlayer?.pause(); previewPlayer = AVPlayer(url: result.url) }
                    NookCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("残す場所を、選ぼう。").font(.headline)
                            Button { saveConfirm = true } label: { Label(store.exportSaved ? "写真に保存済み" : "コピーを写真に保存", systemImage: store.exportSaved ? "checkmark" : "photo.badge.plus") }.buttonStyle(NookButton(prominent: true)).disabled(store.mediaBusy || store.exportSaved)
                            Button { previewPlayer?.pause(); shareItem = ShareVideoItem(url: result.url) } label: { Label("共有・ファイルへ保存", systemImage: "square.and.arrow.up") }.buttonStyle(NookButton()).disabled(store.mediaBusy)
                            if store.savingExport { ProgressView("写真へコピーを保存中") }
                        }
                    }
                    NookCard { DisclosureGroup("設定を変えて再実行") { settings.padding(.top, 16) } }
                } else {
                    NookCard { settings }
                    Text(store.exportMessage).font(.subheadline).foregroundStyle(Nook.muted).accessibilityIdentifier("exportStatus")
                }
                Text("画質・色・音声・メタデータが変わる場合があります。コピーを再生して確認してください。保存だけでは空き容量は増えず、元動画も自動削除しません。").font(.caption).foregroundStyle(Nook.muted)
                if store.isDemo { Text("サンプルには実動画がないため、コピー作成は写真ライブラリの動画で使えます。").font(.caption).foregroundStyle(Nook.muted) }
            }.navigationTitle("元動画を残して整理").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("閉じる") { previewPlayer?.pause(); dismiss() }.disabled(store.mediaBusy) }
            .onDisappear { previewPlayer?.pause() }
            .interactiveDismissDisabled(store.mediaBusy || shareItem != nil)
            .sheet(item: $shareItem) { item in VideoShareSheet(url: item.url) { shareItem = nil } }
            .alert("コピーを写真に保存しますか？", isPresented: $saveConfirm) {
                Button("戻る", role: .cancel) {}
                Button("コピーを保存") { Task { await store.saveExportToPhotos() } }
            } message: { Text("元動画は残ります。コピーが増えるため、保存直後は使用容量が増えます。") }
        }.tint(Nook.ink)
    }
}
