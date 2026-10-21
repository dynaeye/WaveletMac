import Combine
import Foundation

@MainActor
final class LocalMediaStore: ObservableObject {
    let player: PlaybackEngine

    @Published private(set) var upnpSources: [UPnPSourceConfig] = []
    @Published private(set) var smbSources: [SMBSourceConfig] = []
    @Published private(set) var folderSources: [FolderSourceConfig] = []
    @Published private(set) var selectedSource: MediaSourceRef?
    @Published private(set) var path: [BrowseLocation] = []
    @Published private(set) var entries: [MediaEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isScanningUPnP = false
    @Published private(set) var statusMessage: MediaStatusMessage?
    @Published private(set) var errorMessage: String?
    @Published private(set) var mountedSMBIDs: Set<String> = []
    @Published var searchText = ""
    @Published var selectedEntryID: String?

    private let defaults: UserDefaults
    private let sourcesKey = "wavelet.mac.mediaSources.v1"
    private let client: UPnPClient
    private let mountManager: SMBMountManager
    private var current: ActiveSource?
    private var sessionPasswords: [String: String] = [:]
    private var folderAccessURLs: [URL] = []
    private var browseToken = UUID()

    private enum ActiveSource {
        case upnp(UPnPSourceConfig, UPnPDevice)
        case smb(SMBSourceConfig, URL)
        case folder(FolderSourceConfig, URL)
    }

    init(
        player: PlaybackEngine,
        defaults: UserDefaults = .standard,
        mountManager: SMBMountManager = .shared,
        client: UPnPClient = UPnPClient()
    ) {
        self.player = player
        self.defaults = defaults
        self.mountManager = mountManager
        self.client = client
        loadSources()
        mountedSMBIDs = Set(smbSources.filter { mountManager.isMounted($0.id) }.map(\.id))
    }

    // MARK: Published helpers

    var interfaceLanguage: String {
        let preference = defaults.string(forKey: "wavelet.mac.language.v1") ?? "跟随系统"
        return RadioCatalogStore.resolvedLanguage(preference)
    }

    func text(_ key: String) -> String {
        MacLocalization.text(key, language: interfaceLanguage)
    }

    func countText(_ key: String, _ count: Int) -> String {
        MacLocalization.format(key, count: count, language: interfaceLanguage)
    }

    var upnpSourceRefs: [MediaSourceRef] {
        upnpSources.map {
            MediaSourceRef(
                kind: .upnp,
                id: $0.id,
                name: $0.name,
                detail: "UPnP · \($0.descriptionURL.host ?? "LAN")",
                isOnline: nil
            )
        }
    }

    var smbSourceRefs: [MediaSourceRef] {
        smbSources.map {
            MediaSourceRef(
                kind: .smb,
                id: $0.id,
                name: $0.displayName,
                detail: $0.detail,
                isOnline: mountedSMBIDs.contains($0.id)
            )
        }
    }

    var folderSourceRefs: [MediaSourceRef] {
        folderSources.map {
            MediaSourceRef(
                kind: .folder,
                id: $0.id,
                name: $0.displayName,
                detail: $0.detail,
                isOnline: FileManager.default.fileExists(atPath: $0.path)
            )
        }
    }

    var allSourceRefs: [MediaSourceRef] {
        upnpSourceRefs + smbSourceRefs + folderSourceRefs
    }

    var hasSources: Bool {
        !upnpSources.isEmpty || !smbSources.isEmpty || !folderSources.isEmpty
    }

    var visibleEntries: [MediaEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        let normalized = Search.normalize(query)
        guard !normalized.isEmpty else { return entries }
        return entries.filter {
            let haystack = Search.normalize([$0.name, $0.detail ?? "", $0.format ?? ""].joined(separator: " "))
            return haystack.contains(normalized)
        }
    }

    var audioCount: Int {
        visibleEntries.filter(\.isPlayable).count
    }

    var canGoBack: Bool { path.count > 1 }

    var currentSourceID: String? {
        switch current {
        case let .upnp(config, _): config.id
        case let .smb(config, _): config.id
        case let .folder(config, _): config.id
        case nil: nil
        }
    }

    // MARK: Source selection and browsing

    func selectSource(key: String) async {
        guard let ref = allSourceRefs.first(where: { $0.key == key }) else {
            selectedSource = nil
            isLoading = false
            return
        }
        let token = beginBrowse()
        selectedSource = ref
        searchText = ""
        selectedEntryID = nil
        errorMessage = nil
        statusMessage = nil
        path = []
        entries = []
        current = nil

        switch ref.kind {
        case .upnp:
            await connectUPnP(id: ref.id, token: token)
        case .smb:
            if let config = smbSources.first(where: { $0.id == ref.id }) {
                await connectSMB(config: config, token: token)
            }
        case .folder:
            await connectFolder(id: ref.id, token: token)
        }
    }

    func reload() async {
        guard let current, let location = path.last else { return }
        let token = beginBrowse()
        errorMessage = nil
        switch current {
        case let .upnp(_, device):
            await loadUPnPChildren(device: device, objectID: location.id, token: token)
        case .smb, .folder:
            await loadFileChildren(relativePath: location.id, token: token)
        }
    }

    func goBack() async {
        guard let current, path.count > 1 else { return }
        path.removeLast()
        guard let location = path.last else { return }
        let token = beginBrowse()
        errorMessage = nil
        switch current {
        case let .upnp(_, device):
            await loadUPnPChildren(device: device, objectID: location.id, token: token)
        case .smb, .folder:
            await loadFileChildren(relativePath: location.id, token: token)
        }
    }

    func jump(to index: Int) async {
        guard let current, path.indices.contains(index), index < path.count else { return }
        path = Array(path.prefix(index + 1))
        guard let location = path.last else { return }
        let token = beginBrowse()
        errorMessage = nil
        switch current {
        case let .upnp(_, device):
            await loadUPnPChildren(device: device, objectID: location.id, token: token)
        case .smb, .folder:
            await loadFileChildren(relativePath: location.id, token: token)
        }
    }

    func open(_ entry: MediaEntry) async {
        guard let current else { return }
        if entry.kind == .container {
            path.append(BrowseLocation(id: entry.objectID, title: entry.name))
            let token = beginBrowse()
            errorMessage = nil
            switch current {
            case let .upnp(_, device):
                await loadUPnPChildren(device: device, objectID: entry.objectID, token: token)
            case .smb, .folder:
                await loadFileChildren(relativePath: entry.objectID, token: token)
            }
        } else {
            play(entry)
        }
    }

    func play(_ entry: MediaEntry) {
        guard let current else { return }
        guard entry.isPlayable else {
            errorMessage = text("请选择一个可播放的音频文件。")
            return
        }
        let sourceID: String
        let sourceName: String
        let isNetwork: Bool
        switch current {
        case let .upnp(config, _):
            sourceID = config.id
            sourceName = config.name
            isNetwork = true
        case let .smb(config, _):
            sourceID = config.id
            sourceName = config.displayName
            isNetwork = true
        case let .folder(config, _):
            sourceID = config.id
            sourceName = config.displayName
            isNetwork = false
        }
        let queue = visibleEntries.compactMap { item in
            item.track(sourceID: sourceID, sourceName: sourceName, isNetworkSource: isNetwork)
        }
        guard let track = entry.track(sourceID: sourceID, sourceName: sourceName, isNetworkSource: isNetwork) else {
            errorMessage = text("请选择一个可播放的音频文件。")
            return
        }
        player.playLocal(track, queue: queue)
        errorMessage = nil
    }

    func playAll() {
        guard let first = visibleEntries.first(where: \.isPlayable) else {
            errorMessage = text("此媒体源没有可播放的音频。")
            return
        }
        play(first)
    }

    func choosePlaybackFile(_ url: URL) {
        guard AudioFile.isAudioFile(url) else {
            errorMessage = text("不支持的文件类型。")
            return
        }
        let root = url.deletingLastPathComponent()
        let sourceName = root.lastPathComponent
        let track = LocalAudioTrack(
            id: "manual:\(url.path)",
            title: url.deletingPathExtension().lastPathComponent,
            artist: "",
            album: "",
            url: url,
            artworkURL: nil,
            sourceID: "manual",
            sourceName: sourceName,
            format: AudioFile.formatLabel(for: url),
            durationHint: nil,
            isNetworkSource: false
        )
        player.playLocal(track, queue: [track])
        errorMessage = nil
    }

    // MARK: UPnP

    func scanUPnP() async {
        guard !isScanningUPnP else { return }
        isScanningUPnP = true
        statusMessage = MediaStatusMessage(text: text("正在扫描本地网络…"), isError: false)
        defer { isScanningUPnP = false }
        let devices = await UPnPDiscovery.discover(timeout: 6)
        guard !devices.isEmpty else {
            statusMessage = MediaStatusMessage(
                text: text("未发现 UPnP 服务器。") + "\n" + text("未发现服务器时，请允许本地网络访问，或手动添加设备描述地址。"),
                isError: true
            )
            return
        }
        for device in devices {
            store(device)
        }
        saveSources()
        statusMessage = MediaStatusMessage(
            text: countText("已发现 %d 个 UPnP 服务器。", devices.count),
            isError: false
        )
    }

    @discardableResult
    func addUPnPSource(address: String) async -> Bool {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = text("请输入设备描述地址。")
            return false
        }
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "http://" + value
        }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            errorMessage = text("无法读取设备描述。")
            return false
        }
        do {
            let devices = try await client.fetchDevices(descriptionURL: url)
            guard !devices.isEmpty else {
                throw MediaFailure("未找到 UPnP 内容目录服务。")
            }
            var firstConfig: UPnPSourceConfig?
            for device in devices {
                let config = store(device)
                if firstConfig == nil { firstConfig = config }
            }
            saveSources()
            if let firstConfig {
                await selectSource(key: "upnp:\(firstConfig.id)")
            }
            return true
        } catch {
            present(error, fallback: "无法连接 UPnP 服务器")
            return false
        }
    }

    @discardableResult
    private func store(_ device: UPnPDevice) -> UPnPSourceConfig {
        let id = device.id
        let config = UPnPSourceConfig(
            id: id,
            name: device.name,
            descriptionURL: device.location,
            udn: device.udn,
            lastSeenAt: Date()
        )
        if let index = upnpSources.firstIndex(where: { $0.id == id || ($0.udn != nil && $0.udn == device.udn && $0.name == device.name) }) {
            upnpSources[index] = config
        } else {
            upnpSources.append(config)
        }
        return config
    }

    private func connectUPnP(id: String, token: UUID) async {
        guard let config = upnpSources.first(where: { $0.id == id }) else {
            isLoading = false
            return
        }
        isLoading = true
        defer { if isCurrent(token) { isLoading = false } }
        do {
            let devices = try await client.fetchDevices(descriptionURL: config.descriptionURL)
            guard isCurrent(token) else { return }
            guard let device = devices.first(where: { $0.id == id }) ?? devices.first else {
                throw MediaFailure("未找到 UPnP 内容目录服务。")
            }
            current = .upnp(config, device)
            path = [BrowseLocation(id: "0", title: config.name)]
            await loadUPnPChildren(device: device, objectID: "0", token: token)
        } catch {
            guard isCurrent(token) else { return }
            present(error, fallback: "无法连接 UPnP 服务器")
            path = []
        }
    }

    private func loadUPnPChildren(device: UPnPDevice, objectID: String, token: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { if isCurrent(token) { isLoading = false } }
        do {
            let fetched = try await client.browseAll(device: device, objectID: objectID)
            guard isCurrent(token) else { return }
            let containers = fetched.filter { $0.kind == .container }
            let audio = fetched.filter { $0.kind == .audio }
            entries = containers + audio
            selectedEntryID = nil
        } catch {
            guard isCurrent(token) else { return }
            entries = []
            present(error, fallback: "无法连接 UPnP 服务器")
        }
    }

    // MARK: SMB

    func saveSMB(_ input: SMBSourceConfig, password: String?) throws -> SMBSourceConfig {
        var hostInput = input.host
        var shareInput = input.share
        if SMBAddress.normalizedShare(shareInput) == nil,
           let parsed = SMBAddress.hostAndShare(hostInput),
           let embeddedShare = parsed.share {
            hostInput = parsed.host
            shareInput = embeddedShare
        }
        guard let host = SMBAddress.normalizedHost(hostInput) else {
            throw MediaFailure("SMB 服务器地址不能为空。")
        }
        guard let share = SMBAddress.normalizedShare(shareInput) else {
            throw MediaFailure("SMB 共享名称不能为空。")
        }
        var config = input
        config.host = host
        config.share = share
        config.username = config.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.name = "\(host)/\(share)"
        }
        let isNew = !smbSources.contains { $0.id == config.id }
        if isNew { config.id = UUID().uuidString }
        if !config.usesGuest && config.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MediaFailure("此服务器需要用户名和密码。")
        }

        let suppliedPassword = password
        if let suppliedPassword, !suppliedPassword.isEmpty {
            sessionPasswords[config.id] = suppliedPassword
            if config.rememberPassword {
                try? KeychainStore.setPassword(suppliedPassword, for: config.id)
            }
        } else if !config.rememberPassword {
            KeychainStore.deletePassword(for: config.id)
            sessionPasswords[config.id] = nil
        }

        if isNew {
            smbSources.append(config)
        } else if let index = smbSources.firstIndex(where: { $0.id == config.id }) {
            if player.localTrack?.sourceID == config.id {
                player.clearLocalPlayback()
            }
            smbSources[index] = config
            mountManager.unmountImmediately(config.id)
            mountedSMBIDs.remove(config.id)
        }
        saveSources()
        return config
    }

    func chooseSMBShare(
        host: String,
        username: String,
        password: String?,
        usesGuest: Bool
    ) async throws -> String {
        try await mountManager.chooseShare(
            host: host,
            username: username,
            password: password,
            usesGuest: usesGuest
        )
    }

    func connectSMB(id: String) async {
        guard let config = smbSources.first(where: { $0.id == id }) else { return }
        let token = beginBrowse()
        selectedSource = smbSourceRefs.first { $0.id == id }
        searchText = ""
        selectedEntryID = nil
        path = []
        entries = []
        current = nil
        errorMessage = nil
        statusMessage = nil
        await connectSMB(config: config, token: token)
    }

    private func connectSMB(config: SMBSourceConfig, token: UUID) async {
        isLoading = true
        defer { if isCurrent(token) { isLoading = false } }
        do {
            let password = sessionPasswords[config.id]
                ?? (config.rememberPassword ? KeychainStore.password(for: config.id) : nil)
            let mounted = try await mountManager.mount(config, password: password)
            guard isCurrent(token) else { return }
            mountedSMBIDs.insert(config.id)
            current = .smb(config, mounted)
            path = [BrowseLocation(id: "", title: config.displayName)]
            await loadFileChildren(relativePath: "", token: token)
        } catch {
            guard isCurrent(token) else { return }
            mountedSMBIDs.remove(config.id)
            present(error, fallback: "无法连接 SMB 服务器")
            path = []
        }
    }

    func disconnectSMB(id: String) {
        if player.localTrack?.sourceID == id {
            player.clearLocalPlayback()
        }
        mountManager.unmountImmediately(id)
        mountedSMBIDs.remove(id)
        if currentSourceID == id {
            _ = beginBrowse()
            current = nil
            selectedSource = nil
            path = []
            entries = []
            isLoading = false
        }
        errorMessage = nil
        statusMessage = MediaStatusMessage(text: text("未连接"), isError: false)
    }

    // MARK: Folders

    func addFolder(_ url: URL) async {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            errorMessage = text("本地文件夹无法访问，请重新添加。")
            return
        }
        if let existing = folderSources.first(where: { $0.path == standardized.path }) {
            await selectSource(key: "folder:\(existing.id)")
            return
        }
        let bookmark = try? standardized.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let config = FolderSourceConfig(
            id: UUID().uuidString,
            name: standardized.lastPathComponent,
            path: standardized.path,
            bookmark: bookmark
        )
        folderSources.append(config)
        saveSources()
        await selectSource(key: "folder:\(config.id)")
    }

    private func connectFolder(id: String, token: UUID) async {
        guard let config = folderSources.first(where: { $0.id == id }) else {
            isLoading = false
            return
        }
        let url = resolveFolderURL(config)
        guard FileManager.default.fileExists(atPath: url.path) else {
            present(MediaFailure("本地文件夹无法访问，请重新添加。"), fallback: "本地文件夹无法访问，请重新添加。")
            isLoading = false
            return
        }
        if url.startAccessingSecurityScopedResource() {
            folderAccessURLs.append(url)
        }
        current = .folder(config, url)
        path = [BrowseLocation(id: "", title: config.displayName)]
        await loadFileChildren(relativePath: "", token: token)
    }

    private func resolveFolderURL(_ config: FolderSourceConfig) -> URL {
        if let bookmark = config.bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url.standardizedFileURL
            }
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url.standardizedFileURL
            }
        }
        return URL(fileURLWithPath: config.path).standardizedFileURL
    }

    private func loadFileChildren(relativePath: String, token: UUID) async {
        guard let root = activeRootURL else {
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        defer { if isCurrent(token) { isLoading = false } }
        do {
            let directory = try FileMediaBrowser.resolve(relativePath: relativePath, in: root)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw MediaFailure("无法读取此文件夹。")
            }
            let fetched = try await Task.detached(priority: .userInitiated) {
                try FileMediaBrowser.entries(in: directory, root: root)
            }.value
            guard isCurrent(token) else { return }
            entries = fetched
            selectedEntryID = nil
        } catch {
            guard isCurrent(token) else { return }
            entries = []
            present(error, fallback: "无法读取此文件夹。")
        }
    }

    private var activeRootURL: URL? {
        switch current {
        case let .smb(_, root), let .folder(_, root): root
        case .upnp: nil
        case nil: nil
        }
    }

    // MARK: Removal

    func removeSource(_ ref: MediaSourceRef) {
        if player.localTrack?.sourceID == ref.id {
            player.clearLocalPlayback()
        }
        switch ref.kind {
        case .upnp:
            upnpSources.removeAll { $0.id == ref.id }
        case .smb:
            smbSources.removeAll { $0.id == ref.id }
            KeychainStore.deletePassword(for: ref.id)
            sessionPasswords[ref.id] = nil
            mountManager.unmount(ref.id)
            mountedSMBIDs.remove(ref.id)
        case .folder:
            if let config = folderSources.first(where: { $0.id == ref.id }) {
                let url = resolveFolderURL(config)
                folderAccessURLs.removeAll { $0 == url }
                url.stopAccessingSecurityScopedResource()
            }
            folderSources.removeAll { $0.id == ref.id }
        }

        if currentSourceID == ref.id {
            _ = beginBrowse()
            current = nil
            selectedSource = nil
            path = []
            entries = []
            isLoading = false
        }
        saveSources()
        errorMessage = nil
        statusMessage = MediaStatusMessage(text: text("已移除媒体源。"), isError: false)
    }

    func removeAllSources() {
        _ = beginBrowse()
        if player.localTrack != nil { player.clearLocalPlayback() }
        for source in smbSources {
            mountManager.unmount(source.id)
            KeychainStore.deletePassword(for: source.id)
        }
        for source in folderSources {
            let url = resolveFolderURL(source)
            url.stopAccessingSecurityScopedResource()
        }
        upnpSources = []
        smbSources = []
        folderSources = []
        mountedSMBIDs = []
        current = nil
        selectedSource = nil
        path = []
        entries = []
        isLoading = false
        saveSources()
    }

    // MARK: Persistence

    private func loadSources() {
        guard let data = defaults.data(forKey: sourcesKey),
              let decoded = try? JSONDecoder().decode(PersistedMediaSources.self, from: data) else { return }
        upnpSources = decoded.upnp
        smbSources = decoded.smb
        folderSources = decoded.folders
    }

    private func saveSources() {
        let sources = PersistedMediaSources(upnp: upnpSources, smb: smbSources, folders: folderSources)
        guard let data = try? JSONEncoder().encode(sources) else { return }
        defaults.set(data, forKey: sourcesKey)
    }

    // MARK: Error plumbing

    func clearError() {
        errorMessage = nil
    }

    func clearStatus() {
        statusMessage = nil
    }

    func errorText(for error: Error) -> String {
        if let failure = error as? MediaFailure {
            var message = text(failure.messageKey)
            if failure.messageKey.contains("%d") {
                message = String(format: message, failure.status ?? 0)
            }
            if let detail = failure.detail, !detail.isEmpty {
                message += "\n" + detail
            }
            return message
        }
        return error.localizedDescription
    }

    private func beginBrowse() -> UUID {
        let token = UUID()
        browseToken = token
        return token
    }

    private func isCurrent(_ token: UUID) -> Bool {
        browseToken == token
    }

    private func present(_ error: Error, fallback: String) {
        if error is MediaFailure {
            errorMessage = errorText(for: error)
        } else {
            errorMessage = text(fallback) + "\n" + error.localizedDescription
        }
    }
}
