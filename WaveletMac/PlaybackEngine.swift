@preconcurrency import AVFoundation
@preconcurrency import AppKit
import Combine
import Foundation
@preconcurrency import MediaPlayer
@preconcurrency import Network

enum PlaybackState: String {
    case ready = "准备就绪"
    case connecting = "正在连接"
    case buffering = "正在缓冲"
    case playing = "正在收听"
    case paused = "已暂停"
    case failed = "连接失败"

    var isActive: Bool {
        self == .connecting || self == .buffering || self == .playing
    }
}

@MainActor
final class PlaybackEngine: ObservableObject {
    @Published private(set) var station: Station?
    @Published private(set) var state: PlaybackState = .ready
    @Published private(set) var line = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var sleepDeadline: Date?
    @Published private(set) var now = Date()
    let volumeChanges = PassthroughSubject<Float, Never>()

    var volume: Float {
        didSet {
            volume = min(1, max(0, volume))
            player.volume = volume
            volumeChanges.send(volume)
            volumeSaveTask?.cancel()
            volumeSaveTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                self?.persistVolume()
            }
        }
    }

    private let player = AVPlayer()
    private let networkMonitor = NWPathMonitor()
    private let defaults: UserDefaults
    private let volumeKey = "wavelet.mac.volume.v1"
    private var isOnline = true
    private var triedLines = Set<Int>()
    private var lastProgressAt = Date()
    private var lastPosition = 0.0
    private var ticker: Task<Void, Never>?
    private var volumeSaveTask: Task<Void, Never>?
    private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var audioOutputMonitor: AudioOutputMonitor?

    var currentStreamURL: URL? {
        guard let station, station.streams.indices.contains(line) else { return nil }
        return station.streams[line].url
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        volume = min(1, max(0, defaults.object(forKey: volumeKey) as? Float ?? 0.65))
        player.volume = volume
        player.automaticallyWaitsToMinimizeStalling = true
        player.preventsDisplaySleepDuringVideoPlayback = false

        networkMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                isOnline = online
                if !online && state.isActive {
                    fail("网络已断开。恢复网络后，请点击播放重连。")
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "WaveletMac.NetworkMonitor"))

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceNotifications.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pauseForSystemChange("Mac 已进入睡眠。唤醒后请手动点击播放。")
            }
        })
        workspaceObservers.append(workspaceNotifications.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, state.isActive else { return }
                pauseForSystemChange("Mac 已唤醒。为避免意外发声，请手动点击播放。")
            }
        })

        audioOutputMonitor = AudioOutputMonitor { [weak self] in
            Task { @MainActor [weak self] in
                self?.pauseForSystemChange("音频输出设备已变化。请确认输出设备后手动继续播放。")
            }
        }

        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { break }
                self?.tick()
            }
        }

        configureRemoteCommands()
    }

    func restore(_ station: Station, line: Int) {
        self.station = station
        self.line = station.streams.indices.contains(line) ? line : 0
        state = .ready
        errorMessage = nil
        updateNowPlaying()
    }

    /// Releases all station-specific audio and timer state while keeping the engine reusable.
    func clearStation() {
        stopCurrentItem()
        triedLines.removeAll()
        sleepDeadline = nil
        station = nil
        line = 0
        state = .ready
        errorMessage = nil
        updateNowPlaying()
    }

    func updateStationMetadata(_ station: Station) {
        guard self.station?.id == station.id else { return }
        self.station = station
        updateNowPlaying()
    }

    func select(_ station: Station, line: Int) {
        stopCurrentItem()
        restore(station, line: line)
        play()
    }

    func toggle() {
        state.isActive ? pause() : play()
    }

    func play() {
        guard station != nil else { return }
        guard isOnline else {
            fail("网络不可用，请连接网络后重试。")
            return
        }
        triedLines.removeAll()
        connect(line)
    }

    func pause() {
        stopCurrentItem()
        state = station == nil ? .ready : .paused
        errorMessage = nil
        updateNowPlaying()
    }

    func switchLine(_ index: Int) {
        guard let station, station.streams.indices.contains(index) else { return }
        line = index
        play()
    }

    func setSleep(minutes: Int) {
        sleepDeadline = Date().addingTimeInterval(Double(minutes * 60))
        now = Date()
    }

    func cancelSleep() {
        sleepDeadline = nil
    }

    var sleepRemaining: String? {
        guard let sleepDeadline else { return nil }
        let seconds = max(0, Int(ceil(sleepDeadline.timeIntervalSince(now))))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func connect(_ index: Int) {
        guard let station, station.streams.indices.contains(index) else {
            fail("电台暂无可用线路。")
            return
        }

        stopCurrentItem()
        line = index
        triedLines.insert(index)
        defaults.set(index, forKey: lineKey(station.id))
        errorMessage = nil
        state = .connecting
        lastPosition = 0
        lastProgressAt = Date()

        player.replaceCurrentItem(with: AVPlayerItem(url: station.streams[index].url))
        player.play()
        updateNowPlaying()
    }

    private func retryNextLine() {
        guard isOnline, let station,
              let next = PlaybackPolicy.nextLine(count: station.streams.count, tried: triedLines) else {
            fail("连接未成功，可能受网络或地区限制。请重试或手动切换线路。")
            return
        }
        connect(next)
    }

    private func fail(_ message: String) {
        stopCurrentItem()
        state = .failed
        errorMessage = message
        updateNowPlaying()
    }

    private func pauseForSystemChange(_ message: String) {
        guard state.isActive else { return }
        stopCurrentItem()
        state = .paused
        errorMessage = message
        updateNowPlaying()
    }

    private func stopCurrentItem() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    func persistVolume() {
        volumeSaveTask?.cancel()
        volumeSaveTask = nil
        defaults.set(volume, forKey: volumeKey)
    }

    private func tick() {
        let currentTime = Date()
        if sleepDeadline != nil, Int(currentTime.timeIntervalSince1970) != Int(now.timeIntervalSince1970) {
            now = currentTime
        }
        if let sleepDeadline, sleepDeadline <= currentTime {
            self.sleepDeadline = nil
            pause()
            return
        }
        guard state.isActive, let item = player.currentItem else { return }
        if item.status == .failed {
            retryNextLine()
            return
        }

        if state == .connecting,
           item.status == .readyToPlay,
           player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            state = .buffering
            updateNowPlaying()
        }

        let position = player.currentTime().seconds
        if position.isFinite && position > lastPosition + 0.01 {
            lastPosition = position
            lastProgressAt = Date()
            if state != .playing {
                state = .playing
                updateNowPlaying()
            }
        } else if Date().timeIntervalSince(lastProgressAt) > 2, state == .playing {
            state = .buffering
            updateNowPlaying()
        }

        if Date().timeIntervalSince(lastProgressAt) >= 20 {
            retryNextLine()
        }
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        bind(commands.playCommand) { $0.play() }
        bind(commands.pauseCommand) { $0.pause() }
        bind(commands.togglePlayPauseCommand) { $0.toggle() }
    }

    private func bind(_ command: MPRemoteCommand, action: @escaping @MainActor (PlaybackEngine) -> Void) {
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                action(self)
            }
            return .success
        }
        remoteCommandTargets.append((command, target))
    }

    private func updateNowPlaying() {
        guard let station else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: station.name,
            MPMediaItemPropertyArtist: station.subtitle,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0
        ]
    }

    func savedLine(for stationID: Station.ID) -> Int {
        defaults.integer(forKey: lineKey(stationID))
    }

    private func lineKey(_ stationID: Station.ID) -> String {
        "wavelet.mac.line.\(stationID).v1"
    }
}
