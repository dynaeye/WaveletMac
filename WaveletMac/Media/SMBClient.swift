import Darwin
import Foundation
import NetFS
import Security

// MARK: - Keychain

enum KeychainStore {
    static let service = "com.mythmedia.waveletmac.smb"

    static func setPassword(_ password: String, for account: String) throws {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    static func password(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    struct KeychainError: Error {
        let status: OSStatus
    }
}

// MARK: - SMB addresses

enum SMBAddress {
    /// Accepts `host`, `host/share`, or `smb://user@host/share` and returns the host.
    static func normalizedHost(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.lowercased().hasPrefix("smb://") {
            value = String(value.dropFirst("smb://".count))
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        if let at = value.lastIndex(of: "@") {
            value = String(value[value.index(after: at)...])
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return value.isEmpty ? nil : value
    }

    /// Splits a full SMB URL such as `smb://user@host/share` into host and share.
    static func hostAndShare(_ raw: String) -> (host: String, share: String?)? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.lowercased().hasPrefix("smb://") {
            value = String(value.dropFirst("smb://".count))
        }
        let hostPart: String
        var sharePart: String?
        if let slash = value.firstIndex(of: "/") {
            hostPart = String(value[..<slash])
            var path = String(value[value.index(after: slash)...])
            path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let next = path.firstIndex(of: "/") { path = String(path[..<next]) }
            sharePart = normalizedShare(path)
        } else {
            hostPart = value
        }
        guard let host = normalizedHost(hostPart) else { return nil }
        return (host, sharePart)
    }

    static func normalizedShare(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !value.isEmpty, !value.contains("/") else { return nil }
        return value
    }

    static func shareURL(host rawHost: String, share rawShare: String) -> URL? {
        guard let hostValue = normalizedHost(rawHost),
              let share = normalizedShare(rawShare) else { return nil }

        var host = hostValue
        var port: Int?
        if host.hasPrefix("[") {
            guard let closing = host.firstIndex(of: "]") else { return nil }
            let literal = String(host[host.index(after: host.startIndex)..<closing])
            host = literal
            let remainder = hostValue[hostValue.index(after: closing)...]
            if remainder.hasPrefix(":") { port = Int(remainder.dropFirst()) }
        } else if host.filter({ $0 == ":" }).count == 1,
                  let colon = host.lastIndex(of: ":"),
                  let parsed = Int(host[host.index(after: colon)...]) {
            port = parsed
            host = String(host[..<colon])
        }

        var components = URLComponents()
        components.scheme = "smb"
        components.host = host
        components.port = port
        components.path = "/" + share
        return components.url
    }

    static func serverURL(host rawHost: String) -> URL? {
        guard let host = normalizedHost(rawHost) else { return nil }
        return URL(string: "smb://\(host)")
    }

    static func detail(host: String, share: String) -> String {
        "\(normalizedHost(host) ?? host)/\(normalizedShare(share) ?? share)"
    }
}

// MARK: - Mount manager

@MainActor
final class SMBMountManager {
    static let shared = SMBMountManager()

    private let baseDirectory: URL
    private var mountedPaths: [String: URL] = [:]
    private var pendingMounts: [String: Task<URL, Error>] = [:]

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? Self.resolvedTemporaryDirectory()
            .appendingPathComponent("WaveletMediaMounts", isDirectory: true)
        if FileManager.default.fileExists(atPath: self.baseDirectory.path) {
            cleanupStaleMounts()
        }
    }

    private static func resolvedTemporaryDirectory() -> URL {
        let temp = FileManager.default.temporaryDirectory
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let resolved = temp.path.withCString { realpath($0, &buffer) }
        if resolved != nil {
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self), isDirectory: true)
        }
        return temp
    }

