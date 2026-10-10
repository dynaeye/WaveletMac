import Foundation

/// Stores the user's catalog outside the app bundle and only replaces it atomically.
struct PersonalStationRepository {
    let applicationSupportDirectory: URL
    private let fileManager: FileManager

    init(
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.applicationSupportDirectory = applicationSupportDirectory ??
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Wavelet", isDirectory: true)
    }

    private var catalogURL: URL {
        applicationSupportDirectory.appendingPathComponent("PersonalStations.json")
    }

    private var migrationBackupURL: URL {
        applicationSupportDirectory.appendingPathComponent("pre-personal-catalog-userdefaults.plist")
    }

    func load() throws -> Data? {
        guard fileManager.fileExists(atPath: catalogURL.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: catalogURL.path)
        if let size = attributes[.size] as? NSNumber, size.intValue > PersonalCatalog.maximumBytes {
            throw PersonalCatalog.Failure.tooLarge
        }
        let data = try Data(contentsOf: catalogURL, options: .mappedIfSafe)
        guard data.count <= PersonalCatalog.maximumBytes else { throw PersonalCatalog.Failure.tooLarge }
        return data
    }

    func save(_ data: Data) throws {
        guard data.count <= PersonalCatalog.maximumBytes else { throw PersonalCatalog.Failure.tooLarge }
        try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        try data.write(to: catalogURL, options: .atomic)
    }

    /// Preserves an unreadable catalog before a user-initiated, validated replacement.
    func recover(with data: Data) throws {
        guard data.count <= PersonalCatalog.maximumBytes else { throw PersonalCatalog.Failure.tooLarge }
        try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: catalogURL.path) {
            let backup = applicationSupportDirectory.appendingPathComponent("PersonalStations.corrupt-backup.json")
            if !fileManager.fileExists(atPath: backup.path) {
                try fileManager.copyItem(at: catalogURL, to: backup)
            }
        }
        try data.write(to: catalogURL, options: .atomic)
    }

    func remove() throws {
        guard fileManager.fileExists(atPath: catalogURL.path) else { return }
        try fileManager.removeItem(at: catalogURL)
    }

    /// Keeps one recoverable snapshot before retiring the previous bundled-directory preferences.
    func backupLegacyPreferences(_ defaults: UserDefaults) throws {
        guard !fileManager.fileExists(atPath: migrationBackupURL.path) else { return }
        let snapshot = defaults.dictionaryRepresentation()
        let data = try PropertyListSerialization.data(
            fromPropertyList: snapshot,
            format: .binary,
            options: 0
        )
        try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        try data.write(to: migrationBackupURL, options: .atomic)
    }
}
