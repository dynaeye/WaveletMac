import AppKit
import SwiftUI

private enum MacDesign {
    static let paper = Color(hex: 0xEDE7DA)
    static let card = Color(hex: 0xF8F4EB)
    static let forest = Color(hex: 0x2E3A2E)
    static let amber = Color(hex: 0xEAB96A)
    static let ink = Color(hex: 0x28281F)
    static let line = Color(hex: 0xDED6C6)
    static let muted = Color(hex: 0x918D80)
    static let bottomLogo: NSImage = {
        guard
            let url = Bundle.main.url(forResource: "wavelet-logo-white3", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else { return NSImage() }
        return image
    }()
}

struct ContentView: View {
    enum Drawer: Equatable { case favorites, directory, settings }

    @ObservedObject var store: RadioCatalogStore
    @ObservedObject private var player: PlaybackEngine
    @State private var drawer: Drawer?
    private let receiverHeight: CGFloat = 542

    init(store: RadioCatalogStore) {
        self.store = store
        player = store.player
    }

    private func t(_ key: String) -> String { store.text(key) }
    private func countText(_ key: String, _ count: Int) -> String {
        MacLocalization.format(key, count: count, language: store.interfaceLanguage)
    }

    var body: some View {
        ZStack(alignment: .top) {
            receiver
                .frame(height: receiverHeight, alignment: .top)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .zIndex(1)

        }
        .frame(height: receiverHeight, alignment: .top)
        .background {
            DrawerWindowPresenter(
                isPresented: drawer != nil,
                height: drawerHeight,
                themePreference: store.themePreference,
                content: AnyView(Group {
                    if let drawer {
                        drawerView(drawer)
                            .environment(\.locale, store.interfaceLocale)
                    }
                })
            )
        }
        .background(TransparentWindowConfigurator(themePreference: store.themePreference))
        .background(Color.clear)
        .containerBackground(.clear, for: .window)
        .environment(\.locale, store.interfaceLocale)
        .alert(t("无法加载电台目录"), isPresented: loadErrorBinding) {
            Button(t("关闭"), role: .cancel) { }
        } message: { Text(t(store.loadError ?? "未知错误")) }
    }

