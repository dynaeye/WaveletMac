import SwiftUI

@main
struct ShazamKitProbeApp: App {
    var body: some Scene {
        WindowGroup {
            ProbeView()
                .frame(minWidth: 420, minHeight: 300)
        }
        .windowResizability(.contentSize)
    }
}

private struct ProbeView: View {
    @StateObject private var model = RecognitionModel()

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: model.match == nil ? "waveform" : "music.note")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)

            Text("ShazamKit 识别实验")
                .font(.title2.weight(.semibold))

            Text(model.status)
                .font(.body)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 42)

            if !model.inputDetails.isEmpty {
                Text("\(model.inputDetails)\n已送入匹配：\(model.receivedBufferCount) 段 · 当前输入电平：\(model.inputLevel, format: .number.precision(.fractionLength(4)))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            if let match = model.match {
                VStack(spacing: 4) {
                    Text(match.title).font(.headline)
                    Text(match.artist).foregroundStyle(.secondary)
                }
            }

            Button(model.isRecognizing ? "停止识别" : "识别 20 秒") {
                model.isRecognizing ? model.stop() : model.start()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)

            Text("通过麦克风识别周围播放的音乐。可先播放 Wavelet 电台，再点击识别。\n实验不会保存录音；这是扬声器回采验证，不代表最终会采用该架构。Shazam Mac 可能直接识别系统音频，和麦克风回采条件不同。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
    }
}
