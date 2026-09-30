import Foundation

struct RadioStream: Codable, Hashable {
    let url: URL
    let format: String
    let testedAt: String
}

struct Station: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let region: String
    let group: String
    let city: String
    let category: String
    let language: String
    let aliases: [String]
    let official: String
    let source: String
    let streams: [RadioStream]
    var regionName: String { Region.all.first { $0.id == region }?.name ?? region }
    var subtitle: String { [regionName, group, city].filter { !$0.isEmpty }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: " · ") }
    var searchIndex: String { Search.normalize(([name, regionName, group, city, category, language] + aliases).joined(separator: " ")) }
}

struct Region: Identifiable {
    let id: String
    let name: String
    static let all = zip(["cn", "hk", "mo", "tw", "us", "sg", "my", "jp", "other", "tv"],
                         ["中国大陆", "香港", "澳门", "台湾", "美国", "新加坡", "马来西亚", "日本", "其他地区", "电视伴音"]).map { Region(id: $0, name: $1) }
}

struct StationCatalog: Codable {
    let schemaVersion: Int
    let sourceUpdatedAt: String
    let validation: String
    let stations: [Station]

    static func load(bundle: Bundle = .main, filename: String? = nil) throws -> StationCatalog {
        #if DEBUG
        let defaultFilename = "stations-candidates"
        #else
        let defaultFilename = "stations"
        #endif
        guard let url = bundle.url(forResource: filename ?? defaultFilename, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard catalog.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return catalog
    }
}

struct StationTranslation: Codable {
    let name: String
    let aliases: [String]
    let language: String
    let group: String
    let category: String
    let city: String
}

struct StationTranslationCatalog: Codable {
    let schemaVersion: Int
    let translations: [String: [String: StationTranslation]]

    static func load(bundle: Bundle = .main) throws -> StationTranslationCatalog {
        guard let url = bundle.url(forResource: "电台目录翻译", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard catalog.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return catalog
    }

    func localized(_ station: Station, appLanguage: String) -> Station {
        if appLanguage == "繁體中文" {
            return station.replacingCatalogText { value in
                value.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? value
            }
        }
        let languageCode = [
            "英文": "en", "日文": "ja", "韩文": "ko", "泰文": "th",
            "西班牙语": "es", "阿拉伯文": "ar"
        ][appLanguage]
        guard let languageCode, let translation = translations[languageCode]?[station.id] else { return station }
        return Station(
            id: station.id,
            name: translation.name,
            region: station.region,
            group: translation.group,
            city: translation.city,
            category: translation.category,
            language: translation.language,
            aliases: translation.aliases,
            official: station.official,
            source: station.source,
            streams: station.streams
        )
    }
}

private extension Station {
    func replacingCatalogText(_ transform: (String) -> String) -> Station {
        Station(
            id: id,
            name: transform(name),
            region: region,
            group: transform(group),
            city: transform(city),
            category: transform(category),
            language: transform(language),
            aliases: aliases.map(transform),
            official: official,
            source: source,
            streams: streams
        )
    }
}

enum Search {
    static func normalize(_ value: String) -> String {
        let simplified = value.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? value
        return simplified.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }
    static func before(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.numeric, .caseInsensitive], locale: Locale(identifier: "zh_CN@collation=pinyin")) == .orderedAscending
    }
    static func matches(_ query: String, station: Station) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace).map { normalize(String($0)) }
        return terms.allSatisfy { station.searchIndex.contains($0) }
    }
    static func nameOrder(_ a: Station, _ b: Station) -> Bool {
        let x = normalize(a.name), y = normalize(b.name)
        return x == y ? a.id < b.id : before(x, y)
    }
    static func groupRank(_ group: String, region: String) -> Int {
        if region == "cn" { return ["全国": 0, "央广": 0, "北京": 1, "上海": 2][group] ?? 3 }
        if region == "tv" { return ["央视": 0, "香港": 1][group] ?? 2 }
        return 0
    }
    static func directoryOrder(_ a: Station, _ b: Station) -> Bool {
        if a.region != b.region { return (Region.all.firstIndex { $0.id == a.region } ?? 99) < (Region.all.firstIndex { $0.id == b.region } ?? 99) }
        if a.group != b.group {
            let x = groupRank(a.group, region: a.region), y = groupRank(b.group, region: b.region)
            return x == y ? before(a.group, b.group) : x < y
        }
        return nameOrder(a, b)
    }
}

enum ListeningHistory {
    static func record(_ id: String, in counts: inout [String: Int]) {
        counts[id] = min(max(0, counts[id, default: 0]), Int.max - 1) + 1
    }
    static func top(_ stations: [Station], region: String, counts: [String: Int]) -> [Station] {
        Array(stations.filter { $0.region == region }.sorted {
            let a = counts[$0.id, default: 0], b = counts[$1.id, default: 0]
            return a == b ? Search.nameOrder($0, $1) : a > b
        }.prefix(4))
    }
}

enum FavoriteStations {
    static func sanitized(_ ids: [String], validIDs: Set<String>) -> [String] {
        var seen = Set<String>()
        return ids.filter { validIDs.contains($0) && seen.insert($0).inserted }
    }

    static func toggling(_ id: String, in ids: [String]) -> [String] {
        ids.contains(id) ? ids.filter { $0 != id } : [id] + ids
    }
}

struct SleepSchedule {
    private(set) var deadline: Date?
    mutating func start(minutes: Int, now: Date = Date()) { deadline = now.addingTimeInterval(Double(minutes * 60)) }
    mutating func cancel() { deadline = nil }
    func expired(at now: Date) -> Bool { deadline.map { $0 <= now } ?? false }
    func remaining(at now: Date) -> Int? { deadline.map { max(0, Int(ceil($0.timeIntervalSince(now)))) } }
}

enum PlaybackPolicy {
    static func nextLine(count: Int, tried: Set<Int>) -> Int? {
        guard tried.count < 3 else { return nil }
        return (0..<count).first { !tried.contains($0) }
    }
}

struct InterruptionResumePolicy {
    private(set) var wasPlaying = false

    mutating func interruptionBegan(whilePlaying: Bool) {
        wasPlaying = wasPlaying || whilePlaying
    }

    mutating func cancel() {
        wasPlaying = false
    }

    mutating func interruptionEnded() -> Bool {
        defer { wasPlaying = false }
        return wasPlaying
    }
}
