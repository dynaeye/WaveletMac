import SwiftUI

@main
struct WaveletMacApp: App {
    @StateObject private var store = RadioCatalogStore()

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(store: store)
                .frame(minWidth: 520, idealWidth: 580, maxWidth: 680)
        }
        .defaultSize(width: 580, height: 440)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarView(store: store, player: store.player)
        } label: {
            Image("WaveletMark")
            Text(menuBarTitle)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarTitle: String {
        let name = store.player.station?.name ?? "Wavelet"
        return name.count > 12 ? String(name.prefix(12)) + "…" : name
    }
}
