import Foundation

// MARK: - XML tree

final class XMLNode {
    let name: String
    let namespaceURI: String?
    var attributes: [String: String]
    var children: [XMLNode] = []
    var text = ""

    init(name: String, namespaceURI: String? = nil, attributes: [String: String] = [:]) {
        self.name = name
        self.namespaceURI = namespaceURI
        self.attributes = attributes
    }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    func child(_ name: String) -> XMLNode? {
        children.first { $0.name == name }
    }

    func children(named name: String) -> [XMLNode] {
        children.filter { $0.name == name }
    }

    func firstDescendant(_ name: String) -> XMLNode? {
        if self.name == name { return self }
        for child in children {
            if let match = child.firstDescendant(name) { return match }
        }
        return nil
    }
}

enum XMLTree {
    static func parse(_ data: Data) throws -> XMLNode {
        do {
            return try parseOnce(data)
        } catch {
            guard let string = String(data: data, encoding: .utf8) else { throw error }
            let sanitized = string.replacingOccurrences(
                of: "&(?!(?:amp|lt|gt|quot|apos|#\\d+|#x[0-9A-Fa-f]+);)",
                with: "&amp;",
                options: .regularExpression
            )
            guard sanitized != string, let sanitizedData = sanitized.data(using: .utf8) else { throw error }
            return try parseOnce(sanitizedData)
        }
    }

    static func parse(_ string: String) throws -> XMLNode {
        guard let data = string.data(using: .utf8) else {
            throw MediaFailure("无法读取设备描述。")
        }
        return try parse(data)
    }

    private static func parseOnce(_ data: Data) throws -> XMLNode {
        let builder = XMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw builder.failure ?? MediaFailure("无法读取设备描述。", detail: parser.parserError?.localizedDescription)
        }
        return builder.document
    }
}

private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    let document = XMLNode(name: "#document")
    private var stack: [XMLNode] = []
    var failure: Error?

    override init() {
        super.init()
        stack = [document]
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = XMLNode(name: elementName, namespaceURI: namespaceURI, attributes: attributeDict)
        stack.last?.children.append(node)
        stack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard stack.count > 1 else { return }
        stack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            stack.last?.text += string
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        failure = parseError
    }
}

// MARK: - SSDP

struct SSDPResponse: Equatable, Sendable {
    let location: URL
    let searchTarget: String?
    let usn: String?
    let server: String?
}

enum SSDPDiscovery {
    static let mediaServerTarget = "urn:schemas-upnp-org:device:MediaServer:1"

