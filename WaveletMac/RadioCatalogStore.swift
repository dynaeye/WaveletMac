import Combine
import Foundation

@MainActor
final class RadioCatalogStore: ObservableObject {
    let player: PlaybackEngine
    @Published private(set) var stations: [Station] = []
    @Published private(set) var loadError: String?
    @Published var searchText = ""
    @Published var selectedStationID: Station.ID?
    @Published private(set) var favoriteIDs: [Station.ID]

    private let favoritesKey = "wavelet.mac.favoriteStationIDs.v1"

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        player = PlaybackEngine(defaults: defaults)
        favoriteIDs = defaults.stringArray(forKey: favoritesKey) ?? []
        do {
            let catalog = try StationCatalog.load(bundle: bundle)
            stations = catalog.stations.sorted(by: Search.directoryOrder)
            favoriteIDs = FavoriteStations.sanitized(
                favoriteIDs,
                validIDs: Set(stations.map(\.id))
            )
            selectedStationID = stations.first?.id
            if let station = stations.first {
                player.restore(station, line: player.savedLine(for: station.id))
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    var filteredStations: [Station] {
        stations.filter { Search.matches(searchText, station: $0) }
    }

    var selectedStation: Station? {
        guard let selectedStationID else { return nil }
        return stations.first { $0.id == selectedStationID }
    }

    var favoriteStations: [Station] {
        let byID = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) })
        return favoriteIDs.compactMap { byID[$0] }
    }

    func select(_ station: Station) {
        selectedStationID = station.id
        player.select(station, line: player.savedLine(for: station.id))
    }

    func toggleFavorite(_ station: Station, defaults: UserDefaults = .standard) {
        favoriteIDs = FavoriteStations.toggling(station.id, in: favoriteIDs)
        defaults.set(favoriteIDs, forKey: favoritesKey)
    }

    func isFavorite(_ station: Station) -> Bool {
        favoriteIDs.contains(station.id)
    }
}
