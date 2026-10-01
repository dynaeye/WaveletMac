# iOS 1.0 到 macOS 的复用说明

## 可直接复用

1. `Shared/Models.swift`
   - `Station` / `RadioStream` / `Region` 数据模型。
   - 电台目录和六语翻译解析。
   - 繁简归一、搜索、拼音排序、地区排序、收藏与常听纯逻辑。
2. `Shared/Resources/` 与 `docs/电台目录翻译.json`
   - 1,519 个 Debug 候选电台、Release 验证目录与六语电台翻译。
3. `Assets/` 和 `Fonts/`
   - 可继续使用同一套品牌 Logo、Noto Sans SC、Inter、Space Mono 和 Archivo。
4. `scripts/`
   - 目录迁移、翻译源数据导出、翻译修正、城市译名整理和核心检查可与 iOS 版共用。

## 可复用逻辑，但需要 macOS 适配

1. `Reference/iOS/RadioStore.swift`
   - 搜索、筛选、收藏、常听次数、上次电台和语言切换逻辑可保留。
   - 建议在 macOS 项目中将其改为依赖播放器协议，避免 Store 与移动端 `PlaybackEngine` 紧耦合。
2. `Reference/iOS/PlaybackEngine.swift`
   - AVPlayer 连接、缓冲、进度判定、超时和多线路重试思路可复用。
   - `UIKit`、`UIApplication`、`AVAudioSession` 中断/路由通知属于 iOS，macOS 版需换成 AppKit 生命周期与 macOS 音频设备变化处理。
   - `MPRemoteCommandCenter` 和 Now Playing 需在 macOS 目标上重新验证，不应假设与 iOS 行为完全一致。
3. `Reference/iOS/ContentView.swift`
   - 可复用颜色、字体、文案、收音机面板视觉和语言字典。
   - 不复制 iPhone/iPad 横竖屏分支、底部导航和手势返回；Mac 建议使用 `NavigationSplitView`、菜单命令、键盘快捷键、右键菜单和可调窗口。

## 不建议直接复用

- iOS 首页的随机金句功能、`QuoteCatalog` 和 `motivational-quotes.json`。
- iOS `Info.plist` 中的后台音频声明。
- iPhone/iPad 状态栏、安全区、屏幕旋转和防自动锁屏处理。
- iOS AppIcon 占位配置。macOS 需独立的多尺寸 App Icon。

## 建议开发顺序

1. 建立 macOS 15+ SwiftUI App，产品名 `WaveletMac`，确定最终 Bundle ID。
2. 将 `Shared/Models.swift`、`Shared/Resources`、`docs/电台目录翻译.json`、`Assets` 和 `Fonts` 加入 target，先完成目录解码与搜索测试。
3. 建立 macOS 专用播放引擎，保留真实状态、20 秒无进度超时和最多 3 条线路重试。
4. 将 `RadioStore` 迁移到共享层，验证 UserDefaults 持久化键和 iOS 版是否需要互通或独立。
5. 以 Mac 桌面交互重建界面，再补菜单栏、快捷键、窗口恢复、媒体键和深色模式。
6. 分别验证 Intel/Apple Silicon 需求、睡眠唤醒、音频输出设备切换、菜单栏播放和锁屏/Now Playing 行为。

## 数据基线

- Debug 候选目录：1,519 个电台。
- 电台翻译：英文、日文、韩文、泰文、西班牙语、阿拉伯语各 1,519 条。
- Release 目录仍受 `native-validation.json` 验证记录约束，迁入后不能将 Debug 候选目录误当成已验证正式目录。