    private var receiver: some View {
        VStack(spacing: 14) {
            HStack {
                Text("WAVELET").font(.custom("Space Mono", size: 15).weight(.bold)).tracking(3)
                Spacer()
                Text("SR-01 / DIGITAL RADIO")
                    .font(.custom("Space Mono", size: 9)).tracking(1)
                    .foregroundStyle(Color(hex: 0x97A28F))
                Rectangle()
                    .fill(Color(hex: 0x97A28F).opacity(0.45))
                    .frame(width: 1, height: 12)
                Button {
                    TransparentWindowConfigurator.configuredWindow?.miniaturize(nil)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(hex: 0x97A28F))
                        .frame(width: 22, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("最小化"))
                .help(t("最小化"))
            }
            .frame(minHeight: 24)

            tuningScreen

            streamSelector

            HStack {
                Button { store.step(-1) } label: {
                    Image(systemName: "backward.end").font(.system(size: 22, weight: .medium)).frame(width: 52, height: 52)
                }
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.state.isActive ? "pause" : "play")
                        .font(.system(size: 27, weight: .semibold)).foregroundStyle(MacDesign.amber)
                        .frame(width: 68, height: 68)
                        .background(Color(hex: 0x222D22), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.1)))
                }
                .disabled(player.station == nil)
                .accessibilityLabel(t(player.state.isActive ? "暂停播放" : "开始收听"))
                Spacer()
                Button { store.step(1) } label: {
                    Image(systemName: "forward.end").font(.system(size: 22, weight: .medium)).frame(width: 52, height: 52)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.1")
                VolumeSlider(player: player, accessibilityTitle: t("音量"))
                    .tint(MacDesign.amber)
                    .environment(\.controlActiveState, .active)
                    .accessibilityLabel(t("音量"))
                Image(systemName: "speaker.wave.2")
            }
            .foregroundStyle(Color(hex: 0x97A28F))

            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)

            HStack(spacing: 9) {
                Circle().fill(player.state == .failed ? .red : MacDesign.amber).frame(width: 7, height: 7)
                Text(t(player.state.rawValue)).font(.custom("Noto Sans SC", size: 12))
                Spacer()
                if let station = player.station {
                    Button { store.toggleFavorite(station) } label: {
                        Label(t("收藏"), systemImage: store.isFavorite(station) ? "star.fill" : "star")
                            .foregroundStyle(store.isFavorite(station) ? MacDesign.amber : Color(hex: 0xC4CDBE))
                    }.buttonStyle(.plain)
                }
                sleepMenu(foreground: Color(hex: 0xC4CDBE))
            }
            .foregroundStyle(Color(hex: 0xC4CDBE))
            .font(.custom("Noto Sans SC", size: 12)).frame(minHeight: 28)

            if let error = player.errorMessage {
                Text(t(error)).font(.custom("Noto Sans SC", size: 11)).foregroundStyle(MacDesign.amber).lineLimit(2)
            }

            HStack(spacing: 6) {
                receiverDrawerButton("我的收藏", icon: "heart.fill", target: .favorites)
                receiverDrawerButton("电台列表", icon: "list.bullet", target: .directory)
                receiverDrawerButton("设置", icon: "gearshape.fill", target: .settings)
                Spacer(minLength: 12)
                Image(nsImage: MacDesign.bottomLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 90, height: 20)
                    .accessibilityLabel("Wavelet")
            }
        }
        .foregroundStyle(MacDesign.card)
        .padding(18)
        .background(MacDesign.forest, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(alignment: .top) {
            WindowDragArea().frame(height: 52).padding(.trailing, 56)
        }
    }

    private var tuningScreen: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("INTERNET RADIO"); Spacer(); Text(statusCode) }
                .font(.custom("Space Mono", size: 9).weight(.bold)).tracking(1)
            Rectangle().fill(MacDesign.ink.opacity(0.25)).frame(height: 1)
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(player.station.map { "\(t($0.regionName)) / \($0.language)" } ?? t("华语广播"))
                    .font(.custom("Noto Sans SC", size: 11))
                Spacer(minLength: 8)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(channelNumber).font(.custom("Inter", size: 30))
                    Text("CH").font(.custom("Space Mono", size: 8).weight(.bold))
                }
            }
            Text(player.station?.name ?? t("选择电台，开始收听"))
                .font(.custom("Noto Sans SC", size: 22).weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                .offset(y: -4)
            VStack(spacing: 7) {
                HStack {
                    ForEach(["01", "03", "06", "09", "12"], id: \.self) { value in
                        Text(value); if value != "12" { Spacer() }
                    }
                }.font(.custom("Space Mono", size: 8))
                GeometryReader { proxy in
                    Canvas { context, size in
                        for tick in 0...36 {
                            let x = CGFloat(tick) / 36 * size.width
                            var path = Path(); path.move(to: CGPoint(x: x, y: tick % 3 == 0 ? 0 : 5)); path.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(path, with: .color(MacDesign.ink.opacity(0.35)), lineWidth: 1)
                        }
                    }
                    Capsule().fill(MacDesign.forest).frame(width: 2, height: 23).offset(x: proxy.size.width * needlePosition, y: -4)
                }.frame(height: 17)
            }
            HStack {
                Text(player.station?.category ?? t("华语广播")); Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(context.date, format: .dateTime.hour().minute()).font(.custom("Space Mono", size: 11))
                }
            }.font(.custom("Noto Sans SC", size: 11))
        }
        .foregroundStyle(Color(hex: 0x493B1F)).padding(15)
        .background(LinearGradient(colors: [Color(hex: 0xF3D293), MacDesign.amber], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var streamSelector: some View {
        HStack(spacing: 10) {
            Label(t("播放线路"), systemImage: "point.3.connected.trianglepath.dotted")
                .font(.custom("Noto Sans SC", size: 12).weight(.medium))
            Spacer()
            if let station = player.station, !station.streams.isEmpty {
                StreamLinePicker(
                    titles: station.streams.enumerated().map { store.lineTitle($0.offset, format: $0.element.format) },
                    selection: player.line,
                    accessibilityTitle: t("播放线路"),
                    onSelect: player.switchLine
                )
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: 190, alignment: .trailing)
            } else { Text(t("暂无线路")).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 12).frame(minHeight: 38)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func receiverDrawerButton(_ title: String, icon: String, target: Drawer) -> some View {
        Button { toggleDrawer(target) } label: {
            Label(t(title), systemImage: icon)
                .font(.custom("Noto Sans SC", size: 11).weight(.medium))
                .padding(.horizontal, 4)
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(drawer == target ? MacDesign.amber : Color(hex: 0xC4CDBE))
    }

    private func toggleDrawer(_ target: Drawer) {
        drawer = drawer == target ? nil : target
    }

    @ViewBuilder private func drawerView(_ drawer: Drawer) -> some View {
        VStack(spacing: 12) {
            drawerHeader(drawer)
            switch drawer {
            case .directory: directoryView
            case .favorites: stationList(store.favoriteStations)
            case .settings: settingsView
            }
        }
        .padding(18)
        .frame(height: drawerHeight, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55))
        )
        .shadow(color: .black.opacity(0.1), radius: 14, y: 5)
    }

    private var directoryView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                TextField(t("搜索电台、地区、城市或分类"), text: $store.searchText)
                    .textFieldStyle(.roundedBorder)
                directoryFilters
                Spacer(minLength: 0)
            }
            .frame(width: 210, alignment: .topLeading)

            Divider()

            stationList(store.filteredStations)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var directoryFilters: some View {
        VStack(spacing: 8) {
            filterPicker("地区", selection: $store.region, options: regionOptions, allTitle: "全部地区")
                .onChange(of: store.region) {
                    store.group = ""
                    store.city = ""
                    store.category = ""
                }
            filterPicker("省市 / 分组", selection: $store.group, options: filterOptions(store.scopedStations.map(\.group)))
                .onChange(of: store.group) { store.city = "" }
            filterPicker(
                "城市",
                selection: $store.city,
                options: filterOptions(store.scopedStations.filter { store.group.isEmpty || $0.group == store.group }.map(\.city))
            )
            filterPicker("节目类型", selection: $store.category, options: filterOptions(store.scopedStations.map(\.category)))
        }
    }

    private var regionOptions: [(value: String, label: String)] {
        Region.all.compactMap { region in
            let label = t(region.name)
            return store.stations.contains { $0.region == region.id } ? (region.id, label) : nil
        }
    }

    private func filterOptions(_ values: [String]) -> [(value: String, label: String)] {
        Array(Set(values.filter { !$0.isEmpty }))
            .sorted(by: Search.before)
            .map { ($0, $0) }
    }

    private func filterPicker(
        _ title: String,
        selection: Binding<String>,
        options: [(value: String, label: String)],
        allTitle: String = "全部"
    ) -> some View {
        HStack(spacing: 6) {
            Text(t(title)).font(.custom("Noto Sans SC", size: 10).weight(.medium)).foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
                .lineLimit(2)
            DirectoryFilterPicker(
                title: t(title),
                options: [(value: "", label: t(allTitle))] + options,
                selection: selection
            )
            .frame(width: 128)
        }
        .padding(.horizontal, 10)
        .frame(width: 210)
        .frame(minHeight: 34)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55))
        )
    }

    private func drawerHeader(_ drawer: Drawer) -> some View {
        HStack {
            Text(drawerTitle(drawer)).font(.custom("Noto Sans SC", size: 16).weight(.bold))
            if drawer == .settings,
               let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("v\(version)")
                    .font(.custom("Inter", size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if drawer == .directory {
                Text(countText("个电台", store.filteredStations.count)).font(.custom("Inter", size: 11)).foregroundStyle(MacDesign.muted)
            }
            Button { self.drawer = nil } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(MacDesign.muted).keyboardShortcut(.cancelAction)
        }
    }

    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsSection("播放") {
                    VStack(spacing: 10) {
                        HStack {
                            Label(t("音量"), systemImage: "speaker.wave.2")
                            VolumeSlider(player: player, accessibilityTitle: t("音量"))
                                .tint(MacDesign.amber)
                                .environment(\.controlActiveState, .active)
                        }
                        Divider()
                        HStack {
                            Label(t("睡眠定时"), systemImage: "timer")
                            Spacer()
                            sleepMenu(foreground: .primary, showsIcon: false, idleTitle: "未设置")
                        }
                        Divider()
                        Toggle(t("启动时自动播放"), isOn: $store.autoplayEnabled)
                    }
                }
                settingsSection("通用") {
                    VStack(spacing: 10) {
                        settingPicker("主题", icon: "sun.max", value: store.themePreference, options: ["浅色", "深色", "跟随系统"], onSelect: store.setTheme)
                        Divider()
                        settingPicker("语言", icon: "character", value: store.languagePreference, options: ["跟随系统", "繁體中文", "简体中文", "英文", "日文", "韩文", "泰文", "西班牙语", "阿拉伯文"], onSelect: store.setLanguage)
                    }
                }
                Divider()
                HStack {
                    Button(t("退出 Wavelet")) {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(t(title)).font(.custom("Noto Sans SC", size: 12).weight(.bold)).foregroundStyle(.secondary)
            content()
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55))
                )
        }
    }

    private func settingPicker(_ title: String, icon: String, value: String, options: [String], onSelect: @escaping @MainActor @Sendable (String) -> Void) -> some View {
        HStack {
            Label(t(title), systemImage: icon); Spacer()
            Picker(t(title), selection: Binding(get: { value }, set: onSelect)) {
                ForEach(options, id: \.self) { Text(t($0)).tag($0) }
            }.labelsHidden().frame(maxWidth: 150)
        }
    }

    private func sleepMenu(foreground: Color, showsIcon: Bool = true, idleTitle: String = "睡眠") -> some View {
        Menu {
            ForEach([30, 60, 120, 180], id: \.self) { minutes in Button(countText("分钟后停止", minutes)) { player.setSleep(minutes: minutes) } }
            if player.sleepDeadline != nil { Divider(); Button(t("取消定时")) { player.cancelSleep() } }
        } label: {
            Group {
                if showsIcon {
                    Label(player.sleepRemaining ?? t(idleTitle), systemImage: "moon")
                } else {
                    Text(player.sleepRemaining ?? t(idleTitle))
                }
            }
            .foregroundStyle(player.sleepDeadline == nil ? foreground : MacDesign.amber)
        }
        .menuStyle(.borderlessButton)
        .tint(player.sleepDeadline == nil ? foreground : MacDesign.amber)
        .environment(\.controlActiveState, .active)
    }

    private func stationList(_ stations: [Station]) -> some View {
        Group {
            if stations.isEmpty {
                ContentUnavailableView(t(drawer == .favorites ? "还没有收藏" : "没有匹配的电台"), systemImage: drawer == .favorites ? "heart" : "magnifyingglass")
            } else {
                List(stations, selection: $store.selectedStationID) { station in
                    HStack(spacing: 10) {
                        Image(systemName: player.station?.id == station.id ? "waveform" : "antenna.radiowaves.left.and.right")
                            .foregroundStyle(player.station?.id == station.id ? MacDesign.amber : MacDesign.muted)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(station.name).font(.custom("Noto Sans SC", size: 12).weight(.medium))
                            Text(store.subtitle(station)).font(.custom("Noto Sans SC", size: 10)).foregroundStyle(MacDesign.muted)
                        }
                        Spacer()
                        Button { store.toggleFavorite(station) } label: {
                            Image(systemName: store.isFavorite(station) ? "heart.fill" : "heart").foregroundStyle(store.isFavorite(station) ? .red : MacDesign.muted)
                        }.buttonStyle(.plain)
                    }
                    .contentShape(Rectangle()).onTapGesture { store.select(station) }.tag(station.id)
                }.listStyle(.inset)
            }
        }
    }

    private var channelNumber: String {
        store.stations.firstIndex { $0.id == player.station?.id }.map { String(format: "%02d", $0 + 1) } ?? "––"
    }
    private var needlePosition: Double {
        guard let index = store.stations.firstIndex(where: { $0.id == player.station?.id }) else { return 0.45 }
        return 0.02 + Double(index) / Double(max(1, store.stations.count - 1)) * 0.94
    }
    private var statusCode: String {
        switch player.state { case .ready: "READY"; case .connecting: "CONNECTING"; case .buffering: "BUFFERING"; case .playing: "LIVE"; case .paused: "PAUSED"; case .failed: "FAILED" }
    }
    private func drawerTitle(_ drawer: Drawer) -> String {
        switch drawer { case .favorites: t("我的收藏"); case .directory: t("电台列表"); case .settings: t("设置") }
    }
    private var drawerHeight: CGFloat {
        let availableHeight = NSScreen.main?.visibleFrame.height ?? 900
        return min(350, max(220, availableHeight - 560))
    }
    private var loadErrorBinding: Binding<Bool> { Binding(get: { store.loadError != nil }, set: { _ in }) }
}