    func mount(_ source: SMBSourceConfig, password: String?) async throws -> URL {
        if let path = mountedPaths[source.id], Self.isSMBMount(path) {
            return path
        }
        if let pending = pendingMounts[source.id] {
            return try await pending.value
        }
        let mountPoint = baseDirectory.appendingPathComponent(source.id, isDirectory: true)
        let effectivePassword = (password?.isEmpty == true) ? nil : password
        let task = Task<URL, Error> {
            do {
                return try await Self.attemptMount(
                    source: source,
                    mountPoint: mountPoint,
                    password: effectivePassword
                )
            } catch let failure as MediaFailure
                where Self.isCredentialFailure(failure) && effectivePassword != nil {
                // The app's saved password may be stale. NetFS can use the
                // credential already stored by macOS (Finder/system Keychain).
                return try await Self.attemptMount(
                    source: source,
                    mountPoint: mountPoint,
                    password: nil
                )
            }
        }
        pendingMounts[source.id] = task
        do {
            let path = try await task.value
            pendingMounts[source.id] = nil
            mountedPaths[source.id] = path
            return path
        } catch {
            pendingMounts[source.id] = nil
            if Self.isSMBMount(mountPoint) {
                Task.detached(priority: .utility) {
                    Self.performUnmount(mountPoint)
                }
            } else {
                try? FileManager.default.removeItem(at: mountPoint)
            }
            throw error
        }
    }

    /// Opens the system SMB share picker for a server URL such as
    /// `smb://192.168.3.133`, then returns the selected share name.
    func chooseShare(
        host rawHost: String,
        username: String,
        password: String?,
        usesGuest: Bool
    ) async throws -> String {
        guard let host = SMBAddress.normalizedHost(rawHost),
              let url = SMBAddress.serverURL(host: host) else {
            throw MediaFailure("SMB 服务器地址不能为空。")
        }
        let mountPoint = baseDirectory.appendingPathComponent("Picker-\(UUID().uuidString)", isDirectory: true)
        let result = await Task.detached(priority: .userInitiated) { () -> Result<[URL], Error> in
            do {
                try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
                let openOptions = NSMutableDictionary()
                openOptions[kNAUIOptionKey] = kNAUIOptionAllowUI
                if usesGuest { openOptions[kNetFSUseGuestKey] = true }
                let mountOptions = NSMutableDictionary()
                mountOptions[kNetFSMountAtMountDirKey] = true
                mountOptions[kNetFSAllowSubMountsKey] = true
                mountOptions[kNetFSSoftMountKey] = true
                mountOptions[kNetFSMountFlagsKey] = NSNumber(value: MNT_DONTBROWSE)
                let user: CFString? = (usesGuest || username.isEmpty) ? nil : (username as CFString)
                let pass: CFString? = (usesGuest || password == nil) ? nil : (password! as CFString)
                var mountpoints: Unmanaged<CFArray>?
                let status = NetFSMountURLSync(
                    url as CFURL,
                    mountPoint as CFURL,
                    user,
                    pass,
                    openOptions,
                    mountOptions,
                    &mountpoints
                )
                guard status == 0 else { return .failure(Self.mountFailure(status)) }
                var paths: [URL] = []
                if let mountpoints {
                    paths = (mountpoints.takeRetainedValue() as NSArray).compactMap { value in
                        guard let path = value as? String else { return nil }
                        return URL(fileURLWithPath: path)
                    }
                }
                return .success(paths.isEmpty ? [mountPoint] : paths)
            } catch {
                return .failure(error)
            }
        }.value

        let paths: [URL]
        do {
            paths = try result.get()
        } catch {
            if Self.isSMBMount(mountPoint) { Self.performUnmount(mountPoint) }
            if !Self.isSMBMount(mountPoint) { try? FileManager.default.removeItem(at: mountPoint) }
            throw error
        }
        var shares: [String] = []
        for path in paths {
            if let share = Self.shareName(from: path) { shares.append(share) }
        }
        if shares.isEmpty, let share = Self.shareName(from: mountPoint) { shares.append(share) }

        for path in paths where Self.isMountPoint(path) {
            Self.performUnmount(path)
        }
        if Self.isMountPoint(mountPoint) { Self.performUnmount(mountPoint) }
        if !Self.isSMBMount(mountPoint) { try? FileManager.default.removeItem(at: mountPoint) }

        guard let share = shares.first else {
            throw MediaFailure("未选择共享。")
        }
        return share
    }

