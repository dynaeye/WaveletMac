import AppKit
import Combine
import Foundation
import XCTest
@testable import WaveletMac

final class CatalogTests: XCTestCase {
    private func makeRepository() throws -> (PersonalStationRepository, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaveletMacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (PersonalStationRepository(applicationSupportDirectory: directory), directory)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "WaveletMacTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    private func station(
        _ name: String,
        id: String = UUID().uuidString,
        region: String = "自定义地区",
        group: String = "自定义分组",
        city: String = "自定义城市",
        category: String = "音乐",
        language: String = "中文",
        streams: [RadioStream]? = nil
    ) -> Station {
        Station(
            id: id, name: name, region: region, group: group, city: city,
            category: category, language: language, aliases: ["别名"],
            official: "https://station.example/about", source: "本机添加",
            streams: streams ?? [RadioStream(url: URL(string: "https://\(id).example/live.mp3")!, format: "mp3", testedAt: "")]
        )
    }

    private func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @MainActor
    func testFreshInstallIsEmptyAndLegacyPreferencesAreBackedUpBeforeRetirement() throws {
        let (defaults, suite) = try makeDefaults()
        let (repository, directory) = try makeRepository()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        defaults.set(["legacy-station"], forKey: "wavelet.mac.favoriteStationIDs.v1")
        defaults.set(2, forKey: "wavelet.mac.line.legacy-station.v1")
        defaults.set("深色", forKey: "wavelet.mac.theme.v1")
        defaults.set("英文", forKey: "wavelet.mac.language.v1")
        defaults.set(true, forKey: "wavelet.mac.autoplay.v1")
        defaults.set(Float(0.37), forKey: "wavelet.mac.volume.v1")

        let store = RadioCatalogStore(defaults: defaults, repository: repository)

        XCTAssertTrue(store.stations.isEmpty)
        XCTAssertTrue(store.favoriteStations.isEmpty)
        XCTAssertNil(store.player.station)
        XCTAssertEqual(store.player.state, .ready)
        XCTAssertTrue(defaults.bool(forKey: "wavelet.mac.personalCatalogMigration.v1"))
        XCTAssertNil(defaults.object(forKey: "wavelet.mac.line.legacy-station.v1"))
        XCTAssertEqual(defaults.string(forKey: "wavelet.mac.theme.v1"), "深色")
        XCTAssertEqual(defaults.string(forKey: "wavelet.mac.language.v1"), "英文")
        XCTAssertTrue(defaults.bool(forKey: "wavelet.mac.autoplay.v1"))
        XCTAssertEqual(defaults.float(forKey: "wavelet.mac.volume.v1"), 0.37)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pre-personal-catalog-userdefaults.plist").path))
    }

    @MainActor
    func testManualAddUsesRequiredFieldsAndDoesNotStartPlayback() throws {
        let (defaults, suite) = try makeDefaults()
        let (repository, directory) = try makeRepository()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = RadioCatalogStore(defaults: defaults, repository: repository)

        let result = try store.addStation(
            name: "  我的电台  ", region: "  海外  ", url: "https://radio.example/live.aac",
            city: " 城市 ", category: " 音乐 ", language: " 英文 ",
            aliases: [" Foo, Bar，\nBaz ", " , "], source: "  个人  ", group: " 分组 "
        )

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(store.stations.count, 1)
        XCTAssertEqual(store.stations[0].name, "我的电台")
        XCTAssertEqual(store.stations[0].region, "海外")
        XCTAssertEqual(store.stations[0].city, "城市")
        XCTAssertEqual(store.stations[0].streams.first?.format, "aac")
        XCTAssertEqual(store.stations[0].aliases, ["Foo", "Bar", "Baz"])
        XCTAssertEqual(store.stations[0].source, "个人")
        XCTAssertEqual(store.stations[0].group, "分组")
        XCTAssertEqual(store.player.station?.id, store.stations[0].id)
        XCTAssertEqual(store.player.state, .ready)

        XCTAssertThrowsError(try store.addStation(
            name: " ", region: "地区", url: "https://radio.example/other", city: "城市",
            category: "音乐", language: "中文", aliases: [], source: "", group: ""
        ))
        XCTAssertThrowsError(try store.addStation(
            name: "有效名称", region: "地区", url: "file:///tmp/stream", city: "城市",
            category: "音乐", language: "中文", aliases: [], source: "", group: ""
        ))
        XCTAssertEqual(store.stations.count, 1)
    }