/// Native control bounds stay fixed even when the selected title changes.
private struct DirectoryFilterPicker: NSViewRepresentable {
    let title: String
    let options: [(value: String, label: String)]
    @Binding var selection: String

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        button.cell?.lineBreakMode = .byTruncatingTail
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: 128, height: nsView.intrinsicContentSize.height)
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.values = options.map(\.value)
        let titles = options.map(\.label)
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        button.selectItem(at: options.firstIndex { $0.value == selection } ?? 0)
        button.setAccessibilityLabel(title)
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<String>
        var values: [String] = []
        init(selection: Binding<String>) { self.selection = selection }
        @objc func select(_ sender: NSPopUpButton) {
            guard values.indices.contains(sender.indexOfSelectedItem) else { return }
            selection.wrappedValue = values[sender.indexOfSelectedItem]
        }
    }
}

/// Local state tracks every drag without invalidating the entire receiver.
private struct VolumeSlider: View {
    let player: PlaybackEngine
    let accessibilityTitle: String
    @State private var value: Double
    @State private var isEditing = false

    init(player: PlaybackEngine, accessibilityTitle: String) {
        self.player = player
        self.accessibilityTitle = accessibilityTitle
        _value = State(initialValue: Double(player.volume))
    }

    var body: some View {
        Slider(value: $value, in: 0...1, onEditingChanged: { editing in
            isEditing = editing
            if !editing { player.persistVolume() }
        })
        .accessibilityLabel(accessibilityTitle)
        .onChange(of: value) { _, updated in
            if player.volume != Float(updated) { player.volume = Float(updated) }
        }
        .onReceive(player.volumeChanges) { updated in
            if !isEditing, Float(value) != updated { value = Double(updated) }
        }
    }
}

/// SwiftUI's macOS Menu/Picker replaces label fonts with its own control font.
/// Set the native popup font explicitly so the compact stream label is truly 9 pt.
private struct StreamLinePicker: NSViewRepresentable {
    let titles: [String]
    let selection: Int
    let accessibilityTitle: String
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = NSFont(name: "NotoSansSC-Medium", size: 9) ?? .systemFont(ofSize: 9, weight: .medium)
        button.contentTintColor = NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.92, alpha: 1)
        button.appearance = NSAppearance(named: .darkAqua)
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        button.selectItem(at: min(max(selection, 0), max(0, titles.count - 1)))
        button.setAccessibilityLabel(accessibilityTitle)
        button.invalidateIntrinsicContentSize()
    }

    @MainActor final class Coordinator: NSObject {
        var onSelect: (Int) -> Void
        init(onSelect: @escaping (Int) -> Void) { self.onSelect = onSelect }
        @objc func select(_ sender: NSPopUpButton) { onSelect(sender.indexOfSelectedItem) }
    }
}

private extension Color {
    init(hex: UInt) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
