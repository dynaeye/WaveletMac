import AVFoundation
import ShazamKit
import SwiftUI

struct RecognizedSong {
    let title: String
    let artist: String
}

@MainActor
final class RecognitionModel: NSObject, ObservableObject, SHSessionDelegate {
    @Published private(set) var status = "点击按钮后会请求麦克风权限，并识别 20 秒。"
    @Published private(set) var isRecognizing = false
    @Published private(set) var match: RecognizedSong?
    @Published private(set) var inputDetails = ""
    @Published private(set) var receivedBufferCount = 0
    @Published private(set) var inputLevel = 0.0

    private var audioEngine: AVAudioEngine?
    private var tapNode: AVAudioNode?
    private var timeoutTask: Task<Void, Never>?
    private var session: SHSession?

    func start() {
        guard !isRecognizing else { return }
        match = nil
        receivedBufferCount = 0
        inputLevel = 0
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginCapture()
        case .notDetermined:
            status = "正在请求麦克风权限…"
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
                Task { @MainActor in
                    guard let self else { return }
                    guard allowed else {
                        self.status = "没有麦克风权限。可在系统设置 → 隐私与安全性 → 麦克风中授权。"
                        return
                    }
                    self.beginCapture()
                }
            }
        case .denied, .restricted:
            status = "麦克风访问已关闭。请在系统设置 → 隐私与安全性 → 麦克风中允许 ShazamKit Probe。"
        @unknown default:
            status = "无法确定麦克风权限状态。"
        }
    }

    func stop() {
        finish(with: "识别已停止。")
    }

    private func beginCapture() {
        do {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let inputFormat = input.inputFormat(forBus: 0)
            guard inputFormat.channelCount > 0,
                  let matchFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) else {
                status = "无法创建麦克风音频格式。"
                return
            }
            inputDetails = "输入：\(Int(inputFormat.sampleRate)) Hz / \(inputFormat.channelCount) 声道；匹配：48,000 Hz / 单声道"

            let mixer = AVAudioMixerNode()
            engine.attach(mixer)
            engine.connect(input, to: mixer, format: inputFormat)
            engine.connect(mixer, to: engine.mainMixerNode, format: matchFormat)
            engine.mainMixerNode.outputVolume = 0

            let activeSession = SHSession()
            activeSession.delegate = self
            mixer.installTap(onBus: 0, bufferSize: 8192, format: matchFormat) { [weak self] buffer, time in
                activeSession.matchStreamingBuffer(buffer, at: time)
                let level = Self.rootMeanSquareLevel(of: buffer)
                Task { @MainActor [weak self] in
                    guard let self, self.isRecognizing else { return }
                    self.receivedBufferCount += 1
                    self.inputLevel = level
                }
            }

            try engine.start()
            audioEngine = engine
            tapNode = mixer
            session = activeSession
            isRecognizing = true
            status = "正在聆听并匹配 Shazam 曲库…"
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self, isRecognizing else { return }
                let levelDescription = inputLevel < 0.001 ? "输入电平很低" : "已收到有效音频"
                finish(with: "20 秒未匹配（已收 \(receivedBufferCount) 段；\(levelDescription)）。让 Shazam Mac 与本 Demo 同时识别同一首歌，可帮助判断是否为麦克风回采问题。")
            }
        } catch {
            status = "音频引擎启动失败：\(error.localizedDescription)"
            audioEngine = nil
            session = nil
        }
    }

    private func finish(with message: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let engine = audioEngine {
            tapNode?.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        tapNode = nil
        session?.delegate = nil
        session = nil
        isRecognizing = false
        if match == nil { status = message }
    }

    private static func rootMeanSquareLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?.pointee else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum = 0.0
        for index in 0..<count {
            let sample = Double(channel[index])
            sum += sample * sample
        }
        return (sum / Double(count)).squareRoot()
    }

    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        let item = match.mediaItems.first
        let result = RecognizedSong(
            title: item?.title ?? "未知曲名",
            artist: item?.artist ?? "未知歌手"
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.match = result
            self.status = "识别成功。"
            self.finish(with: "识别成功。")
        }
    }

    nonisolated func session(
        _ session: SHSession,
        didNotFindMatchFor signature: SHSignature,
        error: Error?
    ) {
        let message = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, isRecognizing else { return }
            if let message {
                status = "识别服务暂不可用：\(message)"
                finish(with: status)
            } else {
                status = "收到 Shazam 曲库的未匹配结果，仍在继续聆听…"
            }
        }
    }
}