    static func discover(timeout: TimeInterval = 3) -> [SSDPResponse] {
        let targets = [mediaServerTarget, "ssdp:all"]
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        var ttl: UInt8 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
        var loop: UInt8 = 1
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<UInt8>.size))
        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))

        var bindAddress = sockaddr_in()
        bindAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddress.sin_family = sa_family_t(AF_INET)
        bindAddress.sin_port = 0
        bindAddress.sin_addr.s_addr = INADDR_ANY
        _ = withUnsafePointer(to: &bindAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(1900).bigEndian
        guard inet_pton(AF_INET, "239.255.255.250", &address.sin_addr) == 1 else { return [] }

        let interfaces = activeIPv4Interfaces()
        let messages: [Data] = targets.compactMap { target in
            """
            M-SEARCH * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            MAN: "ssdp:discover"\r
            MX: 2\r
            ST: \(target)\r
            \r
            
            """.data(using: .utf8)
        }

        var responses: [String: SSDPResponse] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        var nextProbe = Date()
        var buffer = [UInt8](repeating: 0, count: 65_535)

        while Date() < deadline {
            if Date() >= nextProbe {
                for data in messages {
                    if interfaces.isEmpty {
                        send(data, to: address, fd: fd)
                    } else {
                        for interfaceAddress in interfaces {
                            var local = interfaceAddress
                            setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &local, socklen_t(MemoryLayout<in_addr>.size))
                            send(data, to: address, fd: fd)
                        }
                    }
                }
                // Re-probe while the local-network permission prompt is on screen
                // or when a single multicast packet is lost.
                nextProbe = Date().addingTimeInterval(2)
            }

            var source = sockaddr_storage()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let received = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return withUnsafeMutablePointer(to: &source) { sourcePointer in
                    sourcePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                        recvfrom(fd, base, raw.count, 0, sockaddrPointer, &sourceLength)
                    }
                }
            }
            guard received > 0 else { continue }
            let data = Data(buffer[0..<received])
            guard let response = parse(data) else { continue }
            let key = response.location.absoluteString
            if let previous = responses[key] {
                // A media-server response is more useful than a generic root-device response.
                if previous.searchTarget?.contains("MediaServer") == true { continue }
            }
            responses[key] = response
        }
        return Array(responses.values)
    }

    private static func activeIPv4Interfaces() -> [in_addr] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return [] }
        defer { freeifaddrs(head) }
        var addresses: [in_addr] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let pointer = cursor {
            defer { cursor = pointer.pointee.ifa_next }
            guard let socketAddress = pointer.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let flags = Int32(pointer.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, flags & IFF_MULTICAST != 0 else { continue }
            let address = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            guard address.sin_addr.s_addr != 0 else { continue }
            if !addresses.contains(where: { $0.s_addr == address.sin_addr.s_addr }) {
                addresses.append(address.sin_addr)
            }
        }
        return addresses
    }

    private static func send(_ data: Data, to address: sockaddr_in, fd: Int32) {
        var address = address
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    _ = sendto(fd, base, raw.count, 0, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    /// Parses a single SSDP reply. Kept separate so header handling is testable.
    static func parse(_ data: Data) -> SSDPResponse? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard let status = lines.first, status.contains("200") else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { headers[key] = value }
        }
        guard let locationText = headers["location"],
              let location = URL(string: locationText),
              let scheme = location.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return SSDPResponse(
            location: location,
            searchTarget: headers["st"],
            usn: headers["usn"],
            server: headers["server"]
        )
    }
}

// MARK: - Device description

struct UPnPDevice: Identifiable, Hashable, Sendable {
    let id: String
    let udn: String?
    let name: String
    let model: String?
    let location: URL
    let serviceType: String
    let controlURL: URL
    let baseURL: URL
}

enum UPnPDescriptionParser {
    static func devices(from data: Data, location: URL) throws -> [UPnPDevice] {
        let document = try XMLTree.parse(data)
        let root = document.firstDescendant("root") ?? document
        let urlBase = root.child("URLBase").flatMap { resolve($0.trimmedText, base: location) } ?? location
        let base = urlBase

        guard let rootDevice = root.child("device") else {
            throw MediaFailure("无法读取设备描述。")
        }
        var devices: [UPnPDevice] = []
        walk(rootDevice, base: base, location: location, inheritedName: nil, into: &devices)
        return devices
    }

    private static func walk(
        _ node: XMLNode,
        base: URL,
        location: URL,
        inheritedName: String?,
        into devices: inout [UPnPDevice]
    ) {
        let friendlyName = node.child("friendlyName")?.trimmedText
        let name = friendlyName.flatMap { $0.isEmpty ? nil : $0 } ?? inheritedName ?? "UPnP"
        let model = node.child("modelName")?.trimmedText
        let udn = node.child("UDN")?.trimmedText
        let deviceID = udn.flatMap { $0.isEmpty ? nil : $0 } ?? location.absoluteString

        var contentDirectories: [(type: String, control: URL)] = []
        for service in node.child("serviceList")?.children(named: "service") ?? [] {
            let type = service.child("serviceType")?.trimmedText ?? ""
            guard type.contains("ContentDirectory") else { continue }
            guard let controlText = service.child("controlURL")?.trimmedText,
                  let control = resolve(controlText, base: base) else { continue }
            contentDirectories.append((type, control))
        }

        for (index, service) in contentDirectories.enumerated() {
            let suffix = contentDirectories.count > 1 ? "#\(index)" : ""
            devices.append(UPnPDevice(
                id: "\(deviceID)#\(service.control.absoluteString)\(suffix)",
                udn: udn.flatMap { $0.isEmpty ? nil : $0 },
                name: name,
                model: model?.isEmpty == true ? nil : model,
                location: location,
                serviceType: service.type,
                controlURL: service.control,
                baseURL: base
            ))
        }

        for child in node.child("deviceList")?.children(named: "device") ?? [] {
            walk(child, base: base, location: location, inheritedName: name, into: &devices)
        }
    }

