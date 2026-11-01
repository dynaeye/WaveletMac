import AppKit
import SwiftUI

/// 自定义「关于 Wavelet」窗口。标准 About 面板只能显示版本与版权，
/// 这里额外提供官网链接和手动检查更新入口。
struct AboutView: View {
    @ObservedObject var store: RadioCatalogStore

    private static let website = URL(string: "https://www.mythmedia.com/wavelet/")!

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("WAVELET")
                    .font(.custom("Space Mono", size: 19).weight(.bold))
                    .tracking(3)
                Text(store.text("面向 macOS 的互联网电台"))
                    .font(.custom("Noto Sans SC", size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("\(store.text("版本")) \(versionText)")
                .font(.custom("Inter", size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()

            Link(destination: Self.website) {
                Label {
                    Text("www.mythmedia.com/wavelet")
                        .font(.custom("Inter", size: 11))
                } icon: {
                    Image(systemName: "globe")
                }
            }

            Button(store.text("检查更新")) { AppUpdater.checkForUpdates() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!AppUpdater.canCheckForUpdates)

            Text("© 2026 Mythmedia")
                .font(.custom("Inter", size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(width: 340)
        .background(.regularMaterial)
    }
}
