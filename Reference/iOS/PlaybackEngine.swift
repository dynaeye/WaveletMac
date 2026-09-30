import Foundation
import Observation
import AVFoundation
import MediaPlayer
import Network
import UIKit

enum PlaybackState: String {
    case ready = "准备就绪", connecting = "正在连接", buffering = "正在缓冲"
    case playing = "正在收听", paused = "已暂停", failed = "连接失败"
    var active: Bool { self == .connecting || self == .buffering || self == .playing }
}

@MainActor @Observable
final class PlaybackEngine {
    private(set) var station: Station?
    private(set) var state: PlaybackState = .ready
    private(set) var line = 0
    private(set) var errorMessage: String?
    private var sleep = SleepSchedule()
    var sleepDeadline: Date? { sleep.deadline }
    private(set) var now = Date()
    var onStep: ((Int) -> Void)?
    var volume: Float {
        didSet { audio.volume = volume; UserDefaults.standard.set(volume, forKey: "wavelet.volume") }
    }
    @ObservationIgnored private let audio = AVPlayer()
    @ObservationIgnored private let network = NWPathMonitor()
    @ObservationIgnored private var online = true
    @ObservationIgnored private var tried = Set<Int>()
    @ObservationIgnored private var lastProgress = Date()
    @ObservationIgnored private var position = 0.0
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var interruptionResume = InterruptionResumePolicy()

    init() {
        volume = min(1, max(0, UserDefaults.standard.object(forKey: "wavelet.volume") as? Float ?? 0.65))
        audio.volume = volume
        audio.automaticallyWaitsToMinimizeStalling = true
        audio.preventsDisplaySleepDuringVideoPlayback = false
        restoreAutomaticScreenLock()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { break }
                self?.tick()
            }
        }
        network.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                self.online = available
                if !available && self.state.active { self.fail("网络已断开。恢复网络后，请点击播放重连。") }
            }
        }
        network.start(queue: DispatchQueue(label: "WaveletRadio.Network"))
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in self?.handleInterruption(type: rawType) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let unplugged = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            if unplugged { Task { @MainActor in self?.pause() } }
        })
        let center = MPRemoteCommandCenter.shared()
        bind(center.playCommand) { $0.play() }
        bind(center.pauseCommand) { $0.pause() }
        bind(center.togglePlayPauseCommand) { $0.toggle() }
        bind(center.nextTrackCommand) { $0.onStep?(1) }
        bind(center.previousTrackCommand) { $0.onStep?(-1) }
    }
    private func bind(_ command: MPRemoteCommand, action: @escaping @MainActor (PlaybackEngine) -> Void) {
        let token = command.addTarget { [weak self] _ in
            Task { @MainActor in if let self { action(self) } }
            return .success
        }
        remoteTargets.append((command, token))
    }
    func restore(_ station: Station, line: Int) {
        self.station = station
        self.line = station.streams.indices.contains(line) ? line : 0
        state = .ready
    }
    func updateStationMetadata(_ station: Station) {
        guard self.station?.id == station.id else { return }
        self.station = station
        updateNowPlaying()
    }
    func select(_ station: Station, line: Int) {
        audio.pause()
        audio.replaceCurrentItem(with: nil)
        restore(station, line: line)
        play()
    }
    func toggle() { state.active ? pause() : play() }
    func play() {
        interruptionResume.cancel()
        startPlayback()
    }
    private func startPlayback() {
        guard station != nil else { return }
        guard online else { fail("网络不可用，请连接网络后重试。"); return }
        if let deadline = sleepDeadline, deadline <= Date() { cancelSleep(); pause(); return }
        tried = []
        connect(line)
    }
    func pause() {
        interruptionResume.cancel()
        audio.pause()
        audio.replaceCurrentItem(with: nil)
        state = station == nil ? .ready : .paused
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        restoreAutomaticScreenLock()
    }
    func switchLine(_ index: Int) {
        guard let station, station.streams.indices.contains(index) else { return }
        line = index
        play()
    }
    private func connect(_ index: Int) {
        guard let station, station.streams.indices.contains(index) else { fail("电台暂无可用线路。"); return }
        audio.pause()
        audio.replaceCurrentItem(with: nil)
        line = index
        tried.insert(index)
        UserDefaults.standard.set(index, forKey: "wavelet.line.\(station.id)")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch { fail("无法启用系统音频：\(error.localizedDescription)"); return }
        errorMessage = nil
        state = .connecting
        position = 0
        lastProgress = Date()
        audio.replaceCurrentItem(with: AVPlayerItem(url: station.streams[index].url))
        audio.play()
        updateNowPlaying()
    }
    private func retry() {
        guard online, let station,
              let next = PlaybackPolicy.nextLine(count: station.streams.count, tried: tried) else {
            fail("连接未成功，可能受网络或地区限制。请重试或手动切换线路。")
            return
        }
        connect(next)
    }
    private func fail(_ message: String) {
        interruptionResume.cancel()
        audio.pause()
        audio.replaceCurrentItem(with: nil)
        state = .failed
        errorMessage = message
        updateNowPlaying()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        restoreAutomaticScreenLock()
    }
    private func restoreAutomaticScreenLock() {
        UIApplication.shared.isIdleTimerDisabled = false
    }
    private func handleInterruption(type rawType: UInt?) {
        guard let rawType,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            interruptionResume.interruptionBegan(whilePlaying: state.active)
            audio.pause()
            state = station == nil ? .ready : .paused
            updateNowPlaying()
        case .ended:
            if interruptionResume.interruptionEnded() {
                startPlayback()
            }
        @unknown default:
            break
        }
    }
    func setSleep(minutes: Int) { sleep.start(minutes: minutes); now = Date() }
    func cancelSleep() { sleep.cancel() }
    var sleepRemaining: String? {
        guard let seconds = sleep.remaining(at: now) else { return nil }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    func checkDeadline() {
        now = Date()
        if sleep.expired(at: now) {
            sleep.cancel()
            pause()
            audio.replaceCurrentItem(with: nil)
        }
    }
    private func tick() {
        checkDeadline()
        guard state.active, let item = audio.currentItem else { return }
        if item.status == .failed { retry(); return }
        if state == .connecting && item.status == .readyToPlay && audio.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            state = .buffering
            updateNowPlaying()
        }
        let current = audio.currentTime().seconds
        if current.isFinite && current > position + 0.01 {
            position = current
            lastProgress = Date()
            if state != .playing { state = .playing; updateNowPlaying() }
        } else if Date().timeIntervalSince(lastProgress) > 2 && state == .playing {
            state = .buffering
            updateNowPlaying()
        }
        if Date().timeIntervalSince(lastProgress) >= 20 { retry() }
    }
    private func updateNowPlaying() {
        guard let station else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: station.name,
            MPMediaItemPropertyArtist: station.subtitle,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0
        ]
    }
}
