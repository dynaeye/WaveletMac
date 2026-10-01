import AppKit
import Foundation
import XCTest
@testable import WaveletMac

final class CatalogTests: XCTestCase {
    private var resourceBundle: Bundle {
        Bundle(for: CatalogTests.self)
    }

    func testDebugCatalogLoadsAllCandidates() throws {
        let catalog = try StationCatalog.load(bundle: resourceBundle, filename: "stations-candidates")

        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.stations.count, 1_519)
        XCTAssertEqual(Set(catalog.stations.map(\.id)).count, catalog.stations.count)
        XCTAssertTrue(catalog.stations.allSatisfy { !$0.streams.isEmpty })
    }

    func testReleaseCatalogIsMacVerifiedAndEmptyUntilNativeValidation() throws {
        let catalog = try StationCatalog.load(bundle: resourceBundle, filename: "stations")

        XCTAssertEqual(catalog.validation, "mac-verified")
        XCTAssertTrue(catalog.stations.isEmpty)
    }

    func testSearchMatchesTraditionalSimplifiedAndMetadata() throws {
        let catalog = try StationCatalog.load(bundle: resourceBundle, filename: "stations-candidates")
        let station = try XCTUnwrap(catalog.stations.first { $0.name.contains("飛碟") })

        XCTAssertTrue(Search.matches("飞碟电台", station: station))
        XCTAssertTrue(Search.matches("台北", station: station))
        XCTAssertTrue(Search.matches("飞碟 台北", station: station))
        XCTAssertFalse(Search.matches("完全不存在的电台名称", station: station))
    }

    func testTranslationCatalogCoversEveryCandidateInSixLanguages() throws {
        let catalog = try StationCatalog.load(bundle: resourceBundle, filename: "stations-candidates")
        let translations = try StationTranslationCatalog.load(bundle: resourceBundle)

        XCTAssertEqual(Set(translations.translations.keys), Set(["en", "ja", "ko", "th", "es", "ar"]))
        for language in translations.translations.keys {
            XCTAssertEqual(translations.translations[language]?.count, catalog.stations.count)
        }
    }

    @MainActor
    func testStoreRestoresAStationWithoutStartingPlayback() throws {
        let suiteName = "WaveletMacTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RadioCatalogStore(bundle: resourceBundle, defaults: defaults)

        XCTAssertEqual(store.stations.count, 1_519)
        XCTAssertNotNil(store.player.station)
        XCTAssertEqual(store.player.state, .ready)
    }

    @MainActor
    func testSettingsPersistAndLanguageLocalizesCatalog() throws {
        let suiteName = "WaveletMacTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RadioCatalogStore(bundle: resourceBundle, defaults: defaults)
        let source = try StationCatalog.load(bundle: resourceBundle, filename: "stations-candidates")
        let sourceBeijing = try XCTUnwrap(source.stations.first { $0.city == "北京" })

        store.setTheme("深色")
        store.setLanguage("英文")
        store.autoplayEnabled = true

        XCTAssertEqual(defaults.string(forKey: "wavelet.mac.theme.v1"), "深色")
        XCTAssertEqual(defaults.string(forKey: "wavelet.mac.language.v1"), "英文")
        XCTAssertTrue(defaults.bool(forKey: "wavelet.mac.autoplay.v1"))
        XCTAssertEqual(store.stations.first { $0.id == sourceBeijing.id }?.city, "Beijing")
    }

    @MainActor
    func testDirectoryFiltersMatchIOSRegionGroupCityAndCategoryRules() throws {
        let suiteName = "WaveletMacTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RadioCatalogStore(bundle: resourceBundle, defaults: defaults)
        let target = try XCTUnwrap(store.stations.first {
            !$0.group.isEmpty && !$0.city.isEmpty && !$0.category.isEmpty
        })

        store.region = target.region
        store.group = target.group
        store.city = target.city
        store.category = target.category
        store.searchText = target.name

        XCTAssertTrue(store.filteredStations.contains { $0.id == target.id })
        XCTAssertTrue(store.filteredStations.allSatisfy {
            $0.region == target.region && $0.group == target.group &&
            $0.city == target.city && $0.category == target.category
        })
    }

    @MainActor
    func testSleepTimerCanBeConfiguredAndCancelled() {
        let player = PlaybackEngine()

        player.setSleep(minutes: 30)
        XCTAssertNotNil(player.sleepDeadline)
        XCTAssertNotNil(player.sleepRemaining)
        player.cancelSleep()
        XCTAssertNil(player.sleepDeadline)
        XCTAssertNil(player.sleepRemaining)
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
    func testLanguageSwitchUpdatesInterfaceAndMetadataWithoutResettingPlayer() throws {
        let suiteName = "WaveletMacTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RadioCatalogStore(bundle: resourceBundle, defaults: defaults)
        let stationID = store.player.station?.id
        let state = store.player.state
        let line = store.player.line
        for language in MacLocalization.languages + ["繁體中文", "简体中文"] {
            store.setLanguage(language)
            XCTAssertEqual(store.interfaceLanguage, language)
            XCTAssertEqual(store.text("设置"), MacLocalization.text("设置", language: language))
            XCTAssertEqual(store.player.station?.id, stationID)
            XCTAssertEqual(store.player.line, line)
            XCTAssertEqual(store.player.state, state)
            XCTAssertEqual(store.player.station, store.stations.first { $0.id == stationID })
        }
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
}
