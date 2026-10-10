import AVFoundation
import ShazamKit
import ScreenCaptureKit

struct RecognizedSong: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let appleMusicURL: URL?
}

struct RecognitionQuerySchedule {
    private var nextQuery: TimeInterval
    private var completed = false

    init(minimumDuration: TimeInterval) {
        nextQuery = min(20, max(5, minimumDuration))
    }

    /// Returns whether this is the final query, or nil if more audio is needed.
    mutating func checkpoint(at duration: TimeInterval) -> Bool? {
        guard !completed else { return nil }
        if duration >= 20 {
            completed = true
            return true
        }
        guard duration >= nextQuery else { return nil }
        nextQuery = min(20, nextQuery + 5)
        return false
    }
}

/// Captures only Wavelet's system-output audio for a short, in-memory ShazamKit query.
/// It never enables or reads the microphone and does not write a recording to disk.
@MainActor
final class StreamSongRecognition: NSObject, ObservableObject, SHSessionDelegate {
    @Published private(set) var isRecognizing = false
    @Published private(set) var isCapturing = false
    @Published private(set) var status = "请先播放电台。"
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var artworkURL: URL?
    @Published private(set) var appleMusicURL: URL?
    @Published private(set) var recordedSeconds = 0
    @Published private(set) var history: [RecognizedSong]

    private let defaults: UserDefaults
    private static let historyKey = "wavelet.mac.songRecognitionHistory.v1"

