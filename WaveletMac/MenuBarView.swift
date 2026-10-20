import AppKit
import Combine
import SwiftUI

/// One native status item with independently clickable menu and playback regions.
@MainActor
final class RadioStatusBarController: NSObject, ObservableObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var store: RadioCatalogStore?
    private var showMainWindow: (() -> Void)?
    private var subscriptions = Set<AnyCancellable>()
    private let stationButton = NSButton()
    private let playbackButton = NSButton()
    private let menu = NSMenu()

    func install(store: RadioCatalogStore, showMainWindow: @escaping () -> Void) {
        self.showMainWindow = showMainWindow
        guard statusItem == nil else { return }
        self.store = store
        menu.delegate = self
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let container = item.button else { return }
        container.title = ""
        container.target = self
        container.action = #selector(openMenu)
        for button in [stationButton, playbackButton] {
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.focusRingType = .none
            button.target = self
            container.addSubview(button)
        }
        stationButton.imagePosition = .imageLeading
        stationButton.alignment = .left
        stationButton.action = #selector(openMenu)
        playbackButton.imagePosition = .imageOnly
        playbackButton.action = #selector(togglePlayback)
        if let logo = NSImage(named: "WaveletMark")?.copy() as? NSImage {
            logo.size = NSSize(width: 16, height: 16)
            logo.isTemplate = true
            stationButton.image = logo
        }
        store.player.objectWillChange
            .sink { [weak self] _ in
                // @Published announces before assigning its new value.
                DispatchQueue.main.async { self?.update() }
            }
            .store(in: &subscriptions)
        store.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.update() }
            }
            .store(in: &subscriptions)
        update()
    }

    private func update() {
        guard let store, let item = statusItem, let container = item.button else { return }
        let player = store.player
        let name = player.displayTitle ?? "Wavelet"
        let title = name.count > 8 ? String(name.prefix(8)) + "…" : name
        let font = NSFont.menuBarFont(ofSize: 11)
        stationButton.attributedTitle = NSAttributedString(string: " " + title, attributes: [
            .font: font, .foregroundColor: NSColor.labelColor
        ])
        stationButton.toolTip = name
        stationButton.setAccessibilityLabel("Wavelet · " + name + " · " + store.text("打开菜单"))
        let textWidth = ceil(((" " + title) as NSString).size(withAttributes: [.font: font]).width)
        let leadingWidth = textWidth + 16 + 10
        let height = NSStatusBar.system.thickness
        item.length = leadingWidth + 4 + 24
        stationButton.frame = NSRect(x: 0, y: 0, width: leadingWidth, height: height)
        playbackButton.frame = NSRect(x: leadingWidth + 4, y: 0, width: 24, height: height)
        playbackButton.image = NSImage(systemSymbolName: player.state.isActive ? "pause.fill" : "play.fill", accessibilityDescription: nil)
        playbackButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        playbackButton.isEnabled = player.hasPlayableItem
        let actionTitle = store.text(player.state.isActive ? "暂停" : "开始收听")
        playbackButton.toolTip = actionTitle
        playbackButton.setAccessibilityLabel(actionTitle)
        container.setAccessibilityLabel("Wavelet · " + name)
    }

    @objc private func togglePlayback() { store?.player.toggle() }

    @objc private func openMenu() {
        guard let store, let item = statusItem, let button = item.button else { return }
        menu.removeAllItems()
        addItem(store.player.displayTitle ?? "Wavelet", action: nil)
        addItem(store.statusText(), action: nil)
        menu.addItem(.separator())
        addItem(store.text(store.player.state.isActive ? "暂停" : "开始收听"), action: #selector(togglePlayback))
        addItem(store.text(store.player.localTrack != nil ? "上一首" : "上一台"), action: #selector(previousStation))
        addItem(store.text(store.player.localTrack != nil ? "下一首" : "下一台"), action: #selector(nextStation))
        if store.player.localTrack != nil {
            addItem(store.text("本地播放"), action: nil)
        } else if let station = store.player.station {
            let lineMenu = NSMenu()
            for (index, stream) in station.streams.enumerated() {
                let line = NSMenuItem(title: store.lineTitle(index, format: stream.format), action: #selector(switchLine(_:)), keyEquivalent: "")
                line.target = self
                line.tag = index
                line.state = store.player.line == index ? .on : .off
                lineMenu.addItem(line)
            }
            let lines = addItem(store.text("播放线路"), action: nil)
            lines.submenu = lineMenu
        }
        menu.addItem(.separator())
        addItem(store.text("显示主窗口"), action: #selector(showWindow))
        addItem(store.text("退出 Wavelet"), action: #selector(quit))

        // Let the status bar place and draw its standard menu, rather than
        // presenting a context menu manually inside the status-item window.
        item.menu = menu
        button.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Detach after tracking so the independent playback region remains clickable.
        statusItem?.menu = nil
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func previousStation() { store?.step(-1) }
    @objc private func nextStation() { store?.step(1) }
    @objc private func switchLine(_ sender: NSMenuItem) { store?.player.switchLine(sender.tag) }
    @objc func showWindow() {
        if let window = TransparentWindowConfigurator.configuredWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            showMainWindow?()
        }
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

struct MenuBarView: View {
    @ObservedObject var store: RadioCatalogStore
    @ObservedObject var player: PlaybackEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(player.displayTitle ?? "Wavelet")
        Label(store.statusText(), systemImage: statusIcon)

        Divider()

        Button {
            player.toggle()
        } label: {
            Label(store.text(player.state.isActive ? "暂停" : "开始收听"), systemImage: player.state.isActive ? "pause.fill" : "play.fill")
        }
        .disabled(!player.hasPlayableItem)

        Button { store.step(-1) } label: {
            Label(store.text(player.localTrack != nil ? "上一首" : "上一台"), systemImage: "backward.end.fill")
        }
        Button { store.step(1) } label: {
            Label(store.text(player.localTrack != nil ? "下一首" : "下一台"), systemImage: "forward.end.fill")
        }

        if let station = player.station {
            Menu(store.text("播放线路")) {
                ForEach(Array(station.streams.enumerated()), id: \.offset) { index, stream in
                    Button {
                        player.switchLine(index)
                    } label: {
                        Text(store.lineTitle(index, format: stream.format))
                    }
                }
            }
        }

        Divider()

        Button(store.text("显示主窗口")) {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button(store.text("退出 Wavelet")) {
            NSApplication.shared.terminate(nil)
        }
    }

    private var statusIcon: String {
        switch player.state {
        case .playing: "dot.radiowaves.left.and.right"
        case .connecting, .buffering: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle"
        case .ready, .paused: "pause.circle"
        }
    }
}
