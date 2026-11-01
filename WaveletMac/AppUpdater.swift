import Foundation
import Sparkle

/// Sparkle 的标准更新控制器。自动检查由 `SUEnableAutomaticChecks` 与
/// `SUScheduledCheckInterval` 驱动；手动入口复用同一个 updater 实例。
/// `start()` 必须在应用启动完成后调用，过早初始化会让 Sparkle 在自己的
/// bundle 尚未就绪时读取 feed。
@MainActor
enum AppUpdater {
    private static var controller: SPUStandardUpdaterController?

    static var isConfigured: Bool { controller != nil }

    static func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    static var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? true
    }

    static func checkForUpdates() {
        start()
        controller?.checkForUpdates(nil)
    }
}
