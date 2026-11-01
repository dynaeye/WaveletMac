import AppKit
import SwiftUI

@MainActor
enum WindowTheme {
    static func apply(_ preference: String, to window: NSWindow) {
        switch preference {
        case "浅色": window.appearance = NSAppearance(named: .aqua)
        case "深色": window.appearance = NSAppearance(named: .darkAqua)
        default: window.appearance = nil
        }
        // Inherit from the window, including when returning to system appearance.
        window.contentView?.appearance = nil
    }
}

/// A separate child panel keeps drawer animation out of the receiver's window layout.
struct DrawerWindowPresenter: NSViewRepresentable {
    var isPresented: Bool
    var height: CGFloat
    var themePreference: String
    var content: AnyView

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            coordinator.update(parent: view.window, isPresented: isPresented, height: height, themePreference: themePreference, content: content)
        }
    }

    @MainActor
    final class Coordinator {
        private var panel: DrawerPanel?
        private var host: NSHostingView<AnyView>?
        private var visible = false

        func update(parent: NSWindow?, isPresented: Bool, height: CGFloat, themePreference: String, content: AnyView) {
            guard let parent else { return }
            if !isPresented {
                guard visible, let panel else { return }
                visible = false
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    panel.animator().alphaValue = 0
                } completionHandler: { [weak self, weak parent] in
                    MainActor.assumeIsolated {
                        guard let self, !self.visible else { return }
                        panel.orderOut(nil)
                        parent?.removeChildWindow(panel)
                        parent?.makeKeyAndOrderFront(nil)
                    }
                }
                return
            }
            let screenFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
            let target = DrawerPanelPlacement.frame(
                parent: parent.frame,
                visibleScreen: screenFrame,
                preferredHeight: height
            )
            let panelHeight = target.height
            if panel == nil {
                let newPanel = DrawerPanel(contentRect: target, styleMask: [.borderless], backing: .buffered, defer: false)
                newPanel.isOpaque = false
                newPanel.backgroundColor = .clear
                newPanel.hasShadow = true
                newPanel.hidesOnDeactivate = false
                newPanel.title = "Wavelet 抽屉"
                newPanel.isReleasedWhenClosed = false
                let hosting = NSHostingView(rootView: AnyView(content.frame(width: target.width, height: panelHeight)))
                newPanel.contentView = hosting
                host = hosting
                panel = newPanel
            }
            guard let panel else { return }
            WindowTheme.apply(themePreference, to: panel)
            host?.rootView = AnyView(content.frame(width: target.width, height: panelHeight))
            if visible {
                panel.setFrame(target, display: true)
                return
            }
            visible = true
            panel.setFrame(target.offsetBy(dx: 0, dy: 18), display: true)
            panel.alphaValue = 0
            // `.above` keeps the drawer visible when a short screen forces it to
            // overlap the receiver edge instead of shrinking below content height.
            parent.addChildWindow(panel, ordered: .above)
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 1
            }
        }
    }
}

enum DrawerPanelPlacement {
    /// 抽屉内容在这个高度以下会被裁切：36pt 内边距 + 标题行 + 搜索框 + 四个筛选器 + 两行电台。
    static let minimumContentHeight: CGFloat = 280

