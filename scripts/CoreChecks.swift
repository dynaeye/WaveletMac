import Foundation

@main
struct CoreChecks {
    static func main() throws {
        let catalog = try JSONDecoder().decode(StationCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: "Shared/Resources/stations-candidates.json")))
        precondition(catalog.schemaVersion == 1)
        precondition(catalog.stations.count > 1000)
        precondition(Set(catalog.stations.map(\.id)).count == catalog.stations.count)
        precondition(catalog.stations.allSatisfy { !$0.streams.isEmpty && $0.streams.allSatisfy { $0.url.scheme == "https" && ["hls", "aac", "mp3"].contains($0.format) } })
        precondition(Search.normalize("臺灣飛碟電臺 FM 92.1") == Search.normalize("台湾飞碟电台 fm92.1"))
        precondition(Search.normalize("香港電台").contains(Search.normalize("香港电台")))
        precondition(Search.groupRank("全国", region: "cn") < Search.groupRank("北京", region: "cn"))
        precondition(Search.groupRank("北京", region: "cn") < Search.groupRank("上海", region: "cn"))
        precondition(Search.groupRank("上海", region: "cn") < Search.groupRank("安徽", region: "cn"))
        precondition(Search.groupRank("央视", region: "tv") < Search.groupRank("香港", region: "tv"))
        precondition(["上海", "北京", "安徽"].sorted(by: Search.before) == ["安徽", "北京", "上海"])
        let stations = catalog.stations.sorted(by: Search.directoryOrder)
        precondition(zip(stations, stations.dropFirst()).allSatisfy { !Search.directoryOrder($1, $0) })
        let release = try JSONDecoder().decode(StationCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: "Shared/Resources/stations.json")))
        precondition(release.validation == "web-candidate")
        precondition(release.stations == catalog.stations)
        let region = "cn"
        let baseline = ListeningHistory.top(stations, region: region, counts: [:])
        precondition(baseline.count == 4 && baseline.allSatisfy { $0.region == region })
        var counts: [String: Int] = [:]
        let selected = stations.last { $0.region == region }!
        ListeningHistory.record(selected.id, in: &counts)
        precondition(counts[selected.id] == 1)
        precondition(ListeningHistory.top(stations, region: region, counts: counts).first?.id == selected.id)
        counts[selected.id] = Int.max
        ListeningHistory.record(selected.id, in: &counts)
        precondition(counts[selected.id] == Int.max)
        let validFavorites = Set(stations.prefix(2).map(\.id))
        let firstFavorite = stations[0].id, secondFavorite = stations[1].id
        precondition(FavoriteStations.sanitized([firstFavorite, "missing", firstFavorite, secondFavorite], validIDs: validFavorites) == [firstFavorite, secondFavorite])
        var favorites: [String] = []
        favorites = FavoriteStations.toggling(firstFavorite, in: favorites)
        favorites = FavoriteStations.toggling(secondFavorite, in: favorites)
        precondition(favorites == [secondFavorite, firstFavorite])
        favorites = FavoriteStations.toggling(firstFavorite, in: favorites)
        precondition(favorites == [secondFavorite])
        var sleep = SleepSchedule()
        let start = Date(timeIntervalSince1970: 1000)
        sleep.start(minutes: 30, now: start)
        precondition(sleep.remaining(at: start.addingTimeInterval(1200)) == 600)
        precondition(!sleep.expired(at: start.addingTimeInterval(1799)))
        precondition(sleep.expired(at: start.addingTimeInterval(1800)))
        precondition(sleep.remaining(at: start.addingTimeInterval(7200)) == 0)
        sleep.cancel()
        precondition(sleep.remaining(at: start) == nil)
        precondition(PlaybackPolicy.nextLine(count: 5, tried: [0, 1]) == 2)
        precondition(PlaybackPolicy.nextLine(count: 5, tried: [0, 1, 2]) == nil)
        precondition(PlaybackPolicy.nextLine(count: 1, tried: [0]) == nil)
        precondition(PlaybackPolicy.nextLine(count: 5, tried: [4]) == 0)
        var interruption = InterruptionResumePolicy()
        interruption.interruptionBegan(whilePlaying: true)
        precondition(interruption.interruptionEnded())
        interruption.interruptionBegan(whilePlaying: false)
        precondition(!interruption.interruptionEnded())
        interruption.interruptionBegan(whilePlaying: true)
        interruption.cancel()
        precondition(!interruption.interruptionEnded())
        print("PASS: catalog, HTTPS/format gate, unique IDs, traditional/simplified search, pinyin, region priorities, directory order, top four, selection counting, overflow, favorites persistence policy, sleep deadline/cancel, retry cap, interruption resume policy. Candidates: \(stations.count)")
    }
}