    func testSimplifiedAndFullFormatsRoundTripEveryStreamField() throws {
        let compact = try json([
            "schemaVersion": 1,
            "stations": [[
                "name": "Compact", "region": "", "city": "City", "category": "Talk",
                "language": "English", "aliases": ["Alt"], "source": "user", "group": "Group",
                "url": "https://compact.example/live.m3u8"
            ]]
        ])
        let decodedCompact = try PersonalCatalog.decode(compact)
        XCTAssertEqual(decodedCompact[0].region, "其他地区")
        XCTAssertEqual(decodedCompact[0].streams[0].format, "hls")

        let full = try json([
            "schemaVersion": 1,
            "sourceUpdatedAt": "2026-10-06T00:00:00Z",
            "validation": "user-provided",
            "stations": [[
                "id": "stable-id", "name": "Full", "region": "Custom",
                "group": "Original Group", "city": "Original City", "category": "Music",
                "language": "Japanese", "aliases": ["A"], "official": "https://radio.example",
                "source": "My source", "streams": [
                    ["url": "https://a.example/live.aac", "format": "aac", "testedAt": "2026-10-06"],
                    ["url": "https://b.example/live", "format": "custom-format", "testedAt": "never"]
                ]
            ]]
        ])
        let decodedFull = try PersonalCatalog.decode(full)
        let encoded = try PersonalCatalog.encode(decodedFull)
        let roundTrip = try PersonalCatalog.decode(encoded)
        XCTAssertEqual(roundTrip, decodedFull)
        XCTAssertEqual(roundTrip[0].id, "stable-id")
        XCTAssertEqual(roundTrip[0].official, "https://radio.example")
        XCTAssertEqual(roundTrip[0].streams[1].format, "custom-format")
        XCTAssertEqual(roundTrip[0].streams[1].testedAt, "never")
    }