    private var session: SHSession?
    private var stream: SCStream?
    private var sampleReceiver: ScreenAudioSampleReceiver?
    private var captureTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var requestID = UUID()
    private var pendingSignature: SHSignature?
    private var isQuerying = false
    private var captureEnded = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.historyKey),
           let songs = try? JSONDecoder().decode([RecognizedSong].self, from: data) {
            history = Array(songs.prefix(5))
        } else {
            history = []
        }
        super.init()
    }

    func remember(_ song: RecognizedSong) {
        history.removeAll { $0.id == song.id }
        history.insert(song, at: 0)
        history = Array(history.prefix(5))
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Self.historyKey)
        }
    }

    func identify() {
        guard !isRecognizing else { return }
        resetResult()
        isRecognizing = true
        status = "正在准备系统音频捕获…"

        let request = UUID()
        requestID = request
        let activeSession = SHSession()
        let minimumDuration = activeSession.catalog.minimumQuerySignatureDuration
        activeSession.delegate = self
        session = activeSession

        let receiver = ScreenAudioSampleReceiver(
            minimumDuration: minimumDuration
        ) { [weak self] seconds in
            Task { @MainActor [weak self] in
                guard let self, self.requestID == request, self.isRecognizing else { return }
                self.recordedSeconds = min(20, Int(seconds.rounded(.down)))
            }
        } onComplete: { [weak self] signature, isFinal in
            Task { @MainActor [weak self] in
                guard let self, self.requestID == request, self.isRecognizing else { return }
                await self.submit(signature, request: request, isFinal: isFinal)
            }
        } onCompleteWithError: { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.requestID == request, self.isRecognizing else { return }
                self.finish(with: message)
            }
        }
        sampleReceiver = receiver

        captureTask = Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                try Task.checkCancellation()
                guard let self, self.requestID == request else { return }
                guard let app = content.applications.first(where: {
                    $0.bundleIdentifier == Bundle.main.bundleIdentifier
                }), let display = content.displays.first else {
                    throw RecognitionFailure.captureSourceUnavailable
                }

                let filter = SCContentFilter(
                    display: display,
                    including: [app],
                    exceptingWindows: []
                )
                let configuration = SCStreamConfiguration()
                configuration.width = 2
                configuration.height = 2
                configuration.capturesAudio = true
                configuration.captureMicrophone = false
                configuration.sampleRate = 48_000
                configuration.channelCount = 2

                let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
                try stream.addStreamOutput(
                    receiver,
                    type: .audio,
                    sampleHandlerQueue: DispatchQueue(label: "Wavelet.SystemAudioCapture")
                )
                self.stream = stream
                self.status = "等待 macOS 允许捕获 Wavelet 系统输出…"
                try await stream.startCapture()
                guard self.requestID == request else {
                    try? await stream.stopCapture()
                    return
                }
                self.captureTask = nil
                self.isCapturing = true
                self.status = "正在录制系统音频…"
                self.timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(35))
                    guard !Task.isCancelled, let self, self.requestID == request else { return }
                    self.finish(with: "没有捕获到 Wavelet 的播放音频，请检查系统录屏与音频权限。")
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.requestID == request else { return }
                self.finish(with: "系统音频捕获失败：\(error.localizedDescription)")
            }
        }
    }

    func stop() {
        finish(with: "识别已停止。")
    }

    func showNeedsPlayback() {
        status = "请先播放电台。"
    }

    private func submit(_ signature: SHSignature, request: UUID, isFinal: Bool) async {
        guard requestID == request, isRecognizing else { return }
        pendingSignature = signature
        if isFinal {
            captureEnded = true
            isCapturing = false
            let activeStream = stream
            stream = nil
            sampleReceiver = nil
            if let activeStream { try? await activeStream.stopCapture() }
            guard requestID == request, isRecognizing else { return }
            status = "采集完成，正在等待识别结果…"
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.requestID == request else { return }
                self.finish(with: "Shazam 查询超时，请稍后重试。")
            }
        }
        await matchPendingSignature(request: request)
    }

    private func matchPendingSignature(request: UUID) async {
        guard requestID == request, isRecognizing, !isQuerying,
              let signature = pendingSignature, let activeSession = session else { return }
        pendingSignature = nil
        isQuerying = true
        let minimumDuration = activeSession.catalog.minimumQuerySignatureDuration
        let maximumDuration = activeSession.catalog.maximumQuerySignatureDuration
        guard signature.duration >= minimumDuration else {
            isQuerying = false
            if captureEnded { finish(with: "未找到匹配歌曲。") }
            return
        }
        let querySignature: SHSignature
        if signature.duration > maximumDuration {
            do {
                let sliceDuration = min(maximumDuration, 20)
                let slices = try signature.slices(
                    from: max(0, signature.duration - sliceDuration),
                    duration: sliceDuration, stride: nil
                )
                guard let firstSlice = try await slices.first(where: { @Sendable _ in true }) else {
                    guard requestID == request, isRecognizing else { return }
                    finish(with: "ShazamKit 无法生成有效时长的签名片段。")
                    return
                }
                querySignature = firstSlice
            } catch {
                guard requestID == request, isRecognizing else { return }
                finish(with: "ShazamKit 签名切片失败：\(error.localizedDescription)")
                return
            }
        } else {
            querySignature = signature
        }
        guard requestID == request, isRecognizing else { return }
        guard querySignature.duration >= minimumDuration,
              querySignature.duration <= maximumDuration else {
            finish(with: "ShazamKit 签名时长无效：\(String(format: "%.2f", querySignature.duration)) 秒；允许范围 \(String(format: "%.2f", minimumDuration))–\(String(format: "%.2f", maximumDuration)) 秒。")
            return
        }
        status = "正在识别歌曲…"
        activeSession.match(querySignature)
    }

    private func resetResult() {
        title = nil
        artist = nil
        artworkURL = nil
        appleMusicURL = nil
        recordedSeconds = 0
        isCapturing = false
        pendingSignature = nil
        isQuerying = false
        captureEnded = false
    }

    private func finish(with message: String) {
        captureTask?.cancel()
        captureTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        let activeStream = stream
        stream = nil
        if let activeStream {
            Task { try? await activeStream.stopCapture() }
        }
        sampleReceiver = nil
        session?.delegate = nil
        session = nil
        pendingSignature = nil
        isQuerying = false
        isRecognizing = false
        isCapturing = false
        status = message
        requestID = UUID()
    }

    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        let sessionID = ObjectIdentifier(session)
        let item = match.mediaItems.first
        let title = item?.title ?? "未知曲名"
        let artist = item?.artist ?? "未知歌手"
        let artworkURL = item?.artworkURL
        let appleMusicURL = item?.appleMusicURL
        let songID = item?.shazamID ?? appleMusicURL?.absoluteString ?? "\(title)|\(artist)"
        Task { @MainActor [weak self] in
            guard let self, self.isRecognizing,
                  self.session.map(ObjectIdentifier.init) == sessionID else { return }
            self.title = title
            self.artist = artist
            self.artworkURL = artworkURL
            self.appleMusicURL = appleMusicURL
            self.remember(RecognizedSong(
                id: songID, title: title, artist: artist,
                artworkURL: artworkURL, appleMusicURL: appleMusicURL
            ))
            self.finish(with: "识别成功。")
        }
    }

    nonisolated func session(
        _ session: SHSession,
        didNotFindMatchFor signature: SHSignature,
        error: Error?
    ) {
        let sessionID = ObjectIdentifier(session)
        let canContinue = error == nil ||
            ((error as NSError?)?.domain == SHErrorDomain && (error as NSError?)?.code == 201)
        let message: String
        if let error {
            let nsError = error as NSError
            if nsError.domain == SHErrorDomain, nsError.code == 201 {
                let minimum = session.catalog.minimumQuerySignatureDuration
                let maximum = session.catalog.maximumQuerySignatureDuration
                message = "ShazamKit 签名时长被拒（\(String(format: "%.2f", signature.duration)) 秒；允许 \(String(format: "%.2f", minimum))–\(String(format: "%.2f", maximum)) 秒）：\(nsError.localizedDescription)"
            } else {
                message = "ShazamKit 查询失败（\(nsError.domain) / \(nsError.code)）：\(nsError.localizedDescription)"
            }
        } else {
            message = "未找到匹配歌曲。"
        }
        Task { @MainActor [weak self] in
            guard let self, self.isRecognizing,
                  self.session.map(ObjectIdentifier.init) == sessionID else { return }
            if canContinue {
                self.isQuerying = false
                if self.pendingSignature != nil {
                    await self.matchPendingSignature(request: self.requestID)
                } else if self.captureEnded {
                    self.finish(with: message)
                } else {
                    self.status = "暂未匹配，继续采集音频…"
                }
            } else {
                self.finish(with: message)
            }
        }
    }
}

