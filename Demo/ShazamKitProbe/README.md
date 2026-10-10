# ShazamKit Probe

独立的 macOS 小实验，用于验证 ShazamKit 曲库匹配、麦克风授权和用户主动识别的基本流程。不会引用或修改 WaveletMac 的源码、工程或脚本。

## 运行

```sh
cd Demo/ShazamKitProbe
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ShazamKitProbe.xcodeproj \
  -scheme ShazamKitProbe \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/ShazamKitProbeDerivedData \
  build
open /private/tmp/ShazamKitProbeDerivedData/Build/Products/Debug/ShazamKitProbe.app
```

打开后，先在扬声器播放一段歌曲或 Wavelet 电台，再点击“识别 12 秒”。首次使用会请求麦克风权限。实验仅把实时麦克风缓冲区交给 ShazamKit，不写入录音文件；停止按钮或 12 秒超时会关闭采集。

## 实验边界

- 此原型验证 ShazamKit 对外部声音的识别流程，不读取 WaveletMac 的私有 AVPlayer 缓冲区。
- 扬声器回采会受音量、环境噪声、设备麦克风和歌曲是否在 Shazam 曲库中的影响。
- 若识别成功，可确认 ShazamKit 服务、开发者配置及本机音频权限可用；要将识别稳定接到 Wavelet 的播放流，仍需独立验证 AVPlayer 音频 tap 的兼容性与播放稳定性。
- 使用 Shazam 曲库需要在 Apple Developer 账号的 App ID 服务中启用 ShazamKit。
