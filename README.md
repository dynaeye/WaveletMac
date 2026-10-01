# WaveletMac

Wavelet 的原生 macOS 版本仓库。工程采用 Swift 6、SwiftUI 与 AVFoundation，最低支持 macOS 15；App 显示名称为 `Wavelet`，Bundle ID 为 `com.mythmedia.waveletmac`。

## 目录

- `Shared/`：可直接放入 macOS target 的模型、数据和通用资源。
- `Assets/`：Wavelet Logo 和品牌图片。
- `Fonts/`：iOS 版使用的字体与授权文件。
- `scripts/`：电台目录迁移、翻译、城市数据和核心逻辑校验工具。
- `docs/`：Mac 开发计划与进度、翻译源数据、正式翻译和原生验证记录。
- `Reference/iOS/`：iOS 1.0 源码与截图参考，不应直接加入 macOS target；旧移动端开发文档已清理。
- `WaveletMac/`：macOS App、目录 Store、原生播放引擎、主窗口与菜单栏界面。
- `WaveletMacTests/`：目录加载、搜索、翻译覆盖和默认不自动播放测试。
- `project.yml`：XcodeGen 工程源文件；修改工程结构后运行 `xcodegen generate`。

## 当前状态

2026-10-01：用户确认当前 Mac 版本为最终版本，固定 App 路径为 `/Users/dynasty/workspace/radio/Mac/Final/Wavelet.app`。该 App 保留已确认的当前构建与 1,519 个候选电台，不切换到空目录的 Release 构建。最终 App 不纳入 Git；源码和后续维护工程保留，旧测试构建移至废纸篓。

已创建 `WaveletMac.xcodeproj`，Debug App 可编译，目录与搜索测试通过。Debug 使用 1,519 个候选电台；Release 继续只读取 Mac 原生验证目录，当前为 0 台。播放器不会在启动时自动发声。

## 本地验证

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WaveletMac.xcodeproj \
  -scheme WaveletMac \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ./DerivedData \
  CODE_SIGNING_ALLOWED=NO test
```