    func testInvalidBatchSchemaAndSizeAreRejectedBeforeMerge() throws {
        let validThenInvalid = Data(#"{"schemaVersion":1,"stations":[{"name":"Valid","url":"https://valid.example/live"},{"name":"Invalid","url":"file:///unsafe"}]}"#.utf8)
        XCTAssertThrowsError(try PersonalCatalog.decode(validThenInvalid))
        XCTAssertThrowsError(try PersonalCatalog.decode(Data(#"{"schemaVersion":2,"stations":[]}"#.utf8)))
        XCTAssertThrowsError(try PersonalCatalog.decode(Data(repeating: 32, count: PersonalCatalog.maximumBytes + 1)))
        XCTAssertNoThrow(try PersonalCatalog.decode(Data(#"{"schemaVersion":1,"stations":[]}"#.utf8)))
    }

    func testURLCanonicalizationAndMergeRules() throws {
        let variants = [
            "HTTPS://EXAMPLE.COM:443/live#player", "https://example.com/live",
            "http://example.com/live", "https://example.com/Live",
            "https://example.com/live?token=a", "https://example.com/live?token=b"
        ].map { try! PersonalCatalog.validatedURL($0) }
        XCTAssertEqual(PersonalCatalog.urlKey(variants[0]), PersonalCatalog.urlKey(variants[1]))
        XCTAssertNotEqual(PersonalCatalog.urlKey(variants[1]), PersonalCatalog.urlKey(variants[2]))
        XCTAssertNotEqual(PersonalCatalog.urlKey(variants[1]), PersonalCatalog.urlKey(variants[3]))
        XCTAssertNotEqual(PersonalCatalog.urlKey(variants[4]), PersonalCatalog.urlKey(variants[5]))

        let base = station("Existing", id: "same-id", streams: [RadioStream(url: variants[1], format: "mp3", testedAt: "")])
        let collision = station("Different name", id: "same-id", region: "Other", streams: [
            RadioStream(url: variants[0], format: "hls", testedAt: ""),
            RadioStream(url: URL(string: "https://unused.example/b")!, format: "mp3", testedAt: "")
        ])
        let sameIDDifferentURL = station("New", id: "same-id", streams: [RadioStream(url: variants[2], format: "audio", testedAt: "")])
        let intraDuplicate = station("Internal", streams: [
            RadioStream(url: URL(string: "https://internal.example/a")!, format: "mp3", testedAt: "first"),
            RadioStream(url: URL(string: "HTTPS://INTERNAL.EXAMPLE:443/a#x")!, format: "aac", testedAt: "second"),
            RadioStream(url: URL(string: "https://internal.example/b")!, format: "aac", testedAt: "")
        ])
        let merged = PersonalCatalog.merge([collision, sameIDDifferentURL, intraDuplicate], into: [base])
        XCTAssertEqual(merged.added, 2)
        XCTAssertEqual(merged.duplicates, 1)
        XCTAssertNotEqual(merged.stations[1].id, "same-id")
        XCTAssertEqual(merged.stations[2].streams.map(\.url.absoluteString), ["https://internal.example/a", "https://internal.example/b"])
        XCTAssertEqual(merged.stations[2].streams[0].testedAt, "first")
    }

    @MainActor
    func testPersistenceFavoritesDynamicFiltersAndUserMetadataDoNotLocalize() throws {
        let (defaults, suite) = try makeDefaults()
        let (repository, directory) = try makeRepository()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = RadioCatalogStore(defaults: defaults, repository: repository)
        let data = try json([
            "schemaVersion": 1,
            "stations": [
                ["id": "one", "name": "Station One", "region": "Region A", "group": "Group A", "city": "City A", "category": "Music", "language": "English", "url": "https://one.example/live"],
                ["id": "two", "name": "Station Two", "region": "Region A", "group": "Group B", "city": "City B", "category": "Talk", "language": "Japanese", "url": "https://two.example/live"]
            ]
        ])
        let result = try store.importStations(data)
        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(store.player.state, .ready)
        store.toggleFavorite(store.stations[1])
        store.region = "Region A"
        store.group = "Group B"
        store.city = "City B"
        store.category = "Talk"
        store.searchText = "Station Two"
        store.setLanguage("日文")
        XCTAssertEqual(store.filteredStations.map(\.id), ["two"])
        XCTAssertEqual(store.filteredStations[0].language, "Japanese")

        let restarted = RadioCatalogStore(defaults: defaults, repository: repository)
        XCTAssertEqual(restarted.stations, store.stations)
        XCTAssertEqual(restarted.favoriteStations.map(\.id), ["two"])
        XCTAssertEqual(restarted.player.station?.id, store.player.station?.id)
        XCTAssertEqual(restarted.player.state, .ready)
        XCTAssertEqual(try PersonalCatalog.decode(try XCTUnwrap(repository.load())).count, 2)
    }

    @MainActor
    func testDuplicateOnlyImportChangesOnlyTheDuplicateNotice() throws {
        let (defaults, suite) = try makeDefaults()
        let (repository, directory) = try makeRepository()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = RadioCatalogStore(defaults: defaults, repository: repository)
        let station = station("One", id: "one")
        _ = try store.importStations(PersonalCatalog.encode([station]))
        store.toggleFavorite(station)
        store.searchText = "keep query"
        store.region = station.region
        store.group = station.group
        store.city = station.city
        store.category = station.category
        let selectedID = store.selectedStationID
        let state = store.player.state

        let result = try store.importStations(PersonalCatalog.encode([
            self.station("Same URL", id: "different-id", region: "Elsewhere", streams: station.streams)
        ]))

        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(store.lastImportDuplicateCount, 1)
        XCTAssertEqual(store.stations.count, 1)
        XCTAssertEqual(store.favoriteIDs, ["one"])
        XCTAssertEqual(store.searchText, "keep query")
        XCTAssertEqual(store.region, station.region)
        XCTAssertEqual(store.group, station.group)
        XCTAssertEqual(store.city, station.city)
        XCTAssertEqual(store.category, station.category)
        XCTAssertEqual(store.selectedStationID, selectedID)
        XCTAssertEqual(store.player.state, state)
    }

    @MainActor
    func testDeletionClearsOnlyRemovedStationAssociationsAndCurrentPlaybackState() throws {
        let (defaults, suite) = try makeDefaults()
        let (repository, directory) = try makeRepository()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = RadioCatalogStore(defaults: defaults, repository: repository)
        let first = station("First", id: "first", region: "R1", group: "G1", city: "C1", category: "A")
        let second = station("Second", id: "second", region: "R2", group: "G2", city: "C2", category: "B")
        _ = try store.importStations(PersonalCatalog.encode([first, second]))
        store.toggleFavorite(first)
        store.toggleFavorite(second)
        defaults.set(2, forKey: "wavelet.mac.line.second.v1")
        store.player.restore(first, line: 0)
        store.player.setSleep(minutes: 30)

        try store.deleteStation(second)
        XCTAssertEqual(store.player.station?.id, "first")
        XCTAssertNotNil(store.player.sleepDeadline)
        XCTAssertEqual(store.favoriteIDs, ["first"])
        XCTAssertNil(defaults.object(forKey: "wavelet.mac.line.second.v1"))
        XCTAssertEqual(store.availableRegions.map(\.value), ["R1"])
        XCTAssertEqual(store.group, "")

        try store.deleteStation(first)
        XCTAssertNil(store.player.station)
        XCTAssertEqual(store.player.state, .ready)
        XCTAssertNil(store.player.sleepDeadline)
        XCTAssertTrue(store.stations.isEmpty)
        XCTAssertTrue(store.favoriteIDs.isEmpty)
        XCTAssertNil(defaults.object(forKey: "wavelet.mac.lastStationID.v1"))
        store.step(1)
        XCTAssertNil(store.player.station)
    }

    @MainActor
    func testClearAllPersistsEmptyAndKeepsUnrelatedPreferences() throws {
        let (defaults, suite) = try makeDefaults()
        let (repository, directory) = try makeRepository()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = RadioCatalogStore(defaults: defaults, repository: repository)
        let stations = [station("One", id: "one"), station("Two", id: "two")]
        _ = try store.importStations(PersonalCatalog.encode(stations))
        stations.forEach { store.toggleFavorite($0) }
        defaults.set(0, forKey: "wavelet.mac.line.one.v1")
        defaults.set("Español", forKey: "wavelet.mac.language.v1")
        defaults.set("深色", forKey: "wavelet.mac.theme.v1")
        defaults.set(true, forKey: "wavelet.mac.autoplay.v1")
        defaults.set(Float(0.4), forKey: "wavelet.mac.volume.v1")
        store.player.restore(stations[0], line: 0)
        store.player.setSleep(minutes: 30)
        store.region = "自定义地区"
        store.group = "自定义分组"
        store.searchText = "query"

        try store.clearAllStations()

        XCTAssertTrue(store.stations.isEmpty)
        XCTAssertTrue(store.favoriteIDs.isEmpty)
        XCTAssertNil(store.player.station)
        XCTAssertEqual(store.player.state, .ready)
        XCTAssertNil(store.player.sleepDeadline)
        XCTAssertEqual(store.searchText, "")
        XCTAssertEqual(store.region, "")
        XCTAssertNil(defaults.object(forKey: "wavelet.mac.line.one.v1"))
        XCTAssertNil(defaults.object(forKey: "wavelet.mac.lastStationID.v1"))
        XCTAssertEqual(defaults.string(forKey: "wavelet.mac.language.v1"), "Español")
        XCTAssertEqual(defaults.string(forKey: "wavelet.mac.theme.v1"), "深色")
        XCTAssertTrue(defaults.bool(forKey: "wavelet.mac.autoplay.v1"))
        XCTAssertEqual(defaults.float(forKey: "wavelet.mac.volume.v1"), 0.4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("PersonalStations.json").path))
        let emptyStore = RadioCatalogStore(defaults: defaults, repository: repository)
        XCTAssertTrue(emptyStore.stations.isEmpty)
        XCTAssertTrue(try PersonalCatalog.decode(PersonalCatalog.encode([])).isEmpty)
    }

    @MainActor
    func testCorruptSavedFileIsPreservedAndPreventsAccidentalOverwrite() throws {
        let (defaults, suite) = try makeDefaults()
        let (repository, directory) = try makeRepository()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let corrupt = Data("not json".utf8)
        try repository.save(corrupt)
        let store = RadioCatalogStore(defaults: defaults, repository: repository)
        XCTAssertTrue(store.stations.isEmpty)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.importStations(Data(#"{"schemaVersion":2,"stations":[]}"#.utf8)))
        XCTAssertEqual(try repository.load(), corrupt)

        let replacement = try json([
            "schemaVersion": 1,
            "stations": [["name": "Recovered", "url": "https://recovered.example/live"]]
        ])
        let result = try store.importStations(replacement)
        XCTAssertEqual(result.added, 1)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.stations.first?.name, "Recovered")
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("PersonalStations.corrupt-backup.json")), corrupt)
    }

    func testInterfaceTranslationsCoverAllSupportedLanguages() {
        for (key, row) in MacLocalization.translations {
            XCTAssertEqual(row.count, MacLocalization.languages.count, key)
            XCTAssertTrue(row.allSatisfy { !$0.isEmpty }, key)
            for (index, language) in MacLocalization.languages.enumerated() {
                XCTAssertEqual(MacLocalization.text(key, language: language), row[index], "\(key): \(language)")
            }
        }
        XCTAssertEqual(MacLocalization.text("电台列表", language: "繁體中文"), "電台列表")
        XCTAssertEqual(MacLocalization.format("分钟后停止", count: 30, language: "英文"), "Stop in 30 minutes")
        XCTAssertEqual(MacLocalization.format("个电台", count: 12, language: "简体中文"), "12 个电台")
    }

    @MainActor
    func testFollowingSystemClearsWindowAndHostingAppearanceOverrides() {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        for forced in ["浅色", "深色", "浅色"] {
            WindowTheme.apply(forced, to: window)
            XCTAssertEqual(window.appearance?.name, forced == "浅色" ? .aqua : .darkAqua)
            window.contentView?.appearance = NSAppearance(named: .aqua)
            WindowTheme.apply("跟随系统", to: window)
            XCTAssertNil(window.appearance)
            XCTAssertNil(window.contentView?.appearance)
            XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]))
        }
    }

    @MainActor
    func testSleepTimerCanBeConfiguredAndClearedWithStation() throws {
        let player = PlaybackEngine()
        player.restore(station("Timer"), line: 0)
        player.setSleep(minutes: 30)
        XCTAssertNotNil(player.sleepDeadline)
        XCTAssertNotNil(player.sleepRemaining)
        player.clearStation()
        XCTAssertNil(player.station)
        XCTAssertNil(player.sleepDeadline)
        XCTAssertEqual(player.state, .ready)
    }

    @MainActor
    func testShowMainWindowReusesExistingWindow() throws {
        let previous = TransparentWindowConfigurator.configuredWindow
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.close()
            TransparentWindowConfigurator.configuredWindow = previous
        }
        TransparentWindowConfigurator.configuredWindow = window
        let controller = RadioStatusBarController()
        let count = NSApplication.shared.windows.count
        for _ in 0..<5 { controller.showWindow() }
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(NSApplication.shared.windows.count, count)
        XCTAssertTrue(TransparentWindowConfigurator.configuredWindow === window)
    }

    @MainActor
    func testBorderlessReceiverCanMinimizeAndRestore() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless, .fullSizeContentView, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.orderFront(nil)
        let minimized = XCTNSNotificationExpectation(name: NSWindow.didMiniaturizeNotification, object: window)
        window.miniaturize(nil)
        XCTAssertEqual(XCTWaiter.wait(for: [minimized], timeout: 3), .completed)
        XCTAssertTrue(window.isMiniaturized)
        let restored = XCTNSNotificationExpectation(name: NSWindow.didDeminiaturizeNotification, object: window)
        window.deminiaturize(nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 3), .completed)
        XCTAssertFalse(window.isMiniaturized)
    }

    func testDrawerPlacementStaysOnParentScreenAndAvoidsBottomEdge() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 860)
        let nearBottom = NSRect(x: 300, y: 8, width: 600, height: 540)
        let above = DrawerPanelPlacement.frame(parent: nearBottom, visibleScreen: screen, preferredHeight: 320)
        XCTAssertEqual(above.minY, nearBottom.maxY + 12, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(above.minY, screen.minY)
        XCTAssertLessThanOrEqual(above.maxY, screen.maxY)
        XCTAssertEqual(above.height, 300, accuracy: 0.01)

        let nearTop = NSRect(x: 300, y: 312, width: 600, height: 540)
        let below = DrawerPanelPlacement.frame(parent: nearTop, visibleScreen: screen, preferredHeight: 320)
        XCTAssertLessThanOrEqual(below.maxY, nearTop.minY - 12 + 0.01)
        XCTAssertGreaterThanOrEqual(below.minY, screen.minY)
        XCTAssertGreaterThanOrEqual(below.height, 180)
    }

    func testDrawerPlacementUsesOwningDisplayCoordinatesAndClampsHorizontally() {
        let rightDisplay = NSRect(x: 1440, y: 0, width: 1280, height: 900)
        let parent = NSRect(x: 2500, y: 120, width: 600, height: 540)
        let frame = DrawerPanelPlacement.frame(parent: parent, visibleScreen: rightDisplay, preferredHeight: 300)
        XCTAssertGreaterThanOrEqual(frame.minX, rightDisplay.minX + 8)
        XCTAssertLessThanOrEqual(frame.maxX, rightDisplay.maxX - 8)
        XCTAssertGreaterThanOrEqual(frame.minY, rightDisplay.minY)
        XCTAssertLessThanOrEqual(frame.maxY, rightDisplay.maxY)
    }

    @MainActor
    func testVolumeChangesAreImmediateButSavingIsDebounced() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Float(0.25), forKey: "wavelet.mac.volume.v1")
        let player = PlaybackEngine(defaults: defaults)
        var received: [Float] = []
        let subscription = player.volumeChanges.sink { received.append($0) }
        defer { subscription.cancel() }
        player.volume = 0.4
        player.volume = 0.6
        XCTAssertEqual(received, [0.4, 0.6])
        XCTAssertEqual(defaults.float(forKey: "wavelet.mac.volume.v1"), 0.25)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(defaults.float(forKey: "wavelet.mac.volume.v1"), 0.6)
        player.volume = 1.2
        XCTAssertEqual(player.volume, 1)
        player.persistVolume()
        XCTAssertEqual(defaults.float(forKey: "wavelet.mac.volume.v1"), 1)
    }

    @MainActor
    func testRecognitionHistoryKeepsFiveLatestDistinctSongsAndRestoresMetadata() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let recognition = StreamSongRecognition(defaults: defaults)
        for index in 1...6 {
            recognition.remember(RecognizedSong(
                id: "track-\(index)", title: "Song \(index)", artist: "Artist \(index)",
                artworkURL: URL(string: "https://example.com/cover/\(index).jpg"),
                appleMusicURL: URL(string: "https://music.apple.com/song/\(index)")
            ))
        }
        XCTAssertEqual(recognition.history.map(\.id), ["track-6", "track-5", "track-4", "track-3", "track-2"])
        let repeated = RecognizedSong(
            id: "track-3", title: "Updated Song 3", artist: "Artist 3",
            artworkURL: URL(string: "https://example.com/updated-cover.jpg"),
            appleMusicURL: URL(string: "https://music.apple.com/song/3")
        )
        recognition.remember(repeated)
        XCTAssertEqual(recognition.history.map(\.id), ["track-3", "track-6", "track-5", "track-4", "track-2"])
        XCTAssertEqual(recognition.history.first, repeated)
        XCTAssertEqual(StreamSongRecognition(defaults: defaults).history, recognition.history)
    }

    @MainActor
    func testInvalidRecognitionHistoryStartsEmptyAndCanSaveAgain() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid JSON".utf8), forKey: "wavelet.mac.songRecognitionHistory.v1")
        let recognition = StreamSongRecognition(defaults: defaults)
        XCTAssertTrue(recognition.history.isEmpty)
        let song = RecognizedSong(id: "track", title: "Song", artist: "Artist", artworkURL: nil, appleMusicURL: nil)
        recognition.remember(song)
        XCTAssertEqual(StreamSongRecognition(defaults: defaults).history, [song])
    }

    func testProgressiveRecognitionQueriesAtFiveSecondIntervalsAndStopsAtTwenty() {
        var schedule = RecognitionQuerySchedule(minimumDuration: 3)
        var queries: [Int] = []
        var finalQueries: [Int] = []
        for second in 0...25 {
            if let isFinal = schedule.checkpoint(at: Double(second)) {
                queries.append(second)
                if isFinal { finalQueries.append(second) }
            }
        }
        XCTAssertEqual(queries, [5, 10, 15, 20])
        XCTAssertEqual(finalQueries, [20])
    }

    func testProgressiveRecognitionRespectsCatalogMinimumAndHandlesSkippedSamples() {
        var schedule = RecognitionQuerySchedule(minimumDuration: 7)
        XCTAssertNil(schedule.checkpoint(at: 5))
        XCTAssertEqual(schedule.checkpoint(at: 7), false)
        XCTAssertNil(schedule.checkpoint(at: 7.2))
        XCTAssertEqual(schedule.checkpoint(at: 13), false)
        XCTAssertEqual(schedule.checkpoint(at: 20.1), true)
        XCTAssertNil(schedule.checkpoint(at: 25))
    }
}
