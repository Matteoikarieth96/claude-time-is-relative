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
    var onHeaderDoubleClick: (() -> Void)?
    var onHeaderClick: (() -> Void)?
    private var downPoint: NSPoint?
    private var dragging = false
    /// A single click waits for the double-click interval: a second click opens the dashboard instead.
    private var pendingClick: DispatchWorkItem?
    /// Button frames from SwiftUI, origin at the top left of the panel.
    var clickRects: [CGRect] = []
    /// The list's header, same origin: a double click there opens the dashboard.
    var headerRect: CGRect = .zero
    /// The view the trackpad and wheel scroll: the list under this drag layer.
    weak var scrollTarget: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let fromTop = NSPoint(x: p.x, y: bounds.height - p.y)
        if clickRects.contains(where: { $0.insetBy(dx: -3, dy: -3).contains(fromTop) }) { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func inHeader(_ event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        return headerRect.insetBy(dx: -4, dy: -4).contains(NSPoint(x: p.x, y: bounds.height - p.y))
    }

    /// A drag moves the panel; a click on the header switches it short or long; a double click there
    /// opens the dashboard.
    override func mouseDown(with event: NSEvent) {
        dragging = false
        downPoint = event.locationInWindow
        if event.clickCount == 2, inHeader(event) {
            pendingClick?.cancel()
            pendingClick = nil
            downPoint = nil
            onHeaderDoubleClick?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let start = downPoint else { return }
        if hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3 {
            dragging = true
            window?.performDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil }
        guard !dragging, downPoint != nil, event.clickCount == 1, inHeader(event) else { return }
        let work = DispatchWorkItem { [weak self] in self?.onHeaderClick?() }
        pendingClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    /// The layer catches the pointer for dragging; the scrolling goes to the list underneath.
    override func scrollWheel(with event: NSEvent) {
        guard let target = scrollTarget, let container = target.superview,
              let hit = target.hitTest(container.convert(event.locationInWindow, from: nil)) else {
            super.scrollWheel(with: event)
            return
        }
        hit.scrollWheel(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: L("Hide the panel", "Nascondi il pannello"), action: #selector(hide), keyEquivalent: "")
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
    private let store: TaskStore
    private let onClickFrames: ([CGRect]) -> Void
    private let onHeaderFrame: (CGRect) -> Void
    private var subscription: AnyCancellable?
    private var layoutKey = ""
    /// While hidden or covered by windows the panel shows a still copy of the list: same rows and
    /// same size, nothing to lay out every second.
    private var paused = false

    init(store: TaskStore, onHide: @escaping () -> Void) {
        let grip = DragView(frame: .zero)
        self.grip = grip
        self.store = store
        onClickFrames = { [weak grip] frames in grip?.clickRects = frames }
        onHeaderFrame = { [weak grip] rect in grip?.headerRect = rect }
        host = FirstClickHostingView(rootView: PanelView(store: store))
        super.init()
        host.rootView = makeView(store)
        grip.scrollTarget = host
        grip.onHeaderDoubleClick = { DashboardController.shared.show() }
        grip.onHeaderClick = { [weak store] in
            withAnimation(.snappy(duration: 0.25)) { store?.compact.toggle() }
        }
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 80))
        host.sizingOptions = [.intrinsicContentSize] // fit() reads the content size from it
        host.frame = content.bounds
        host.autoresizingMask = [.width, .height]
        content.addSubview(host)

        grip.frame = content.bounds
        grip.autoresizingMask = [.width, .height]
        grip.onHide = onHide
        content.addSubview(grip)

        let glassed: Bool
        // NSGlassEffectView exists only in the macOS 26 SDK (Xcode 26, Swift 6.2): older SDKs,
        // like CI's macos-14 runner, build the blur below instead.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // Liquid Glass, the regular kind of the system's own widgets: bright and crisp, a hint
            // of the wallpaper behind. The clear kind looked dull and grey on a busy wallpaper.
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.3)
            glass.cornerRadius = 22
            content.autoresizingMask = [.width, .height]
            glass.contentView = content
            panel.contentView = glass
            glassed = true
        } else {
            glassed = false
        }
        #else
        glassed = false
        #endif
        if !glassed {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active // the panel is never key: keep the blur on anyway
            effect.maskImage = PanelController.roundedMask(radius: 14)
            content.frame = effect.bounds
            content.autoresizingMask = [.width, .height]
            effect.addSubview(content)
            panel.contentView = effect
        }
        panel.delegate = self
        place()
        // Resize to the content when the list can change size, not at every tick of the clock:
        // measuring the content is the costly part.
        subscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.fitIfNeeded() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        // The words of the other language take another height.
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: Loc.changed, object: nil)
        fit()
        // A panel that starts hidden shows the still copy from the start, not the live list.
        updatePause()
    }

    func show() {
        panel.orderFront(nil)
        updatePause()
    }

    /// The panel is on a screen and at least partly visible, not covered by windows.
    var isOnScreen: Bool { panel.isVisible && panel.occlusionState.contains(.visible) }

    func hide() {
        panel.orderOut(nil)
        updatePause()
    }

    @objc private func occlusionChanged() { updatePause() }
    @objc private func languageChanged() { DispatchQueue.main.async { [weak self] in self?.fit() } }

    private func updatePause() {
        let pause = !isOnScreen
        guard pause != paused else { return }
        paused = pause
        host.rootView = makeView(pause ? store.frozenCopy() : store)
        if !pause { fit() }
    }

    private func makeView(_ store: TaskStore) -> PanelView {
        PanelView(store: store, onClickFrames: onClickFrames, onHeaderFrame: onHeaderFrame,
                  onResize: { [weak self] in DispatchQueue.main.async { self?.fit() } })
    }

    /// What decides the panel's height: the rows, the sessions opened, the page, hidden prompts.
    private func fitIfNeeded() {
        let key = store.groups.map { "\($0.id):\($0.items.count):\($0.main.state == .waiting)" }.joined(separator: ",")
            + "|\(store.expanded.sorted())|\(store.pageLimit)|\(store.hidePrompts)|\(store.hiddenAutomated > 0)"
            + "|\(store.compact)|\(store.compact ? "\(store.waitingCount)\(store.runningCount)\(store.visible.count)" : "")"
        guard key != layoutKey else { return }
        layoutKey = key
        fit()
    }

    func pngForDebug() -> Data? {
        guard let view = host.superview ?? panel.contentView, // the glass itself is not captured
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
        guard !paused else { return }
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