    static func resolve(_ value: String, base: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        let escaped = trimmed.replacingOccurrences(of: " ", with: "%20")
        let directory = base.hasDirectoryPath ? base : base.deletingLastPathComponent()
        if escaped.hasPrefix("/") {
            return URL(string: escaped, relativeTo: base)?.absoluteURL
        }
        return URL(string: escaped, relativeTo: directory)?.absoluteURL
    }
}

// MARK: - SOAP / DIDL

struct UPnPPage: Sendable {
    let entries: [MediaEntry]
    let totalMatches: Int
    let numberReturned: Int
}

struct DIDLResource: Sendable {
    let url: URL
    let protocolInfo: String
    let mimeType: String
    let duration: TimeInterval?
    let size: Int64?

    var isAudio: Bool {
        let mime = mimeType.lowercased()
        return mime.hasPrefix("audio/")
            || mime == "application/ogg"
            || mime == "application/flac"
            || mime == "application/x-flac"
            || mime == "application/x-ogg"
    }

    var isHTTP: Bool {
        let method = protocolInfo.split(separator: ":", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return method == "http-get" || method == "https-get" || method.isEmpty
    }
}

enum DIDLParser {
    static func entries(from didl: String, baseURL: URL) throws -> [MediaEntry] {
        guard !didl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let document = try XMLTree.parse(didl)
        let root = document.firstDescendant("DIDL-Lite") ?? document
        var entries: [MediaEntry] = []
        for node in root.children {
            switch node.name {
            case "container":
                entries.append(containerEntry(node, baseURL: baseURL))
            case "item":
                if let entry = itemEntry(node, baseURL: baseURL) {
                    entries.append(entry)
                }
            default:
                continue
            }
        }
        return entries
    }

    private static func containerEntry(_ node: XMLNode, baseURL: URL) -> MediaEntry {
        let objectID = node.attributes["id"] ?? UUID().uuidString
        let title = node.child("title")?.trimmedText ?? "Untitled"
        let artwork = node.child("albumArtURI").flatMap { UPnPDescriptionParser.resolve($0.trimmedText, base: baseURL) }
        let childCount = node.attributes["childCount"].flatMap { Int($0) }
        return MediaEntry(
            id: "container:\(objectID)",
            objectID: objectID,
            name: title,
            kind: .container,
            detail: nil,
            artist: nil,
            album: nil,
            audioURL: nil,
            artworkURL: artwork,
            duration: nil,
            format: nil,
            size: nil,
            childCount: childCount
        )
    }

