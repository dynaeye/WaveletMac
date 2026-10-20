import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LocalMediaLibraryView: View {
    @ObservedObject var store: RadioCatalogStore
    @ObservedObject private var media: LocalMediaStore
    @ObservedObject private var player: PlaybackEngine
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var addSheet: AddSheet?
    @State private var pendingRemoval: MediaSourceRef?
    @State private var hoveredEntryID: String?

    private enum AddSheet: Identifiable {
        case smb(SMBSourceConfig?)
        case upnp

        var id: String {
            switch self {
            case let .smb(config): "smb-\(config?.id ?? "new")"
            case .upnp: "upnp"
            }
        }
    }

    init(store: RadioCatalogStore) {
        self.store = store
        _media = ObservedObject(wrappedValue: store.media)
        _player = ObservedObject(wrappedValue: store.player)
    }

    private func t(_ key: String) -> String { store.text(key) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                sidebar
                    .frame(minWidth: 224, idealWidth: 242, maxWidth: 286)
                content
                    .frame(minWidth: 540, maxWidth: .infinity)
            }
            Divider()
            LocalPlayerBar(store: store)
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $addSheet) { sheet in
            switch sheet {
            case let .smb(config):
                SMBEditorSheet(media: media, existing: config)
            case .upnp:
                UPnPAddSheet(media: media)
            }
        }
        .confirmationDialog(
            t("删除媒体源"),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { source in
            Button(t("删除"), role: .destructive) {
                media.removeSource(source)
                pendingRemoval = nil
            }
            Button(t("取消"), role: .cancel) { pendingRemoval = nil }
        } message: { source in
            Text(source.name)
        }
        .onAppear {
            guard !media.hasSources, !media.isScanningUPnP else { return }
            Task { await media.scanUPnP() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("本地媒体库")).font(.title2.weight(.semibold))
                Text(t("本地媒体文件仅在本机播放，不会上传。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if media.isScanningUPnP {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(t("扫描中…")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await media.scanUPnP() }
            } label: {
                Label(t("扫描 UPnP 设备"), systemImage: "dot.radiowaves.left.and.right")
            }
            .disabled(media.isScanningUPnP)
            Button(t("关闭")) { dismissWindow(id: "localMedia") }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(t("媒体源")).font(.headline)
                Spacer()
                Menu {
                    Button { addSheet = .smb(nil) } label: {
                        Label(t("添加 SMB 服务器…"), systemImage: "externaldrive.badge.plus")
                    }
                    Button { addSheet = .upnp } label: {
                        Label(t("添加 UPnP 服务器…"), systemImage: "network")
                    }
                    Divider()
                    Button { chooseFolder() } label: {
                        Label(t("添加文件夹…"), systemImage: "folder.badge.plus")
                    }
                    Button { chooseAudioFile() } label: {
                        Label(t("打开音频文件…"), systemImage: "music.note")
                    }
                } label: {
                    Label(t("添加"), systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .help(t("添加媒体源"))
                .accessibilityLabel(t("添加媒体源"))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sourceSection("UPnP", media.upnpSourceRefs, emptyKey: "未发现 UPnP 服务器。")
                    sourceSection("SMB", media.smbSourceRefs, emptyKey: "SMB 服务器")
                    sourceSection(t("本地文件夹"), media.folderSourceRefs, emptyKey: "本地文件夹")
                }
                .padding(.vertical, 6)
            }

            if let status = media.statusMessage {
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(status.isError ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
    }

    private func sourceSection(_ title: String, _ sources: [MediaSourceRef], emptyKey: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 2)
            ForEach(sources) { sourceRow($0) }
            if sources.isEmpty {
                Text(t(emptyKey))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
        }
    }

    private func sourceRow(_ source: MediaSourceRef) -> some View {
        Button {
            Task { await media.selectSource(key: source.key) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: source.kind.symbolName)
                    .frame(width: 18)
                    .foregroundStyle(source.kind == .folder ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name).lineLimit(1)
                    Text(source.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if media.isLoading, media.selectedSource?.key == source.key {
                    ProgressView().controlSize(.mini)
                } else if let online = source.isOnline {
                    Circle()
                        .fill(online ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .help(t(online ? "已连接" : "未连接"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                media.selectedSource?.key == source.key ? Color.accentColor.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .help(source.detail)
        .contextMenu {
            if source.kind == .smb, let config = media.smbSources.first(where: { $0.id == source.id }) {
                Button(t("编辑")) { addSheet = .smb(config) }
                if media.mountedSMBIDs.contains(config.id) {
                    Button(t("断开连接")) { media.disconnectSMB(id: config.id) }
                } else {
                    Button(t("重新连接")) {
                        Task { await media.connectSMB(id: config.id) }
                    }
                }
                Divider()
            }
            Button(t("删除媒体源"), role: .destructive) { pendingRemoval = source }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if let error = media.errorMessage {
                errorBanner(error)
            }
            contentHeader
            Divider()
            contentBody
        }
    }

    private var contentHeader: some View {
        HStack(spacing: 10) {
            Button {
                Task { await media.goBack() }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(!media.canGoBack)
            .help(t("返回上级"))
            .accessibilityLabel(t("返回上级"))

            breadcrumbs
            Spacer(minLength: 8)

            if media.selectedSource != nil {
                Text(media.countText("个项目", media.visibleEntries.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(t("搜索当前目录"), text: $media.searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 140)
                Button {
                    Task { await media.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(media.isLoading)
                .help(t("刷新"))
                .accessibilityLabel(t("刷新"))
                Button {
                    media.playAll()
                } label: {
                    Label(t("播放全部"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(media.audioCount == 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                if media.path.isEmpty {
                    Text(media.selectedSource?.name ?? t("媒体库"))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(media.path.enumerated()), id: \.offset) { index, location in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            Task { await media.jump(to: index) }
                        } label: {
                            Text(location.title)
                                .font(index == media.path.count - 1 ? .headline : .callout)
                                .foregroundStyle(index == media.path.count - 1 ? .primary : .secondary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: 240, alignment: .leading)
    }

    @ViewBuilder
    private var contentBody: some View {
        if media.selectedSource == nil {
            ContentUnavailableView {
                Label(t("选择媒体源开始浏览"), systemImage: "externaldrive.connected.to.line.below")
            } description: {
                Text(t("添加一个 SMB 服务器、UPnP 设备或本地文件夹，即可浏览并播放音频。"))
            } actions: {
                Menu(t("添加媒体源")) {
                    Button(t("添加 SMB 服务器…")) { addSheet = .smb(nil) }
                    Button(t("添加 UPnP 服务器…")) { addSheet = .upnp }
                    Button(t("添加文件夹…")) { chooseFolder() }
                    Button(t("打开音频文件…")) { chooseAudioFile() }
                }
                .fixedSize()
            }
        } else if media.isLoading, media.entries.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text(t("正在载入目录…")).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if media.visibleEntries.isEmpty {
            if media.errorMessage == nil {
                ContentUnavailableView {
                    Label(t("未找到音频文件"), systemImage: "music.note.list")
                } description: {
                    Text(media.searchText.isEmpty ? t("当前目录没有音频文件。") : t("没有匹配的项目。"))
                }
            } else {
                Spacer(minLength: 0)
            }
        } else {
            entriesList
        }
    }

    private var entriesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(media.visibleEntries) { entry in
                    entryRow(entry)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 3)
                        .background(
                            media.selectedEntryID == entry.id
                                ? Color.accentColor.opacity(0.12)
                                : (hoveredEntryID == entry.id ? Color.primary.opacity(0.05) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering { hoveredEntryID = entry.id }
                            else if hoveredEntryID == entry.id { hoveredEntryID = nil }
                        }
                        .onTapGesture(count: 2) {
                            Task { await media.open(entry) }
                        }
                        .onTapGesture {
                            media.selectedEntryID = entry.id
                        }
                        .contextMenu {
                            if entry.kind == .container {
                                Button(t("打开")) {
                                    Task { await media.open(entry) }
                                }
                            } else {
                                Button(t("播放")) { media.play(entry) }
                            }
                        }
                    Divider()
                        .padding(.leading, 58)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func entryRow(_ entry: MediaEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind == .container ? "folder.fill" : "music.note")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(entry.kind == .container ? Color.accentColor : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let count = entry.childCount, count > 0 {
                Text(media.countText("个项目", count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let format = entry.format {
                Text(format)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let size = AudioFile.sizeLabel(entry.size) {
                Text(size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let duration = AudioFile.durationLabel(entry.duration) {
                Text(duration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if entry.isPlayable {
                Button {
                    media.play(entry)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.borderless)
                .help(t("播放"))
                .accessibilityLabel(t("播放"))
            } else if entry.kind == .container {
                Button {
                    Task { await media.open(entry) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(t("打开"))
                .accessibilityLabel(t("打开"))
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            Task { await media.open(entry) }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                media.clearError()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(t("关闭"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.10))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = t("选择文件夹")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await media.addFolder(url) }
    }

    private func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.prompt = t("打开")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        media.choosePlaybackFile(url)
    }
}

private struct SMBEditorSheet: View {
    @ObservedObject var media: LocalMediaStore
    let existing: SMBSourceConfig?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var host: String
    @State private var share: String
    @State private var username: String
    @State private var password = ""
    @State private var usesGuest: Bool
    @State private var rememberPassword: Bool
    @State private var errorText: String?

    init(media: LocalMediaStore, existing: SMBSourceConfig?) {
        self.media = media
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _host = State(initialValue: existing?.host ?? "")
        _share = State(initialValue: existing?.share ?? "")
        _username = State(initialValue: existing?.username ?? "")
        _usesGuest = State(initialValue: existing?.usesGuest ?? false)
        _rememberPassword = State(initialValue: existing?.rememberPassword ?? true)
    }

    private func t(_ key: String) -> String { media.text(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? t("添加 SMB 服务器…") : "\(t("编辑")) \(t("SMB 服务器"))")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                field(t("显示名称"), text: $name, hint: t("可选"))
                field(t("服务器地址"), text: $host, hint: t("例如 192.168.1.10 或 nas.local"))
                field(t("共享名称"), text: $share, hint: t("例如 Music"))
                field(t("用户名"), text: $username, hint: "")
                    .disabled(usesGuest)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("密码")).font(.callout.weight(.medium))
                    SecureField(existing == nil ? "" : t("留空表示不更改"), text: $password)
                        .textFieldStyle(.roundedBorder)
                        .disabled(usesGuest)
                }
                Toggle(t("访客访问"), isOn: $usesGuest)
                Toggle(t("记住密码"), isOn: $rememberPassword)
                    .disabled(usesGuest)
            }

            Text(t("密码保存在 macOS 钥匙串中，不会写入电台目录。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(t("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(t("保存并连接"), action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private func field(_ title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            TextField(hint, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        var config = SMBSourceConfig(
            id: existing?.id ?? UUID().uuidString,
            name: name,
            host: host,
            share: share,
            username: username,
            usesGuest: usesGuest,
            rememberPassword: rememberPassword
        )
        if config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.name = ""
        }
        do {
            let saved = try media.saveSMB(config, password: password)
            dismiss()
            Task { await media.selectSource(key: "smb:\(saved.id)") }
        } catch {
            errorText = media.errorText(for: error)
        }
    }
}

private struct UPnPAddSheet: View {
    @ObservedObject var media: LocalMediaStore
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var isAdding = false
    @State private var errorText: String?

    private func t(_ key: String) -> String { media.text(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("手动添加 UPnP 服务器"))
                .font(.title2.weight(.semibold))
            Text(t("设备描述地址"))
                .font(.callout.weight(.medium))
            TextField("http://192.168.1.10:8200/rootDesc.xml", text: $address)
                .textFieldStyle(.roundedBorder)
            Text(t("未发现服务器时，请允许本地网络访问，或手动添加设备描述地址。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if isAdding { ProgressView().controlSize(.small) }
                Spacer()
                Button(t("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(t("添加")) { add() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private func add() {
        isAdding = true
        errorText = nil
        Task {
            let added = await media.addUPnPSource(address: address)
            isAdding = false
            if added {
                dismiss()
            } else {
                errorText = media.errorMessage
            }
        }
    }
}

private struct LocalPlayerBar: View {
    @ObservedObject var store: RadioCatalogStore
    @ObservedObject private var player: PlaybackEngine
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    init(store: RadioCatalogStore) {
        self.store = store
        _player = ObservedObject(wrappedValue: store.player)
    }

    private func t(_ key: String) -> String { store.text(key) }

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let error = player.errorMessage {
                    Text(store.text(error))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            .frame(width: 230, alignment: .leading)

            if player.localTrack != nil {
                Text(AudioFile.durationLabel(scrubValue) ?? "0:00")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .trailing)
                Slider(value: $scrubValue, in: 0...max(player.localDuration, 0.1), onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing { player.seekLocal(to: scrubValue) }
                })
                .disabled(player.localDuration <= 0)
                .accessibilityLabel(t("播放进度"))
                Text(AudioFile.durationLabel(player.localDuration) ?? "--:--")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .leading)
            } else {
                Spacer(minLength: 0)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button { store.step(-1) } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.borderless)
                .help(t("上一首"))
                .accessibilityLabel(t("上一首"))
                .disabled(!player.hasPlayableItem)
                Button { player.toggle() } label: {
                    Image(systemName: player.state.isActive ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(!player.hasPlayableItem)
                .accessibilityLabel(t(player.state.isActive ? "暂停播放" : "开始收听"))
                Button { store.step(1) } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.borderless)
                .help(t("下一首"))
                .accessibilityLabel(t("下一首"))
                .disabled(!player.hasPlayableItem)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
        .onAppear { scrubValue = player.localPosition }
        .onChange(of: player.localPosition) {
            if !isScrubbing { scrubValue = player.localPosition }
        }
        .onChange(of: player.localTrack?.id) {
            scrubValue = 0
        }
    }

    private var artwork: some View {
        Group {
            if let url = player.localTrack?.artworkURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        artworkPlaceholder
                    }
                }
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(t("歌曲封面"))
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07))
            Image(systemName: player.localTrack == nil ? "radio" : "music.note")
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        player.localTrack?.title ?? player.station?.name ?? t("未播放")
    }

    private var subtitle: String {
        if let track = player.localTrack {
            return track.subtitle
        }
        if let station = player.station {
            return store.subtitle(station)
        }
        return t("选择媒体源开始浏览")
    }

    private var statusText: String {
        if player.localTrack != nil {
            return t(player.state == .playing ? "正在播放" : player.state.rawValue)
        }
        return t(player.state.rawValue)
    }
}
