import AppKit
import Combine
import SwiftUI

/// Borderless panel at desktop level: above the wallpaper and the desktop icons, under every
/// window, on every Space. It never takes focus.
final class DesktopPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 80),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The panel never becomes key: its buttons must take the first click.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Transparent layer over the panel content: drag to move, right click for the menu.
/// Clicks on the buttons ("5 more", "Show less") go through to them.
final class DragView: NSView {
    var onHide: (() -> Void)?
    /// Button frames from SwiftUI, origin at the top left of the panel.
    var clickRects: [CGRect] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let fromTop = NSPoint(x: p.x, y: bounds.height - p.y)
        if clickRects.contains(where: { $0.insetBy(dx: -3, dy: -3).contains(fromTop) }) { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Hide panel", action: #selector(hide), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func hide() { onHide?() }
}

final class PanelController: NSObject, NSWindowDelegate {
    let panel = DesktopPanel()
    private let defaults = UserDefaults.standard
    private let margin: CGFloat = 24

    private let host: FirstClickHostingView<PanelView>
    private let grip: DragView
    private var subscription: AnyCancellable?

    init(store: TaskStore, onHide: @escaping () -> Void) {
        let grip = DragView(frame: .zero)
        self.grip = grip
        host = FirstClickHostingView(rootView: PanelView(store: store, onClickFrames: { [weak grip] frames in
            grip?.clickRects = frames
        }))
        super.init()
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active // the panel is never key: keep the blur on anyway
        effect.maskImage = PanelController.roundedMask(radius: 14)

        host.sizingOptions = [.intrinsicContentSize] // fit() reads the content size from it
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)

        grip.frame = effect.bounds
        grip.autoresizingMask = [.width, .height]
        grip.onHide = onHide
        effect.addSubview(grip)

        panel.contentView = effect
        panel.delegate = self
        place()
        // Every change of the list (or tick of the clock): resize to the content, after SwiftUI
        // has taken the change.
        subscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.fit() }
        }
        fit()
    }

    func show() { panel.orderFront(nil) }
    func hide() { panel.orderOut(nil) }

    func pngForDebug() -> Data? {
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Clicks the first button of the panel with synthetic events, as a user would (tests only).
    func clickFirstButtonForDebug() -> Bool {
        guard let rect = grip.clickRects.first, let content = panel.contentView else { return false }
        let point = NSPoint(x: rect.midX, y: content.bounds.height - rect.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: panel.windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 1, pressure: 1) else { return false }
            panel.sendEvent(event)
        }
        return true
    }

    /// Follow the content size, keeping the top left corner where the user put it.
    private func fit() {
        let size = host.intrinsicContentSize
        let s = NSSize(width: ceil(size.width), height: ceil(size.height))
        guard s.width > 0, s.height > 0, s != panel.frame.size else { return }
        let f = panel.frame
        panel.setFrame(NSRect(x: f.minX, y: f.maxY - s.height, width: s.width, height: s.height),
                       display: true)
        panel.invalidateShadow()
    }

    /// The saved position if it is still on a screen, else the top right corner of the main screen.
    private func place() {
        let size = panel.frame.size
        if defaults.object(forKey: "panelLeft") != nil {
            let left = defaults.double(forKey: "panelLeft")
            let top = defaults.double(forKey: "panelTop")
            let probe = NSPoint(x: left + 20, y: top - 20)
            if NSScreen.screens.contains(where: { $0.frame.contains(probe) }) {
                panel.setFrameTopLeftPoint(NSPoint(x: left, y: top))
                return
            }
        }
        let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameTopLeftPoint(NSPoint(x: vf.maxX - size.width - margin, y: vf.maxY - margin))
    }

    func windowDidMove(_ notification: Notification) {
        defaults.set(panel.frame.minX, forKey: "panelLeft")
        defaults.set(panel.frame.maxY, forKey: "panelTop")
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