    private static func itemEntry(_ node: XMLNode, baseURL: URL) -> MediaEntry? {
        let objectID = node.attributes["id"] ?? UUID().uuidString
        let title = node.child("title")?.trimmedText ?? "Untitled"
        let upnpClass = node.child("class")?.trimmedText ?? ""
        let artist = node.child("artist")?.trimmedText
        let album = node.child("album")?.trimmedText
        let artwork = node.child("albumArtURI").flatMap { UPnPDescriptionParser.resolve($0.trimmedText, base: baseURL) }

        let resources: [DIDLResource] = node.children(named: "res").compactMap { resource in
            guard let url = UPnPDescriptionParser.resolve(resource.trimmedText, base: baseURL) else { return nil }
            if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" { return nil }
            let protocolInfo = resource.attributes["protocolInfo"] ?? ""
            let pieces = protocolInfo.split(separator: ":", omittingEmptySubsequences: false)
            let mime = pieces.count > 2 ? String(pieces[2]) : ""
            return DIDLResource(
                url: url,
                protocolInfo: protocolInfo,
                mimeType: mime,
                duration: AudioFile.parseDuration(resource.attributes["duration"]),
                size: resource.attributes["size"].flatMap { Int64($0) }
            )
        }

        let audioClass = upnpClass.contains("audioItem") || upnpClass.contains("musicTrack")
        guard let resource = bestResource(from: resources, audioClass: audioClass) else { return nil }
        guard resource.isAudio
            || AudioFile.isAudioFile(resource.url)
            || (audioClass && (resource.mimeType.isEmpty || resource.mimeType == "*")) else { return nil }
        guard resource.isHTTP else { return nil }

        let format = AudioFile.formatLabel(mimeType: resource.mimeType, url: resource.url)
        let detail = [artist, album].compactMap { $0?.isEmpty == true ? nil : $0 }.joined(separator: " · ")
        return MediaEntry(
            id: "item:\(objectID):\(resource.url.absoluteString)",
            objectID: objectID,
            name: title,
            kind: .audio,
            detail: detail.isEmpty ? nil : detail,
            artist: artist?.isEmpty == true ? nil : artist,
            album: album?.isEmpty == true ? nil : album,
            audioURL: resource.url,
            artworkURL: artwork,
            duration: resource.duration,
            format: format,
            size: resource.size,
            childCount: nil
        )
    }

    private static func bestResource(from resources: [DIDLResource], audioClass: Bool) -> DIDLResource? {
        let ranked = resources.sorted { lhs, rhs in
            score(lhs, audioClass: audioClass) < score(rhs, audioClass: audioClass)
        }
        return ranked.first { $0.isAudio } ?? (audioClass ? ranked.first : nil) ?? ranked.first
    }

