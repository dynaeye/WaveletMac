import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: RadioCatalogStore
    @ObservedObject var player: PlaybackEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(player.station?.name ?? "Wavelet")
        Text(player.state.rawValue)
            .foregroundStyle(.secondary)

        Divider()

        Button(player.state.isActive ? "暂停" : "播放") {
            player.toggle()
        }
        .disabled(player.station == nil)

        if let station = player.station {
            Menu("播放线路") {
                ForEach(Array(station.streams.enumerated()), id: \.offset) { index, stream in
                    Button {
                        player.switchLine(index)
                    } label: {
                        Text("线路 \(index + 1) · \(stream.format.uppercased())")
                    }
                }
            }
        }

        Divider()

        Button("显示主窗口") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button("退出 Wavelet") {
            NSApplication.shared.terminate(nil)
        }
    }
}
