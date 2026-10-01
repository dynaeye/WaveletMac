import AppKit
import SwiftUI

@main
struct WaveletMacApp: App {
    @StateObject private var store = RadioCatalogStore()
    @StateObject private var statusBar = RadioStatusBarController()
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(WaveletApplicationDelegate.self) private var appDelegate

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        // A singleton scene: status-bar "Show radio" reuses this window.
        // WindowGroup creates another instance on every openWindow(id:) call.
        Window("Wavelet", id: "main") {
            ContentView(store: store)
                .frame(width: 520)
                .onAppear {
                    statusBar.install(store: store) {
                        openWindow(id: "main")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
        }
        .defaultSize(width: 520, height: 550)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

final class WaveletApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
