import AVFoundation
import Foundation
import XCTest
@testable import WaveletMac

final class MediaTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "WaveletMediaTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    private static func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaveletMediaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: DIDL

    func testDIDLParsesFoldersAndAudioResources() throws {
        let didl = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
          <container id="1$3" parentID="0" childCount="3">
            <dc:title>Albums</dc:title>
            <upnp:albumArtURI>/art/folder.jpg</upnp:albumArtURI>
          </container>
          <item id="2$7" parentID="0">
            <dc:title>Song &amp; More</dc:title>
            <upnp:artist>Artist</upnp:artist>
            <upnp:album>Album</upnp:album>
            <upnp:class>object.item.audioItem.musicTrack</upnp:class>
            <res protocolInfo="http-get:*:audio/flac:*" duration="0:03:21.500" size="12345">/music/01.flac</res>
            <res protocolInfo="http-get:*:image/jpeg:*">/art/cover.jpg</res>
          </item>
        </DIDL-Lite>
        """
        let base = try XCTUnwrap(URL(string: "http://192.168.1.2:8200/desc.xml"))
        let entries = try DIDLParser.entries(from: didl, baseURL: base)

        XCTAssertEqual(entries.count, 2)
        let container = try XCTUnwrap(entries.first { $0.kind == .container })
        XCTAssertEqual(container.name, "Albums")
        XCTAssertEqual(container.objectID, "1$3")
        XCTAssertEqual(container.childCount, 3)
        XCTAssertEqual(container.artworkURL?.absoluteString, "http://192.168.1.2:8200/art/folder.jpg")

        let audio = try XCTUnwrap(entries.first { $0.kind == .audio })
        XCTAssertEqual(audio.name, "Song & More")
        XCTAssertEqual(audio.artist, "Artist")
        XCTAssertEqual(audio.album, "Album")
        XCTAssertEqual(audio.format, "FLAC")
        XCTAssertEqual(audio.duration, 201.5)
        XCTAssertEqual(audio.size, 12_345)
        XCTAssertEqual(audio.audioURL?.absoluteString, "http://192.168.1.2:8200/music/01.flac")
    }

    func testDIDLRejectsVideoOnlyItems() throws {
        let didl = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
          <item id="9" parentID="0">
            <dc:title>Movie</dc:title>
            <upnp:class>object.item.videoItem</upnp:class>
            <res protocolInfo="http-get:*:video/mp4:*">/movie.mp4</res>
          </item>
        </DIDL-Lite>
        """
        let base = try XCTUnwrap(URL(string: "http://192.168.1.2:8200/desc.xml"))
        XCTAssertTrue(try DIDLParser.entries(from: didl, baseURL: base).isEmpty)
    }

    func testDescriptionParserFindsNestedContentDirectoriesAndURLBase() throws {
        let xml = """
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <URLBase>http://base.local:9000/</URLBase>
          <device>
            <friendlyName>Root Server</friendlyName>
            <UDN>uuid:root</UDN>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>
                <controlURL>/ctl</controlURL>
              </service>
            </serviceList>
            <deviceList>
              <device>
                <friendlyName>Music Library</friendlyName>
                <UDN>uuid:music</UDN>
                <serviceList>
                  <service>
                    <serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>
                    <controlURL>sub/ctl</controlURL>
                  </service>
                </serviceList>
              </device>
            </deviceList>
          </device>
        </root>
        """
        let location = try XCTUnwrap(URL(string: "http://host/desc.xml"))
        let devices = try UPnPDescriptionParser.devices(from: Data(xml.utf8), location: location)
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices.first?.name, "Root Server")
        XCTAssertEqual(devices.first?.controlURL.absoluteString, "http://base.local:9000/ctl")
        XCTAssertEqual(devices.last?.name, "Music Library")
        XCTAssertEqual(devices.last?.controlURL.absoluteString, "http://base.local:9000/sub/ctl")
    }

    func testDescriptionParserRejectsDevicesWithoutContentDirectory() throws {
        let xml = """
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <device>
            <friendlyName>Router</friendlyName>
            <UDN>uuid:router</UDN>
          </device>
        </root>
        """
        let devices = try UPnPDescriptionParser.devices(
            from: Data(xml.utf8),
            location: URL(string: "http://host/desc.xml")!
        )
        XCTAssertTrue(devices.isEmpty)
    }

    func testDIDLHandlesCDATAAndEscapedResult() throws {
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
              <Result>&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/"&gt;&lt;item id="1"&gt;&lt;dc:title&gt;A &amp;amp; B&lt;/dc:title&gt;&lt;res protocolInfo="http-get:*:audio/mpeg:*"&gt;http://host/a.mp3&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</Result>
              <NumberReturned>1</NumberReturned>
              <TotalMatches>1</TotalMatches>
            </u:BrowseResponse>
          </s:Body>
        </s:Envelope>
        """
        let root = try XMLTree.parse(xml)
        let body = try XCTUnwrap(root.firstDescendant("Body"))
        let response = try XCTUnwrap(body.children.first)
        let result = try XCTUnwrap(response.child("Result")).text
        let entries = try DIDLParser.entries(from: result, baseURL: URL(string: "http://host/desc.xml")!)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "A & B")
    }

    func testSOAPEnvelopeEscapesUserControlledObjectID() {
        let envelope = UPnPSOAP.browseEnvelope(
            objectID: "a&b<c>\"d'",
            serviceType: "urn:schemas-upnp-org:service:ContentDirectory:1",
            start: 10,
            count: 250
        )
        XCTAssertTrue(envelope.contains("<ObjectID>a&amp;b&lt;c&gt;&quot;d&apos;</ObjectID>"))
        XCTAssertTrue(envelope.contains("<StartingIndex>10</StartingIndex>"))
        XCTAssertTrue(envelope.contains("<RequestedCount>250</RequestedCount>"))
        XCTAssertFalse(envelope.contains("<ObjectID>a&b"))
    }

    // MARK: SSDP

    func testSSDPResponseParsingIsCaseInsensitive() throws {
        let response = """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age=1800\r
        Location: http://192.168.1.9:8080/desc.xml\r
        ST: urn:schemas-upnp-org:device:MediaServer:1\r
        USN: uuid:abc::urn:schemas-upnp-org:device:MediaServer:1\r
        SERVER: Linux/5 UPnP/1.0 test/1.0\r
        \r
        
        """
        let parsed = try XCTUnwrap(SSDPDiscovery.parse(Data(response.utf8)))
        XCTAssertEqual(parsed.location.absoluteString, "http://192.168.1.9:8080/desc.xml")
        XCTAssertEqual(parsed.searchTarget, "urn:schemas-upnp-org:device:MediaServer:1")
        XCTAssertEqual(parsed.usn, "uuid:abc::urn:schemas-upnp-org:device:MediaServer:1")
    }

    func testSSDPRejectsIncompleteResponses() {
        XCTAssertNil(SSDPDiscovery.parse(Data("NOTIFY * HTTP/1.1\r\nLOCATION: http://host/x\r\n\r\n".utf8)))
        XCTAssertNil(SSDPDiscovery.parse(Data("HTTP/1.1 200 OK\r\nST: ssdp:all\r\n\r\n".utf8)))
        XCTAssertNil(SSDPDiscovery.parse(Data("HTTP/1.1 200 OK\r\nLOCATION: ftp://host/x\r\n\r\n".utf8)))
    }

    // MARK: SMB

    func testSMBAddressNormalizationAndURL() throws {
        let url = try XCTUnwrap(SMBAddress.shareURL(host: "smb://user@nas.local:445/share/ignored", share: "Music"))
        XCTAssertEqual(url.scheme, "smb")
        XCTAssertEqual(url.host, "nas.local")
        XCTAssertEqual(url.port, 445)
        XCTAssertEqual(url.path, "/Music")

        XCTAssertNil(SMBAddress.normalizedShare(""))
        XCTAssertNil(SMBAddress.normalizedShare("a/b"))
        XCTAssertNil(SMBAddress.shareURL(host: "", share: "Music"))
        XCTAssertEqual(SMBAddress.normalizedHost("  nas.local  "), "nas.local")
        XCTAssertEqual(SMBAddress.normalizedHost("smb://nas.local/Media"), "nas.local")
    }

    func testSMBFailureMessagesCoverCommonStatuses() {
        XCTAssertEqual(SMBMountManager.mountFailure(13).messageKey, "认证失败，请检查用户名和密码。")
        XCTAssertEqual(SMBMountManager.mountFailure(60).messageKey, "连接超时，请检查服务器地址。")
        XCTAssertEqual(SMBMountManager.mountFailure(-128).messageKey, "已取消连接。")
        XCTAssertEqual(SMBMountManager.mountFailure(-5998).messageKey, "服务器没有可用的共享。")
        XCTAssertEqual(SMBMountManager.mountFailure(-6606).messageKey, "无法挂载 SMB 共享，请检查地址、共享名称和凭据。")
    }

    // MARK: Files

    func testAudioFormatAndDurationHelpers() {
        XCTAssertTrue(AudioFile.isAudioFile(URL(fileURLWithPath: "/Music/a.FLAC")))
        XCTAssertFalse(AudioFile.isAudioFile(URL(fileURLWithPath: "/Music/a.txt")))
        XCTAssertEqual(AudioFile.formatLabel(for: URL(fileURLWithPath: "/a.flac")), "FLAC")
        XCTAssertEqual(AudioFile.durationLabel(201.5), "3:22")
        XCTAssertEqual(AudioFile.durationLabel(3_661), "1:01:01")
        XCTAssertNil(AudioFile.durationLabel(-1))
        XCTAssertEqual(AudioFile.parseDuration("0:03:21.500"), 201.5)
        XCTAssertEqual(AudioFile.parseDuration("3:21"), 201)
        XCTAssertNil(AudioFile.parseDuration("nope"))
    }

    func testFileBrowserListsFoldersFirstAndFiltersNonAudio() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("song.mp3"))
        try Data().write(to: directory.appendingPathComponent("notes.txt"))
        try Data().write(to: directory.appendingPathComponent("cover.jpg"))

        let entries = try FileMediaBrowser.entries(in: directory, root: directory)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.kind, .container)
        XCTAssertEqual(entries.first?.name, "Sub")
        XCTAssertEqual(entries.last?.kind, .audio)
        XCTAssertEqual(entries.last?.name, "song")
        XCTAssertEqual(entries.last?.format, "MP3")
        XCTAssertEqual(entries.last?.objectID, "song.mp3")
    }

    func testFileBrowserResolveRejectsTraversal() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try FileMediaBrowser.resolve(relativePath: "../outside.mp3", in: directory))
        XCTAssertThrowsError(try FileMediaBrowser.resolve(relativePath: "missing.mp3", in: directory))
    }

    // MARK: Store

    @MainActor
    func testFolderSourcePersistsAndBrowses() async throws {
        let (defaults, suite) = try makeDefaults()
        let directory = try makeDirectory()
        let mounts = directory.appendingPathComponent("mounts", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("song.mp3"))
        try Data().write(to: directory.appendingPathComponent("readme.txt"))

        let player = PlaybackEngine(defaults: defaults)
        let manager = SMBMountManager(baseDirectory: mounts)
        let store = LocalMediaStore(player: player, defaults: defaults, mountManager: manager)
        await store.addFolder(directory)

        XCTAssertEqual(store.folderSources.count, 1)
        XCTAssertEqual(store.selectedSource?.kind, .folder)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.first?.kind, .container)
        XCTAssertEqual(store.audioCount, 1)
        XCTAssertTrue(store.canGoBack == false)

        store.searchText = "song"
        XCTAssertEqual(store.visibleEntries.count, 1)
        XCTAssertEqual(store.visibleEntries.first?.kind, .audio)
        store.searchText = ""

        await store.open(try XCTUnwrap(store.entries.first { $0.kind == .container }))
        XCTAssertEqual(store.path.count, 2)
        XCTAssertTrue(store.canGoBack)
        await store.goBack()
        XCTAssertEqual(store.path.count, 1)

        let secondStore = LocalMediaStore(player: PlaybackEngine(defaults: defaults), defaults: defaults, mountManager: manager)
        XCTAssertEqual(secondStore.folderSources.count, 1)
        XCTAssertEqual(secondStore.folderSources.first?.path, directory.standardizedFileURL.path)
    }

    @MainActor
    func testRemovingSourceClearsSelection() async throws {
        let (defaults, suite) = try makeDefaults()
        let directory = try makeDirectory()
        let mounts = directory.appendingPathComponent("mounts", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try Data().write(to: directory.appendingPathComponent("song.mp3"))
        let store = LocalMediaStore(
            player: PlaybackEngine(defaults: defaults),
            defaults: defaults,
            mountManager: SMBMountManager(baseDirectory: mounts)
        )
        await store.addFolder(directory)
        let source = try XCTUnwrap(store.selectedSource)
        store.removeSource(source)
        XCTAssertTrue(store.folderSources.isEmpty)
        XCTAssertNil(store.selectedSource)
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testUPnPStoreBrowsesFoldersAndQueuesAudio() async throws {
        let (defaults, suite) = try makeDefaults()
        let directory = try makeDirectory()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        MediaURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/rootDesc.xml" {
                let xml = """
                <root xmlns="urn:schemas-upnp-org:device-1-0">
                  <device>
                    <friendlyName>Mock DLNA</friendlyName>
                    <UDN>uuid:mock</UDN>
                    <serviceList>
                      <service>
                        <serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>
                        <controlURL>http://mock/ctl</controlURL>
                      </service>
                    </serviceList>
                  </device>
                </root>
                """
                let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (http, Data(xml.utf8))
            }
            let body = String(data: Self.requestBody(request), encoding: .utf8) ?? ""
            let objectID = body.contains("<ObjectID>1</ObjectID>") ? "1" : "0"
            let didl: String
            if objectID == "1" {
                didl = """
                <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
                  <item id="11"><dc:title>First Song</dc:title><upnp:artist>Artist</upnp:artist><upnp:class>object.item.audioItem.musicTrack</upnp:class><res protocolInfo="http-get:*:audio/wav:*">http://mock/1.wav</res></item>
                  <item id="12"><dc:title>Second Song</dc:title><upnp:artist>Artist</upnp:artist><upnp:class>object.item.audioItem.musicTrack</upnp:class><res protocolInfo="http-get:*:audio/wav:*">http://mock/2.wav</res></item>
                </DIDL-Lite>
                """
            } else {
                didl = """
                <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
                  <container id="1" childCount="2"><dc:title>Album</dc:title><upnp:class>object.container.album.musicAlbum</upnp:class></container>
                  <item id="2"><dc:title>Root Song</dc:title><upnp:class>object.item.audioItem.musicTrack</upnp:class><res protocolInfo="http-get:*:audio/wav:*">http://mock/root.wav</res></item>
                </DIDL-Lite>
                """
            }
            let escaped = didl.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            let response = """
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
            <u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
            <Result>\(escaped)</Result><NumberReturned>2</NumberReturned><TotalMatches>2</TotalMatches>
            </u:BrowseResponse></s:Body></s:Envelope>
            """
            let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (http, Data(response.utf8))
        }
        defer { MediaURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaURLProtocol.self]
        let client = UPnPClient(session: URLSession(configuration: configuration))
        let store = LocalMediaStore(
            player: PlaybackEngine(defaults: defaults),
            defaults: defaults,
            mountManager: SMBMountManager(baseDirectory: directory.appendingPathComponent("mounts", isDirectory: true)),
            client: client
        )

        let added = await store.addUPnPSource(address: "http://mock/rootDesc.xml")
        XCTAssertTrue(added)
        XCTAssertEqual(store.upnpSources.count, 1)
        XCTAssertEqual(store.selectedSource?.kind, .upnp)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.audioCount, 1)

        await store.open(try XCTUnwrap(store.entries.first { $0.kind == .container }))
        XCTAssertEqual(store.path.count, 2)
        XCTAssertEqual(store.entries.count, 2)
        let first = try XCTUnwrap(store.entries.first { $0.isPlayable })
        store.play(first)
        XCTAssertEqual(store.player.localTrack?.title, "First Song")
        XCTAssertEqual(store.player.localQueue.count, 2)
        XCTAssertTrue(store.player.localTrack?.isNetworkSource == true)
        store.player.clearLocalPlayback()
    }

    @MainActor
    func testSMBSourceValidationAndPersistence() throws {
        let (defaults, suite) = try makeDefaults()
        let directory = try makeDirectory()
        let mounts = directory.appendingPathComponent("mounts", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let manager = SMBMountManager(baseDirectory: mounts)
        let store = LocalMediaStore(
            player: PlaybackEngine(defaults: defaults),
            defaults: defaults,
            mountManager: manager
        )

        XCTAssertThrowsError(try store.saveSMB(
            SMBSourceConfig(id: "empty-host", name: "", host: "", share: "Music", username: "u", usesGuest: false, rememberPassword: false),
            password: nil
        ))
        XCTAssertThrowsError(try store.saveSMB(
            SMBSourceConfig(id: "empty-share", name: "", host: "nas.local", share: "", username: "u", usesGuest: false, rememberPassword: false),
            password: nil
        ))
        XCTAssertThrowsError(try store.saveSMB(
            SMBSourceConfig(id: "no-user", name: "", host: "nas.local", share: "Music", username: "", usesGuest: false, rememberPassword: false),
            password: nil
        ))

        let saved = try store.saveSMB(
            SMBSourceConfig(id: "smb-test", name: "", host: "nas.local", share: "Music", username: "guest", usesGuest: true, rememberPassword: false),
            password: nil
        )
        XCTAssertEqual(store.smbSources.count, 1)
        XCTAssertEqual(saved.host, "nas.local")
        XCTAssertEqual(saved.share, "Music")
        XCTAssertEqual(saved.displayName, "nas.local/Music")

        let reloaded = LocalMediaStore(
            player: PlaybackEngine(defaults: defaults),
            defaults: defaults,
            mountManager: manager
        )
        XCTAssertEqual(reloaded.smbSources.count, 1)
        XCTAssertEqual(reloaded.smbSourceRefs.first?.detail, "SMB · nas.local/Music")

        reloaded.removeSource(try XCTUnwrap(reloaded.smbSourceRefs.first))
        XCTAssertTrue(reloaded.smbSources.isEmpty)
    }

    @MainActor
    func testPlaybackEngineAcceptsLocalQueueAndClears() async throws {
        let (defaults, suite) = try makeDefaults()
        let directory = try makeDirectory()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("tone.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
        buffer.frameLength = 44_100
        try file.write(from: buffer)

        let player = PlaybackEngine(defaults: defaults)
        let track = LocalAudioTrack(
            id: "test-tone",
            title: "Test Tone",
            artist: "Wavelet",
            album: "Tests",
            url: url,
            artworkURL: nil,
            sourceID: "folder-test",
            sourceName: "Tests",
            format: "WAV",
            durationHint: nil,
            isNetworkSource: false
        )
        player.playLocal(track, queue: [track])

        XCTAssertEqual(player.localTrack?.title, "Test Tone")
        XCTAssertEqual(player.localQueue.count, 1)
        XCTAssertEqual(player.localIndex, 0)
        XCTAssertNil(player.station)
        XCTAssertTrue(player.hasPlayableItem)

        player.clearLocalPlayback()
        XCTAssertNil(player.localTrack)
        XCTAssertTrue(player.localQueue.isEmpty)
        XCTAssertEqual(player.state, .ready)
    }

    // MARK: Localization

    func testMediaTranslationsCoverEveryLanguage() {
        let expected = MacLocalization.languages.count
        for (key, row) in MacLocalization.mediaTranslations {
            XCTAssertEqual(row.count, expected, "Missing translation for \(key)")
            XCTAssertFalse(row.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), "Empty translation for \(key)")
        }
        XCTAssertEqual(MacLocalization.text("本地媒体", language: "英文"), "Local Media")
        XCTAssertEqual(MacLocalization.text("本地媒体", language: "日文"), "ローカルメディア")
        XCTAssertEqual(MacLocalization.text("本地媒体", language: "繁體中文"), "本地媒體")
    }

    // MARK: UPnP HTTP client

    func testBrowsePageBuildsRequestAndParsesResult() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = UPnPClient(session: session)

        MediaURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "SOAPACTION"), "\"urn:schemas-upnp-org:service:ContentDirectory:1#Browse\"")
            let body = String(data: Self.requestBody(request), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("<ObjectID>1&amp;2</ObjectID>"))
            let response = """
            <?xml version="1.0"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
              <s:Body>
                <u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
                  <Result>&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/"&gt;&lt;item id="7"&gt;&lt;dc:title&gt;Track&lt;/dc:title&gt;&lt;res protocolInfo="http-get:*:audio/mpeg:*"&gt;http://host/track.mp3&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</Result>
                  <NumberReturned>1</NumberReturned>
                  <TotalMatches>1</TotalMatches>
                </u:BrowseResponse>
              </s:Body>
            </s:Envelope>
            """
            let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/xml"])!
            return (http, Data(response.utf8))
        }
        defer { MediaURLProtocol.handler = nil }

        let device = UPnPDevice(
            id: "device",
            udn: "uuid:device",
            name: "Server",
            model: nil,
            location: URL(string: "http://host/desc.xml")!,
            serviceType: "urn:schemas-upnp-org:service:ContentDirectory:1",
            controlURL: URL(string: "http://host/control")!,
            baseURL: URL(string: "http://host/desc.xml")!
        )
        let page = try await client.browsePage(device: device, objectID: "1&2", start: 0, count: 100)
        XCTAssertEqual(page.totalMatches, 1)
        XCTAssertEqual(page.entries.count, 1)
        XCTAssertEqual(page.entries.first?.name, "Track")
        XCTAssertEqual(page.entries.first?.audioURL?.absoluteString, "http://host/track.mp3")
    }
}

private final class MediaURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
