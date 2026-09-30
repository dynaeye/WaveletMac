import AppKit
import SwiftUI

struct ContentView: View {
    enum Drawer: Equatable {
        case favorites
        case directory
    }

    @ObservedObject var store: RadioCatalogStore
    @ObservedObject private var player: PlaybackEngine
    @State private var drawer: Drawer?
    @State private var showsPlaybackStatus = false

    init(store: RadioCatalogStore) {
        self.store = store
        player = store.player
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                radioPanel

                if let drawer {
                    Divider()
                    drawerView(drawer)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            if showsPlaybackStatus {
                playbackStatusOverlay
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.snappy(duration: 0.24), value: drawer)
        .alert("无法加载电台目录", isPresented: loadErrorBinding) {
            Button("关闭", role: .cancel) { }
        } message: {
            Text(store.loadError ?? "未知错误")
        }
    }

    private var radioPanel: some View {
        VStack(spacing: 18) {
            HStack {
                Image("WaveletHeaderLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 125, height: 50)
                    .accessibilityLabel("Wavelet")

                Spacer()

                Text(player.state.rawValue)
                    .font(.custom("Space Mono", size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }

            display

            HStack(spacing: 12) {
                drawerButton(title: "我的收藏", systemImage: "heart.fill", drawer: .favorites)

                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.state.isActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(player.station == nil)
                .help(player.state.isActive ? "暂停" : "播放")

                drawerButton(title: "电台列表", systemImage: "list.bullet", drawer: .directory)
            }
        }
        .padding(24)
    }

    private var display: some View {
        VStack(spacing: 6) {
            Text(player.station?.name ?? store.selectedStation?.name ?? "Wavelet")
                .font(.custom("Archivo", size: 24).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(player.station?.subtitle ?? store.selectedStation?.subtitle ?? "选择一个电台")
                .font(.custom("Inter", size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(statusCode)
                .font(.custom("Space Mono", size: 11))
                .tracking(2)
                .foregroundStyle(.orange)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .padding(.horizontal, 20)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.92), Color(red: 0.10, green: 0.12, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .foregroundStyle(.white)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showsPlaybackStatus = true
        }
    }

    private func drawerButton(title: String, systemImage: String, drawer target: Drawer) -> some View {
        Button {
            drawer = drawer == target ? nil : target
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    @ViewBuilder
    private func drawerView(_ drawer: Drawer) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(drawer == .favorites ? "我的收藏" : "电台列表")
                    .font(.custom("Archivo", size: 17).weight(.semibold))
                Spacer()
                if drawer == .directory {
                    Text("\(store.filteredStations.count) 个电台")
                        .font(.custom("Inter", size: 12))
                        .foregroundStyle(.secondary)
                }
                Button {
                    self.drawer = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("关闭抽屉")
            }

            if drawer == .directory {
                TextField("搜索电台、地区、城市或分类", text: $store.searchText)
                    .textFieldStyle(.roundedBorder)
            }

            stationList(drawer == .favorites ? store.favoriteStations : store.filteredStations)
        }
        .padding(20)
        .frame(height: drawerHeight)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func stationList(_ stations: [Station]) -> some View {
        Group {
            if stations.isEmpty {
                ContentUnavailableView(
                    drawer == .favorites ? "还没有收藏" : "没有匹配的电台",
                    systemImage: drawer == .favorites ? "heart" : "magnifyingglass"
                )
            } else {
                List(stations, selection: $store.selectedStationID) { station in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(station.name)
                                .font(.custom("Inter", size: 13).weight(.medium))
                            Text(station.subtitle)
                                .font(.custom("Inter", size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            store.toggleFavorite(station)
                        } label: {
                            Image(systemName: store.isFavorite(station) ? "heart.fill" : "heart")
                                .foregroundStyle(store.isFavorite(station) ? .red : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(store.isFavorite(station) ? "取消收藏" : "收藏")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.select(station) }
                    .tag(station.id)
                }
                .listStyle(.inset)
            }
        }
    }

    private var loadErrorBinding: Binding<Bool> {
        Binding(
            get: { store.loadError != nil },
            set: { _ in }
        )
    }

    private var drawerHeight: CGFloat {
        let availableHeight = NSScreen.main?.visibleFrame.height ?? 900
        return min(310, max(180, availableHeight - 360))
    }

    private var statusCode: String {
        switch player.state {
        case .ready: "READY"
        case .connecting: "CONNECTING"
        case .buffering: "BUFFERING"
        case .playing: "LIVE"
        case .paused: "PAUSED"
        case .failed: "FAILED"
        }
    }

    private var playbackStatusOverlay: some View {
        VStack(spacing: 16) {
            HStack {
                Text("播放状态")
                    .font(.custom("Archivo", size: 18).weight(.semibold))
                Spacer()
                Button {
                    showsPlaybackStatus = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("关闭播放状态")
            }

            Image(systemName: player.state == .failed ? "exclamationmark.triangle.fill" : "waveform")
                .font(.system(size: 36))
                .foregroundStyle(player.state == .failed ? .red : .orange)

            Text(player.state.rawValue)
                .font(.custom("Inter", size: 16).weight(.semibold))
            Text(player.errorMessage ?? player.station?.subtitle ?? "尚未选择电台")
                .font(.custom("Inter", size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let station = player.station, station.streams.count > 1 {
                Picker("线路", selection: Binding(
                    get: { player.line },
                    set: { player.switchLine($0) }
                )) {
                    ForEach(Array(station.streams.enumerated()), id: \.offset) { index, stream in
                        Text("线路 \(index + 1) · \(stream.format.uppercased())").tag(index)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(24)
        .frame(width: 350)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
    }
}
