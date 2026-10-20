import Foundation

enum MediaSourceKind: String, Codable, CaseIterable, Sendable {
    case upnp
    case smb
    case folder

    var symbolName: String {
        switch self {
        case .upnp: "dot.radiowaves.left.and.right"
        case .smb: "externaldrive.connected.to.line.below"
        case .folder: "folder"
        }
    }
}

/// A UPnP/DLNA media server the user can reopen later.
struct UPnPSourceConfig: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var descriptionURL: URL
    var udn: String?
    var lastSeenAt: Date?
}

/// Credentials are intentionally not part of this value; they live in Keychain.
struct SMBSourceConfig: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var host: String
    var share: String
    var username: String
    var usesGuest: Bool
    var rememberPassword: Bool

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(host)/\(share)" : trimmed
    }

    var detail: String { "SMB · \(host)/\(share)" }
}

struct FolderSourceConfig: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var path: String
    var bookmark: Data?

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (path as NSString).lastPathComponent : trimmed
    }

    var detail: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

struct PersistedMediaSources: Codable, Sendable {
    var upnp: [UPnPSourceConfig] = []
    var smb: [SMBSourceConfig] = []
    var folders: [FolderSourceConfig] = []
}

/// A row in the source sidebar.
struct MediaSourceRef: Identifiable, Hashable, Sendable {
    let kind: MediaSourceKind
    let id: String
    let name: String
    let detail: String
    let isOnline: Bool?

    var key: String { "\(kind.rawValue):\(id)" }
}

struct BrowseLocation: Identifiable, Hashable, Sendable {
    /// UPnP object ID, or a path relative to the source root ("" for the root).
    let id: String
    let title: String
}

struct MediaEntry: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case container
        case audio
    }

    let id: String
    /// UPnP object ID, or the path relative to the source root.
    let objectID: String
    let name: String
    let kind: Kind
    let detail: String?
    let artist: String?
    let album: String?
    let audioURL: URL?
    let artworkURL: URL?
    let duration: TimeInterval?
    let format: String?
    let size: Int64?
    let childCount: Int?

    var isPlayable: Bool { kind == .audio && audioURL != nil }

    func track(sourceID: String, sourceName: String, isNetworkSource: Bool) -> LocalAudioTrack? {
        guard let audioURL else { return nil }
        return LocalAudioTrack(
            id: "\(sourceID):\(objectID)",
            title: name,
            artist: artist ?? "",
            album: album ?? "",
            url: audioURL,
            artworkURL: artworkURL,
            sourceID: sourceID,
            sourceName: sourceName,
            format: format ?? AudioFile.formatLabel(for: audioURL),
            durationHint: duration,
            isNetworkSource: isNetworkSource
        )
    }
}

struct LocalAudioTrack: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let url: URL
    let artworkURL: URL?
    let sourceID: String
    let sourceName: String
    let format: String
    let durationHint: TimeInterval?
    let isNetworkSource: Bool

    var subtitle: String {
        let parts = [artist, album, sourceName].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return parts.joined(separator: " · ")
    }

    var detail: String {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum AudioFile {
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "wave", "aiff", "aif", "aifc",
        "alac", "ogg", "oga", "opus", "wma", "ape", "m4b", "caf", "dsf", "dff",
        "mp2", "mpga", "ac3", "amr", "au", "snd"
    ]

    static func isAudioFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func isAudioFile(named name: String) -> Bool {
        supportedExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    static func formatLabel(for url: URL) -> String {
        formatLabel(extension: url.pathExtension)
    }

    static func formatLabel(extension pathExtension: String) -> String {
        let value = pathExtension.lowercased()
        guard !value.isEmpty else { return "AUDIO" }
        switch value {
        case "m4a", "alac": return "ALAC"
        case "aiff", "aif", "aifc": return "AIFF"
        case "wave": return "WAV"
        case "mpga": return "MP3"
        case "oga": return "OGG"
        default: return value.uppercased()
        }
    }

    static func formatLabel(mimeType: String, url: URL) -> String {
        switch mimeType.lowercased() {
        case "audio/mpeg", "audio/mp3": return "MP3"
        case "audio/mp4", "audio/x-m4a", "audio/aac": return "AAC"
        case "audio/flac", "audio/x-flac": return "FLAC"
        case "audio/wav", "audio/x-wav", "audio/wave": return "WAV"
        case "audio/ogg", "application/ogg", "audio/opus": return "OGG"
        case "audio/aiff", "audio/x-aiff": return "AIFF"
        case "audio/x-ms-wma": return "WMA"
        default: return formatLabel(for: url)
        }
    }

    static func sizeLabel(_ bytes: Int64?) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    static func durationLabel(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Parses UPnP `H:MM:SS[.fraction]` and `MM:SS` durations.
    static func parseDuration(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let pieces = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(pieces.count) else {
            return TimeInterval(trimmed)
        }
        var seconds = 0.0
        for piece in pieces {
            guard let number = Double(piece), number.isFinite, number >= 0 else { return nil }
            seconds = seconds * 60 + number
        }
        return seconds.isFinite ? seconds : nil
    }
}

struct MediaFailure: Error, Sendable {
    let messageKey: String
    let detail: String?
    let status: Int32?

    init(_ messageKey: String, detail: String? = nil, status: Int32? = nil) {
        self.messageKey = messageKey
        self.detail = detail
        self.status = status
    }
}

struct MediaStatusMessage: Equatable, Sendable {
    let text: String
    let isError: Bool
}
