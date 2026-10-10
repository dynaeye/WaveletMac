import Foundation

/// Cross-platform personal-station JSON contract shared with WaveletRadio.
enum PersonalCatalog {
    static let maximumBytes = 10 * 1024 * 1024
    static let maximumStations = 10_000

    struct ImportResult {
        let stations: [Station]
        let added: Int
        let duplicates: Int
        let incomingCount: Int
    }

    struct File: Decodable {
        let schemaVersion: Int
        let stations: [Entry]
    }

    struct Entry: Decodable {
        let id: String?
        let name: String?
        let region: String?
        let group: String?
        let city: String?
        let category: String?
        let language: String?
        let aliases: [String]?
        let official: String?
        let source: String?
        let url: String?
        let streams: [Stream]?
    }

    struct Stream: Decodable {
        let url: String?
        let format: String?
        let testedAt: String?
    }

    enum Failure: LocalizedError {
        case invalidAddress
        case httpsRequired
        case invalidJSON
        case unsupportedVersion
        case tooManyStations
        case tooManySavedStations
        case tooLarge
        case emptyName
        case missingRequiredField(String)
        case missingAddress
        case unsafeRedirect
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidAddress: "请输入有效的 HTTP 或 HTTPS 播放地址。"
            case .httpsRequired: "网络 JSON 文件请使用 HTTPS 地址。"
            case .invalidJSON: "JSON 格式无效，请查看格式说明。"
            case .unsupportedVersion: "不支持此文件格式版本。"
            case .tooManyStations: "单次最多导入 10000 个电台。"
            case .tooManySavedStations: "个人电台最多保留 10000 个。"
            case .tooLarge: "文件或合并后的目录超过 10 MB，无法处理。"
            case .emptyName: "电台名称不能为空。"
            case let .missingRequiredField(field): "请填写必填项：\(field)。"
            case .missingAddress: "电台缺少有效的播放地址。"
            case .unsafeRedirect: "下载地址跳转到了非 HTTPS 页面，已取消导入。"
            case let .httpStatus(code): "下载失败（HTTP \(code)），请检查文件地址。"
            }
        }
    }

    static func validatedURL(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            throw Failure.invalidAddress
        }
        return url
    }

    static func makeStation(
        name: String, region: String, url: String, city: String, category: String,
        language: String, aliases: [String], source: String, group: String
    ) throws -> Station {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Failure.emptyName }
        for (field, value) in [("地区", region), ("城市", city), ("节目类型", category), ("语言", language)]
        where value.isEmpty { throw Failure.missingRequiredField(field) }
        let address = try validatedURL(url)
        let cleanedAliases = aliases
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",，\n\r")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Station(
            id: UUID().uuidString, name: name, region: region,
            group: group.trimmingCharacters(in: .whitespacesAndNewlines), city: city,
            category: category, language: language, aliases: cleanedAliases,
            official: "", source: source.trimmingCharacters(in: .whitespacesAndNewlines),
            streams: [RadioStream(url: address, format: inferredFormat(address), testedAt: "")]
        )
    }

    static func inferredFormat(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8": "hls"
        case "aac": "aac"
        case "mp3": "mp3"
        default: "audio"
        }
    }

    static func decode(_ data: Data) throws -> [Station] {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw Failure.invalidJSON
        }
        guard file.schemaVersion == 1 else { throw Failure.unsupportedVersion }
        guard file.stations.count <= maximumStations else { throw Failure.tooManyStations }

        return try file.stations.map { entry in
            guard let name = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                throw Failure.emptyName
            }
            let rawStreams: [Stream]
            if let streams = entry.streams {
                rawStreams = streams
            } else if let url = entry.url {
                rawStreams = [Stream(url: url, format: nil, testedAt: nil)]
            } else {
                rawStreams = []
            }
            guard !rawStreams.isEmpty else { throw Failure.missingAddress }

            var seen = Set<String>()
            let streams = try rawStreams.compactMap { stream -> RadioStream? in
                guard let value = stream.url else { throw Failure.missingAddress }
                let url = try validatedURL(value)
                guard seen.insert(urlKey(url)).inserted else { return nil }
                return RadioStream(
                    url: url,
                    format: stream.format ?? inferredFormat(url),
                    testedAt: stream.testedAt ?? ""
                )
            }
            guard !streams.isEmpty else { throw Failure.missingAddress }
            let rawRegion = (entry.region ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Station(
                id: normalizedID(entry.id), name: name,
                region: rawRegion.isEmpty ? "其他地区" : rawRegion,
                group: entry.group ?? "", city: entry.city ?? "",
                category: entry.category ?? "", language: entry.language ?? "",
                aliases: entry.aliases ?? [], official: entry.official ?? "",
                source: entry.source ?? "", streams: streams
            )
        }
    }

    static func urlKey(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if (components.scheme == "https" && components.port == 443) ||
            (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        if components.path.isEmpty { components.path = "/" }
        return components.string ?? url.absoluteString
    }

    static func merge(_ incoming: [Station], into existing: [Station]) -> ImportResult {
        var result = existing
        var urls = Set(existing.flatMap { $0.streams.map { urlKey($0.url) } })
        var ids = Set(existing.map(\.id))

        for station in incoming {
            var stationURLs = Set<String>()
            let uniqueStreams = station.streams.filter { stationURLs.insert(urlKey($0.url)).inserted }
            let keys = Set(uniqueStreams.map { urlKey($0.url) })
            guard urls.isDisjoint(with: keys) else { continue }
            urls.formUnion(keys)
            let id = uniqueID(station.id, existing: &ids)
            result.append(Station(
                id: id, name: station.name, region: station.region,
                group: station.group, city: station.city, category: station.category,
                language: station.language, aliases: station.aliases,
                official: station.official, source: station.source, streams: uniqueStreams
            ))
        }
        let added = result.count - existing.count
        return ImportResult(stations: result, added: added, duplicates: incoming.count - added, incomingCount: incoming.count)
    }

    static func encode(_ stations: [Station], updatedAt: Date = Date()) throws -> Data {
        guard stations.count <= maximumStations else { throw Failure.tooManySavedStations }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let document = StationCatalog(
            schemaVersion: 1,
            sourceUpdatedAt: ISO8601DateFormatter().string(from: updatedAt),
            validation: "user-provided",
            stations: stations
        )
        let data = try encoder.encode(document)
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        return data
    }

    private static func normalizedID(_ value: String?) -> String {
        guard let value else { return UUID().uuidString }
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? UUID().uuidString : id
    }

    private static func uniqueID(_ requested: String, existing ids: inout Set<String>) -> String {
        guard ids.contains(requested) else { ids.insert(requested); return requested }
        var replacement = UUID().uuidString
        while ids.contains(replacement) { replacement = UUID().uuidString }
        ids.insert(replacement)
        return replacement
    }
}

enum NetworkStationCatalog {
    static func download(from address: String, session: URLSession = .shared) async throws -> Data {
        let url = try PersonalCatalog.validatedURL(address)
        guard url.scheme?.lowercased() == "https" else { throw PersonalCatalog.Failure.httpsRequired }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json, text/plain;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else {
            throw PersonalCatalog.Failure.httpStatus(0)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw PersonalCatalog.Failure.httpStatus(response.statusCode)
        }
        guard response.url?.scheme?.lowercased() == "https" else {
            throw PersonalCatalog.Failure.unsafeRedirect
        }
        if response.expectedContentLength > PersonalCatalog.maximumBytes {
            throw PersonalCatalog.Failure.tooLarge
        }

        var data = Data()
        if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
        for try await byte in bytes {
            if data.count.isMultiple(of: 8192) { try Task.checkCancellation() }
            guard data.count < PersonalCatalog.maximumBytes else { throw PersonalCatalog.Failure.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }
}