    nonisolated static func isMountPoint(_ path: URL) -> Bool {
        var info = statfs()
        guard statfs(path.path, &info) == 0 else { return false }
        let on = withUnsafeBytes(of: info.f_mntonname) { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        return URL(fileURLWithPath: on).standardizedFileURL.path == path.standardizedFileURL.path
    }

    nonisolated static func shareName(from path: URL) -> String? {
        var info = statfs()
        guard statfs(path.path, &info) == 0 else { return nil }
        let source = withUnsafeBytes(of: info.f_mntfromname) { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        guard let share = source.split(separator: "/").last, !share.isEmpty else { return nil }
        return String(share).removingPercentEncoding ?? String(share)
    }

    func unmount(_ sourceID: String) {
        pendingMounts[sourceID]?.cancel()
        pendingMounts[sourceID] = nil
        guard let path = mountedPaths.removeValue(forKey: sourceID) else { return }
        Task.detached(priority: .utility) {
            Self.performUnmount(path)
        }
    }

    /// Synchronous variant used when the user reconnects or edits a source and
    /// the new mount must not race the old one.
    func unmountImmediately(_ sourceID: String) {
        pendingMounts[sourceID]?.cancel()
        pendingMounts[sourceID] = nil
        guard let path = mountedPaths.removeValue(forKey: sourceID) else { return }
        Self.performUnmount(path)
    }

    func isMounted(_ sourceID: String) -> Bool {
        guard let path = mountedPaths[sourceID] else { return false }
        return Self.isSMBMount(path)
    }

    func shutdown() {
        for task in pendingMounts.values { task.cancel() }
        pendingMounts.removeAll()
        let paths = mountedPaths.values
        mountedPaths.removeAll()
        for path in paths { Self.performUnmount(path) }
    }

    private func cleanupStaleMounts() {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for child in children {
            if Self.isSMBMount(child) {
                Self.performUnmount(child)
            } else if (try? FileManager.default.contentsOfDirectory(atPath: child.path))?.isEmpty == true {
                try? FileManager.default.removeItem(at: child)
            }
        }
    }

    // MARK: NetFS bridge

    nonisolated private static func attemptMount(
        source: SMBSourceConfig,
        mountPoint: URL,
        password: String?
    ) async throws -> URL {
        var variants = [source.share]
        let lower = source.share.lowercased()
        if lower != source.share { variants.append(lower) }
        let upper = source.share.uppercased()
        if upper != source.share, !variants.contains(upper) { variants.append(upper) }

        var lastError: Error?
        for (index, share) in variants.enumerated() {
            var candidate = source
            candidate.share = share
            guard let variantURL = SMBAddress.shareURL(host: source.host, share: share) else { continue }
            do {
                return try await performMount(
                    source: candidate,
                    url: variantURL,
                    mountPoint: mountPoint,
                    password: password
                )
            } catch let failure as MediaFailure
                where (failure.status == 2 || failure.status == 13 || failure.status == 1)
                && index < variants.count - 1 {
                lastError = failure
                continue
            } catch {
                throw error
            }
        }
        throw lastError ?? MediaFailure("找不到共享，请检查共享名称。")
    }

    nonisolated private static func isCredentialFailure(_ failure: MediaFailure) -> Bool {
        guard let status = failure.status else { return false }
        return status == 1 || status == 13 || status == -5997 || status == -6606
    }

    nonisolated private static func performMount(
        source: SMBSourceConfig,
        url: URL,
        mountPoint: URL,
        password: String?
    ) async throws -> URL {
        let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
            do {
                try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
                if isSMBMount(mountPoint) { return .success(mountPoint) }

                let openOptions = NSMutableDictionary()
                openOptions[kNAUIOptionKey] = kNAUIOptionNoUI
                openOptions[kNetFSAllowLoopbackKey] = true
                if source.usesGuest {
                    openOptions[kNetFSUseGuestKey] = true
                }
                let mountOptions = NSMutableDictionary()
                mountOptions[kNetFSMountAtMountDirKey] = true
                mountOptions[kNetFSSoftMountKey] = true
                mountOptions[kNetFSMountFlagsKey] = NSNumber(value: MNT_DONTBROWSE)

                let user: CFString? = (source.usesGuest || source.username.isEmpty) ? nil : (source.username as CFString)
                let pass: CFString? = (source.usesGuest || password == nil) ? nil : (password! as CFString)
                var mountpoints: Unmanaged<CFArray>?
                let status = NetFSMountURLSync(
                    url as CFURL,
                    mountPoint as CFURL,
                    user,
                    pass,
                    openOptions,
                    mountOptions,
                    &mountpoints
                )
                guard status == 0 else {
                    return .failure(Self.mountFailure(status))
                }
                if let mountpoints {
                    let paths = (mountpoints.takeRetainedValue() as NSArray).compactMap { value -> URL? in
                        guard let path = value as? String else { return nil }
                        return URL(fileURLWithPath: path)
                    }
                    return .success(paths.first ?? mountPoint)
                }
                return .success(mountPoint)
            } catch {
                return .failure(error)
            }
        }.value
        return try result.get()
    }

    nonisolated private static func performUnmount(_ path: URL) {
        guard isSMBMount(path) else { return }
        if Darwin.unmount(path.path, 0) != 0 {
            _ = Darwin.unmount(path.path, MNT_FORCE)
        }
        if !isSMBMount(path) {
            try? FileManager.default.removeItem(at: path)
        }
    }

    nonisolated static func isSMBMount(_ url: URL) -> Bool {
        fileSystemType(at: url) == "smbfs"
    }

    nonisolated static func fileSystemType(at url: URL) -> String? {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return nil }
        return withUnsafeBytes(of: info.f_fstypename) { raw in
            guard let base = raw.baseAddress else { return nil }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }

    nonisolated static func mountFailure(_ status: Int32) -> MediaFailure {
        switch status {
        case -128:
            return MediaFailure("已取消连接。", status: status)
        case -5045, -5046:
            return MediaFailure("服务器要求更改密码。", status: status)
        case -5999:
            return MediaFailure("账号受限，无法连接。", status: status)
        case -5998:
            return MediaFailure("服务器没有可用的共享。", status: status)
        case -5997:
            return MediaFailure("认证失败，请检查用户名和密码。", status: status)
        case -5996:
            return MediaFailure("服务器不支持所需的 SMB 协议。", status: status)
        case -6003:
            return MediaFailure("服务器没有可用的共享。", status: status)
        case -6004:
            return MediaFailure("服务器不允许访客访问，请使用用户名和密码。", status: status)
        case -6600, -6606:
            return MediaFailure("无法挂载 SMB 共享，请检查地址、共享名称和凭据。", status: status)
        case 13:
            return MediaFailure("认证失败，请检查用户名和密码。", status: status)
        case 1, 62:
            return MediaFailure("无法挂载 SMB 共享，请检查系统权限或挂载点。", detail: String(cString: strerror(status)), status: status)
        case 2:
            return MediaFailure("找不到共享，请检查共享名称。", status: status)
        case 60:
            return MediaFailure("连接超时，请检查服务器地址。", status: status)
        case 64, 65:
            return MediaFailure("无法访问服务器，请检查网络和地址。", status: status)
        default:
            let detail = status > 0 ? String(cString: strerror(status)) : nil
            return MediaFailure("无法连接 SMB 服务器（错误 %d）。", detail: detail, status: status)
        }
    }
}

// MARK: - File browsing

enum FileMediaBrowser {
    static func entries(in directory: URL, root: URL) throws -> [MediaEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .isRegularFileKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            throw MediaFailure("无法读取此文件夹。", detail: error.localizedDescription)
        }

