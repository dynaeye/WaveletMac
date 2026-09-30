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
}
