import SwiftUI

@MainActor @Observable
final class RadioStore {
    let player = PlaybackEngine()
    var stations: [Station] = []
    var catalogError: String?
    var counts: [String: Int]
    var favoriteIDs: [String]
    var query = ""
    var region = ""
    var group = ""
    var city = ""
    var category = ""
    private var indexes: [String: String] = [:]
    private var sourceStations: [Station] = []
    private var translationCatalog: StationTranslationCatalog?
    private var stationLanguage = ""
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        counts = (defaults.dictionary(forKey: "wavelet.selections.v1") as? [String: Int] ?? [:]).filter { $0.value > 0 }
        favoriteIDs = defaults.stringArray(forKey: "wavelet.favorites.v1") ?? []
        do {
            sourceStations = try StationCatalog.load().stations.sorted(by: Search.directoryOrder)
            stations = sourceStations
            translationCatalog = try? StationTranslationCatalog.load()
            favoriteIDs = FavoriteStations.sanitized(favoriteIDs, validIDs: Set(stations.map(\.id)))
            defaults.set(favoriteIDs, forKey: "wavelet.favorites.v1")
            indexes = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0.searchIndex) })
            if let id = defaults.string(forKey: "wavelet.lastStation"), let station = stations.first(where: { $0.id == id }) {
                player.restore(station, line: defaults.integer(forKey: "wavelet.line.\(id)"))
            }
            if player.station == nil, let initial = stations.first(where: { $0.id == "f66bb002619e" }) ?? stations.first {
                player.restore(initial, line: 0)
            }
        } catch { catalogError = "电台目录读取失败，请重新安装或稍后重试。" }
        player.onStep = { [weak self] delta in self?.step(delta) }
    }
    func applyLanguage(_ language: String) {
        guard stationLanguage != language else { return }
        stationLanguage = language
        let localized = sourceStations.map { translationCatalog?.localized($0, appLanguage: language) ?? $0 }
        stations = localized
        let localizedByID = Dictionary(uniqueKeysWithValues: localized.map { ($0.id, $0) })
        indexes = Dictionary(uniqueKeysWithValues: sourceStations.map { source in
            let display = localizedByID[source.id] ?? source
            return (source.id, Search.normalize(source.searchIndex + " " + display.searchIndex))
        })
        group = ""
        city = ""
        category = ""
        if let currentID = player.station?.id, let station = localizedByID[currentID] {
            player.updateStationMetadata(station)
        }
    }
    var scoped: [Station] { stations.filter { region.isEmpty || $0.region == region } }
    var filtered: [Station] {
        let terms = query.split(whereSeparator: \.isWhitespace).map { Search.normalize(String($0)) }
        return scoped.filter { s in
            (group.isEmpty || s.group == group) && (city.isEmpty || s.city == city) &&
            (category.isEmpty || s.category == category) && terms.allSatisfy { indexes[s.id, default: ""].contains($0) }
        }
    }
    func top(_ region: String) -> [Station] {
        ListeningHistory.top(stations, region: region, counts: counts)
    }
    var favoriteStations: [Station] {
        let byID = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) })
        return favoriteIDs.compactMap { byID[$0] }
    }
    func isFavorite(_ station: Station) -> Bool { favoriteIDs.contains(station.id) }
    func toggleFavorite(_ station: Station) {
        favoriteIDs = FavoriteStations.toggling(station.id, in: favoriteIDs)
        defaults.set(favoriteIDs, forKey: "wavelet.favorites.v1")
    }
    func select(_ station: Station) {
        ListeningHistory.record(station.id, in: &counts)
        defaults.set(counts, forKey: "wavelet.selections.v1")
        defaults.set(station.id, forKey: "wavelet.lastStation")
        player.select(station, line: defaults.integer(forKey: "wavelet.line.\(station.id)"))
    }
    func step(_ delta: Int) {
        let list = filtered.isEmpty ? stations : filtered
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == player.station?.id } ?? (delta > 0 ? -1 : 0)
        select(list[(index + delta + list.count) % list.count])
    }
    func clearHistory() { counts = [:]; defaults.removeObject(forKey: "wavelet.selections.v1") }
}