        var result: [MediaEntry] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isPackage = values?.isPackage == true
            if values?.isDirectory == true && !isPackage {
                result.append(MediaEntry(
                    id: "folder:\(relativePath(url, root: root))",
                    objectID: relativePath(url, root: root),
                    name: url.lastPathComponent,
                    kind: .container,
                    detail: nil,
                    artist: nil,
                    album: nil,
                    audioURL: nil,
                    artworkURL: nil,
                    duration: nil,
                    format: nil,
                    size: nil,
                    childCount: nil
                ))
            } else if AudioFile.isAudioFile(url) {
                let size = values?.fileSize.map { Int64($0) }
                result.append(MediaEntry(
                    id: "audio:\(relativePath(url, root: root))",
                    objectID: relativePath(url, root: root),
                    name: url.deletingPathExtension().lastPathComponent,
                    kind: .audio,
                    detail: nil,
                    artist: nil,
                    album: nil,
                    audioURL: url,
                    artworkURL: nil,
                    duration: nil,
                    format: AudioFile.formatLabel(for: url),
                    size: size,
                    childCount: nil
                ))
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .container }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        var relative = String(path.dropFirst(rootPath.count))
        while relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    static func resolve(relativePath: String, in root: URL) throws -> URL {
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            throw MediaFailure("共享内的路径无效。")
        }
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw MediaFailure("文件不存在。")
        }
        return candidate
    }

    static func root(onVolume url: URL) -> URL {
        // The mount point itself is the share root.
        url
    }
}
