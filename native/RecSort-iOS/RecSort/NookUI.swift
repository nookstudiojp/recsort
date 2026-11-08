import SwiftUI
import Photos

// Shared brand tokens keep the library, review and export screens consistent.
enum Nook {
    static let paper = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let ink = Color(red: 0.13, green: 0.15, blue: 0.12)
    static let muted = Color(red: 0.40, green: 0.43, blue: 0.36)
    static let lime = Color(red: 0.82, green: 0.96, blue: 0.35)
    static let sage = Color(red: 0.92, green: 0.95, blue: 0.84)
    static let peach = Color(red: 1.0, green: 0.91, blue: 0.84)
    static let line = Color(red: 0.86, green: 0.87, blue: 0.81)
    static let lavender = Color(red: 0.92, green: 0.90, blue: 0.98)
}
struct NookCard<Content: View>: View {
    var fill: Color = .white
    @ViewBuilder var content: Content
    var body: some View { content.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(fill, in: RoundedRectangle(cornerRadius: 23)).overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(Nook.line, lineWidth: 1)) }
}
struct NookButton: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, design: .rounded, weight: .bold)).padding(.horizontal, 16).frame(minHeight: 48).frame(maxWidth: .infinity)
            .foregroundStyle(prominent ? Nook.paper : Nook.ink)
            .background(prominent ? Nook.ink : Nook.sage, in: RoundedRectangle(cornerRadius: 16))
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.38)
    }
}
struct NookBadge: View {
    let label: String
    var color = Nook.sage
    var body: some View { Text(label).font(.system(.caption2, design: .rounded, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 6).background(color, in: Capsule()).foregroundStyle(Nook.ink) }
}
struct NookPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { content }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity) }.background(Nook.paper).foregroundStyle(Nook.ink) }
}
struct VideoThumbnail: View {
    let record: VideoRecord
    let demo: Bool
    @State private var thumbnail: UIImage?
    @State private var request: PHImageRequestID?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15).fill(Nook.sage)
            if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill().frame(width: 78, height: 78).clipped() }
            else { Image(systemName: demo ? "play.rectangle.fill" : "video").font(.system(size: 25)).foregroundStyle(Nook.ink.opacity(0.6)) }
            VStack { Spacer(); HStack { Spacer(); Text(String(format: "%d:%02d", Int(record.duration)/60, Int(record.duration)%60)).font(.system(size: 10, weight: .bold, design: .monospaced)).padding(4).foregroundStyle(.white).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5)) }.padding(5) }
        }.frame(width: 78, height: 78).clipShape(RoundedRectangle(cornerRadius: 15)).accessibilityHidden(true)
        .onAppear {
            guard !demo, request == nil, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [record.id], options: nil).firstObject else { return }
            let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = false; options.deliveryMode = .opportunistic; options.resizeMode = .fast
            request = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 180, height: 180), contentMode: .aspectFill, options: options) { image, info in
                guard info?[PHImageCancelledKey] as? Bool != true else { return }
                Task { @MainActor in thumbnail = image }
            }
        }
        .onDisappear { if let request { PHImageManager.default().cancelImageRequest(request) }; request = nil }
    }
}