private enum RecognitionFailure: LocalizedError {
    case captureSourceUnavailable

    var errorDescription: String? {
        "找不到 Wavelet 的系统音频捕获来源。"
    }
}

/// Receives only app-filtered system-output samples on ScreenCaptureKit's serial queue.
private final class ScreenAudioSampleReceiver: NSObject, SCStreamOutput, @unchecked Sendable {
    private let shazamFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private let signatureGenerator = SHSignatureGenerator()
    private var querySchedule: RecognitionQuerySchedule
    private let onProgress: @Sendable (TimeInterval) -> Void
    private let onComplete: @Sendable (SHSignature, Bool) -> Void
    private let onCompleteWithError: @Sendable (String) -> Void
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var duration: TimeInterval = 0
    private var completed = false
    private var convertedFrames: AVAudioFramePosition = 0

    init(
        minimumDuration: TimeInterval,
        onProgress: @escaping @Sendable (TimeInterval) -> Void,
        onComplete: @escaping @Sendable (SHSignature, Bool) -> Void,
        onCompleteWithError: @escaping @Sendable (String) -> Void
    ) {
        self.querySchedule = RecognitionQuerySchedule(minimumDuration: minimumDuration)
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onCompleteWithError = onCompleteWithError
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, !completed,
              var description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              let inputFormat = AVAudioFormat(streamDescription: &description) else { return }

        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                guard let input = AVAudioPCMBuffer(
                    pcmFormat: inputFormat,
                    bufferListNoCopy: audioBufferList.unsafePointer
                ) else { return }

                if sourceFormat != inputFormat {
                    sourceFormat = inputFormat
                    converter = AVAudioConverter(from: inputFormat, to: shazamFormat)
                }
                guard let converter else { return }
                let capacity = AVAudioFrameCount(
                    ceil(Double(input.frameLength) * shazamFormat.sampleRate / inputFormat.sampleRate) + 32
                )
                guard let output = AVAudioPCMBuffer(pcmFormat: shazamFormat, frameCapacity: capacity) else { return }
                var suppliedInput = false
                var conversionError: NSError?
                let result = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                    guard !suppliedInput else {
                        inputStatus.pointee = .noDataNow
                        return nil
                    }
                    suppliedInput = true
                    inputStatus.pointee = .haveData
                    return input
                }
                guard result != .error, output.frameLength > 0 else {
                    if let conversionError { throw conversionError }
                    return
                }
                let audioTime = AVAudioTime(sampleTime: convertedFrames, atRate: shazamFormat.sampleRate)
                try signatureGenerator.append(output, at: audioTime)
                convertedFrames += AVAudioFramePosition(output.frameLength)
            }
        } catch {
            completed = true
            let nsError = error as NSError
            onCompleteWithError("音频缓冲转换失败（\(nsError.domain)/\(nsError.code)）：\(nsError.localizedDescription)")
            return
        }

        duration = Double(convertedFrames) / shazamFormat.sampleRate
        onProgress(duration)

        guard let isFinal = querySchedule.checkpoint(at: duration) else { return }
        completed = isFinal
        guard convertedFrames > 0 else { return }
        onComplete(signatureGenerator.signature(), isFinal)
    }
}
