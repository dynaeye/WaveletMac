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

2026-10-02：用户确认的最终 App 位于 `/Users/dynasty/workspace/radio/Mac/Final/Wavelet.app`，已完成 Developer ID 签名与 Apple 公证，兼容 arm64、x86_64 和 macOS 15+。最终 DMG 位于 `Final/Wavelet-1.0.dmg`，已单独通过 Apple 公证并 stapled；Gatekeeper 接受 DMG 和其中 app。归档保留在 `Final/Wavelet-1.0.xcarchive`。最终 App、DMG 与归档不纳入 Git；源码和后续维护工程保留。

已创建 `WaveletMac.xcodeproj`。Debug 与 Release 使用相同的 1,519 个电台数据，仍如实标记为 `web-candidate`，不代表全部完成 Mac 原生播放验证；验证记录另存 `docs/native-validation.json`。香港筛选统一为分组“全部 / 香港”、城市仅“全部”，所有语言一致。默认不自动播放，用户可在设置中开启。

仅将当前确认的候选目录同步到 Release（不重新迁移来源）：`node scripts/migrate-catalog.mjs --sync-release`。

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