    static func frame(parent: NSRect, visibleScreen: NSRect, preferredHeight: CGFloat) -> NSRect {
        let margin: CGFloat = 8
        let gap: CGFloat = 12
        let width = min(parent.width, max(1, visibleScreen.width - margin * 2))
        let x = min(max(parent.minX, visibleScreen.minX + margin), visibleScreen.maxX - margin - width)
        let screenHeight = max(1, visibleScreen.height - margin * 2)
        let height = min(preferredHeight, screenHeight)

        let belowSpace = max(0, parent.minY - visibleScreen.minY - gap)
        let aboveSpace = max(0, visibleScreen.maxY - parent.maxY - gap)

        // A side that fits the whole panel keeps the drawer and the receiver apart.
        if belowSpace >= height {
            return NSRect(x: x, y: parent.minY - gap - height, width: width, height: height)
        }
        if aboveSpace >= height {
            return NSRect(x: x, y: parent.maxY + gap, width: width, height: height)
        }

        // Neither side fits. Keep the content intact and let the panel overlap the
        // receiver edge instead of shrinking it below its intrinsic height, which
        // used to crop the drawer's top and bottom once the receiver sat mid-screen.
        let minimum = min(minimumContentHeight, height, screenHeight)
        let belowHeight = min(height, max(belowSpace, minimum))
        let aboveHeight = min(height, max(aboveSpace, minimum))

        if belowHeight >= aboveHeight {
            let desired = parent.minY - gap - belowHeight
            let y = max(visibleScreen.minY, min(desired, visibleScreen.maxY - belowHeight))
            return NSRect(x: x, y: y, width: width, height: belowHeight)
        }
        let desired = parent.maxY + gap
        let y = max(visibleScreen.minY, min(desired, visibleScreen.maxY - aboveHeight))
        return NSRect(x: x, y: y, width: width, height: aboveHeight)
    }
}

private final class DrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct TransparentWindowConfigurator: NSViewRepresentable {
    var themePreference: String = "跟随系统"
    @MainActor static weak var configuredWindow: NSWindow?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            Self.configure(view.window)
            if let window = view.window { WindowTheme.apply(themePreference, to: window) }
            coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            Self.configure(nsView.window)
            if let window = nsView.window { WindowTheme.apply(themePreference, to: window) }
            coordinator.attach(to: nsView.window)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var window: NSWindow?
        private var topEdge: CGFloat?
        private var lastSize: NSSize?
        private var isCorrectingResize = false

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            if let previousWindow = self.window {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: previousWindow)
                NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: previousWindow)
            }
            self.window = window
            topEdge = window.frame.maxY
            lastSize = window.frame.size
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize), name: NSWindow.didResizeNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidMove), name: NSWindow.didMoveNotification, object: window)
        }

        @objc private func windowDidResize(_ notification: Notification) {
            guard let window, let topEdge, !isCorrectingResize else { return }
            lastSize = window.frame.size
            let targetY = topEdge - window.frame.height
            guard abs(window.frame.origin.y - targetY) > 0.5 else { return }
            isCorrectingResize = true
            window.setFrameOrigin(NSPoint(x: window.frame.origin.x, y: targetY))
            isCorrectingResize = false
        }

        @objc private func windowDidMove(_ notification: Notification) {
            guard let window, !isCorrectingResize else { return }
            if let lastSize,
               abs(window.frame.width - lastSize.width) > 0.5 ||
               abs(window.frame.height - lastSize.height) > 0.5 {
                return
            }
            topEdge = window.frame.maxY
        }
    }

    @MainActor
    private static func configure(_ window: NSWindow?) {
        guard let window else { return }
        configuredWindow = window

        window.styleMask = [.borderless, .fullSizeContentView, .miniaturizable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.invalidateShadow()
        window.isMovableByWindowBackground = false

        makeViewTransparent(window.contentView)

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    @MainActor
    private static func makeViewTransparent(_ view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

struct WindowDragArea: View {
    @State private var startOrigin: NSPoint?
    @State private var startMouseLocation: NSPoint?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        guard let window = TransparentWindowConfigurator.configuredWindow ?? NSApp.keyWindow else { return }
                        let mouseLocation = NSEvent.mouseLocation
                        if startOrigin == nil {
                            startOrigin = window.frame.origin
                            startMouseLocation = NSPoint(
                                x: mouseLocation.x - value.translation.width,
                                y: mouseLocation.y + value.translation.height
                            )
                        }
                        guard let startOrigin, let startMouseLocation else { return }
                        window.setFrameOrigin(
                            NSPoint(
                                x: startOrigin.x + mouseLocation.x - startMouseLocation.x,
                                y: startOrigin.y + mouseLocation.y - startMouseLocation.y
                            )
                        )
                    }
                    .onEnded { _ in
                        startOrigin = nil
                        startMouseLocation = nil
                    }
            )
    }
}