    private static func score(_ resource: DIDLResource, audioClass: Bool) -> Int {
        var score = 0
        if !resource.isAudio { score += 4 }
        if !resource.isHTTP { score += 8 }
        if resource.url.scheme?.lowercased() == "https" { score -= 1 }
        if resource.mimeType.isEmpty { score += audioClass ? 1 : 2 }
        return score
    }
}

enum UPnPSOAP {
    static func browseEnvelope(objectID: String, serviceType: String, start: Int, count: Int) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:Browse xmlns:u="\(escape(serviceType))">
        <ObjectID>\(escape(objectID))</ObjectID>
        <BrowseFlag>BrowseDirectChildren</BrowseFlag>
        <Filter>*</Filter>
        <StartingIndex>\(start)</StartingIndex>
        <RequestedCount>\(count)</RequestedCount>
        <SortCriteria></SortCriteria>
        </u:Browse>
        </s:Body>
        </s:Envelope>
        """
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - UPnP client

struct UPnPClient: Sendable {
    let session: URLSession

    init(session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()) {
        self.session = session
    }

    func fetchDevices(descriptionURL: URL) async throws -> [UPnPDevice] {
        var request = URLRequest(url: descriptionURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Wavelet/1.2 (macOS)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw MediaFailure("无法读取设备描述。", detail: "HTTP \(http.statusCode)")
            }
            let devices = try UPnPDescriptionParser.devices(from: data, location: descriptionURL)
            guard !devices.isEmpty else { throw MediaFailure("未找到 UPnP 内容目录服务。") }
            return devices
        } catch let failure as MediaFailure {
            throw failure
        } catch {
            throw MediaFailure("网络请求失败。", detail: error.localizedDescription)
        }
    }

    func browsePage(device: UPnPDevice, objectID: String, start: Int, count: Int) async throws -> UPnPPage {
        var request = URLRequest(url: device.controlURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(device.serviceType)#Browse\"", forHTTPHeaderField: "SOAPACTION")
        request.setValue("Wavelet/1.2 (macOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = UPnPSOAP.browseEnvelope(
            objectID: objectID,
            serviceType: device.serviceType,
            start: start,
            count: count
        ).data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw MediaFailure("UPnP 服务器返回错误。", detail: "HTTP \(http.statusCode)", status: Int32(http.statusCode))
            }
            return try parseBrowseResponse(data, device: device)
        } catch let failure as MediaFailure {
            throw failure
        } catch {
            throw MediaFailure("网络请求失败。", detail: error.localizedDescription)
        }
    }

    func browseAll(
        device: UPnPDevice,
        objectID: String,
        pageSize: Int = 250,
        maximumItems: Int = 5_000
    ) async throws -> [MediaEntry] {
        var entries: [MediaEntry] = []
        var seen = Set<String>()
        var start = 0
        var total = Int.max
        while entries.count < maximumItems {
            let page = try await browsePage(device: device, objectID: objectID, start: start, count: pageSize)
            let newEntries = page.entries.filter { seen.insert($0.id).inserted }
            guard !newEntries.isEmpty else { break }
            entries.append(contentsOf: newEntries)
            total = page.totalMatches
            let returned = max(page.numberReturned, page.entries.count)
            guard returned > 0 else { break }
            start += returned
            if start >= total { break }
        }
        return Array(entries.prefix(maximumItems))
    }

    private func parseBrowseResponse(_ data: Data, device: UPnPDevice) throws -> UPnPPage {
        let document = try XMLTree.parse(data)
        if let fault = document.firstDescendant("Fault") {
            let code = fault.firstDescendant("errorCode")?.trimmedText
            let description = fault.firstDescendant("errorDescription")?.trimmedText
            throw MediaFailure(
                "UPnP 服务器返回错误。",
                detail: [code, description].compactMap { $0 }.joined(separator: " · ")
            )
        }
        guard let body = document.firstDescendant("Body") else {
            throw MediaFailure("UPnP 服务器返回错误。", detail: "Missing SOAP body")
        }
        let responseNode = body.children.first
        guard let responseNode else { return UPnPPage(entries: [], totalMatches: 0, numberReturned: 0) }
        let resultXML = responseNode.child("Result")?.text ?? ""
        let total = Int(responseNode.child("TotalMatches")?.trimmedText ?? "") ?? Int.max
        let returned = Int(responseNode.child("NumberReturned")?.trimmedText ?? "") ?? 0
        let entries = try DIDLParser.entries(from: resultXML, baseURL: device.baseURL)
        return UPnPPage(entries: entries, totalMatches: max(total, entries.count), numberReturned: max(returned, entries.count))
    }
}

enum UPnPDiscovery {
    static func discover(timeout: TimeInterval = 3) async -> [UPnPDevice] {
        let responses = await Task.detached(priority: .userInitiated) {
            SSDPDiscovery.discover(timeout: timeout)
        }.value
        guard !responses.isEmpty else { return [] }

        var seenLocations = Set<String>()
        let locations = responses.compactMap { response -> URL? in
            let key = response.location.absoluteString
            return seenLocations.insert(key).inserted ? response.location : nil
        }

        var devices: [UPnPDevice] = []
        let client = UPnPClient()
        await withTaskGroup(of: [UPnPDevice].self) { group in
            for location in locations.prefix(8) {
                group.addTask {
                    (try? await client.fetchDevices(descriptionURL: location)) ?? []
                }
            }
            for await found in group {
                devices.append(contentsOf: found)
            }
        }
        var seenIDs = Set<String>()
        return devices
            .filter { seenIDs.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
