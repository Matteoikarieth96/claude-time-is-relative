import AppKit
import Combine
import SwiftUI

/// Menu bar item. While a task runs: its time and its estimate ("2m10s / ~4 min", coloured once
/// past the estimate) and how many others run. A hand when a task waits for you. Otherwise a tick
/// and the tasks finished in the last 30 minutes. A click opens the list; resting the pointer on
/// the item opens it too, and it closes again when the pointer goes away.
final class StatusController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: TaskStore
    private let prefs: Prefs
    private var subscription: AnyCancellable?
    private var shownBox: MenuBarBox?
    private var hoverTimer: Timer?
    private var leaveTimer: Timer?
    private var openedByHover = false
    private var awayTicks = 0
    private let host: NSHostingController<MenuView>
    /// The list shows an empty store while closed: nothing to lay out every second.
    private static let idleStore = TaskStore(demoItems: [], now: 0)

    init(store: TaskStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
        host = NSHostingController(rootView: MenuView(store: StatusController.idleStore, prefs: prefs))
        super.init()
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.delegate = self
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle(_:))
            button.imagePosition = .imageLeft
            button.addTrackingArea(NSTrackingArea(rect: .zero,
                                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                  owner: self, userInfo: nil))
        }
        // After a click inside a list opened by hovering, a click on the item closes it, as when
        // opened by a click.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.openedByHover = false }
        // The dashboard or the settings in front: the list gives way.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil,
                                               queue: .main) { [weak self] note in
            guard let self, self.popover.isShown, let window = note.object as? NSWindow,
                  window.styleMask.contains(.titled) else { return }
            self.popover.performClose(nil)
        }
        subscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: Loc.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// The list under the menu bar item is open.
    var isListShown: Bool { popover.isShown }

    var titleForDebug: String { "box='\(shownBox?.segments.map(\.text).joined(separator: " ") ?? "")'" }

    /// Opens the popover, saves a picture of it and closes it again (tests only).
    func dumpPopoverForDebug(to url: URL) {
        guard let button = item.button else { return }
        popover.appearance = NSAppearance(named: .aqua) // the capture has no background: dark text
        toggle(button)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let view = self.popover.contentViewController?.view,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            self.popover.performClose(nil)
            self.popover.appearance = nil
        }
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        hoverTimer?.invalidate()
        // A double click on the item opens the dashboard (the first click already toggled the list).
        if NSApp.currentEvent?.clickCount == 2 {
            if popover.isShown { popover.performClose(sender) }
            DashboardController.shared.show()
            return
        }
        if popover.isShown && openedByHover {
            openedByHover = false // a click on the item keeps the list open
            NSApp.activate(ignoringOtherApps: true)
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            openedByHover = false
            NSApp.activate(ignoringOtherApps: true)
            showList(from: sender)
        }
    }

    private func showList(from button: NSStatusBarButton) {
        host.rootView = MenuView(store: store, prefs: prefs)
        host.view.layoutSubtreeIfNeeded()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        watchPointer()
    }

    /// However it opened, the list closes once the pointer has been away from it and the item for
    /// about a second; hovering the item opens it again.
    private func watchPointer() {
        awayTicks = 0
        leaveTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.checkPointer() }
        RunLoop.main.add(timer, forMode: .common)
        leaveTimer = timer
    }

    func popoverDidClose(_ notification: Notification) {
        host.rootView = MenuView(store: StatusController.idleStore, prefs: prefs)
    }

    // MARK: - opening on hover

    @objc func mouseEntered(_ event: NSEvent) {
        guard prefs.hoverOpen, !popover.isShown else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.openByHover()
        }
    }

    @objc func mouseExited(_ event: NSEvent) {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    /// Without taking the focus from the app in front: the list only shows, and scrolls.
    private func openByHover() {
        guard let button = item.button, !popover.isShown else { return }
        openedByHover = true
        showList(from: button)
    }

    /// The list closes once the pointer has been away from it and the item for about a second; not
    /// while one of its menus is open (the ⋯ of the golf strip, a picker), whose items lie outside
    /// it, nor while a button is held (a golf shot dragged past the edge).
    private func checkPointer() {
        guard popover.isShown else {
            leaveTimer?.invalidate()
            leaveTimer = nil
            return
        }
        if RunLoop.main.currentMode == .eventTracking || NSEvent.pressedMouseButtons != 0 {
            awayTicks = 0
            return
        }
        let p = NSEvent.mouseLocation
        let areas = [item.button?.window?.frame, popover.contentViewController?.view.window?.frame]
            .compactMap { $0?.insetBy(dx: -16, dy: -16) }
        if areas.contains(where: { $0.contains(p) }) {
            awayTicks = 0
            return
        }
        awayTicks += 1
        if awayTicks >= 4 { popover.performClose(nil) }
    }

    // MARK: - the item

    private func refresh() {
        guard let button = item.button else { return }
        let now = store.now
        let visible = store.visible
        let running = visible.filter { $0.state == .running || $0.state == .background }
        let done = store.doneCount
        let waiting = store.waitingCount
        let longest = running.max { $0.elapsed(at: now) < $1.elapsed(at: now) }

        var segments: [MenuBarBox.Segment] = []
        if waiting > 0 { segments.append(.init(symbol: "hand.raised.fill", text: "\(waiting)")) }
        segments.append(.init(symbol: "play.fill", text: "\(running.count)"))
        segments.append(.init(symbol: "checkmark", text: "\(done)"))
        if let longest { segments.append(.init(symbol: "timer", text: clock(longest.elapsed(at: now)))) }

        // The colour says how things go: orange when a task waits for you, else the pace of the
        // longest running task, grey when nothing runs.
        let pace: Pace? = waiting > 0 ? nil : longest.map { $0.pace(at: now) }
        var box = MenuBarBox(segments: segments, pace: pace, waiting: waiting > 0, idle: running.isEmpty && waiting == 0)
        // A task has just finished: for a few seconds the box is its sticker, in its colours. The
        // menu bar is the one place always in sight; the row's animation needs the list open.
        let wallTime = Date().timeIntervalSince1970
        if let party = store.celebrations.values.filter({ wallTime - $0.start < Celebration.duration + 0.5 })
            .max(by: { $0.start < $1.start }) {
            let text = GameMood.current == .miniera
                ? party.ore.map { $0.short + "  " + party.oreDetail } ?? party.outcome.stamp + "  " + party.detail
                : party.outcome.stamp + "  " + party.detail
            box = MenuBarBox(segments: [.init(symbol: "", text: text)],
                             pace: nil, waiting: false, idle: false, outcome: party.outcome)
        }
        if box != shownBox {
            shownBox = box
            button.image = box.image()
            button.imagePosition = .imageOnly
            button.title = ""
        }

        var tips = [running.count == 1 ? L("1 prompt running", "1 prompt in corso") : L("\(running.count) prompts running", "\(running.count) prompt in corso"),
                    done == 1 ? L("1 done in the last hour", "1 finito nell'ultima ora") : L("\(done) done in the last hour", "\(done) finiti nell'ultima ora")]
        if waiting > 0 { tips.insert(waiting == 1 ? L("1 needs you", "1 ti aspetta") : L("\(waiting) need you", "\(waiting) ti aspettano"), at: 0) }
        if let longest {
            let name = longest.shownName(hidePrompts: store.hidePrompts), time = clock(longest.elapsed(at: now))
            var tip = L("The longest: \(name), \(time)", "Il più lungo: \(name), \(time)")
            if let est = longest.estimateText { tip += L(" of \(est)", " su \(est)") }
            if let over = longest.overrunText(at: now) { tip += ", \(over)" }
            tips.append(tip)
        }
        button.toolTip = tips.joined(separator: "\n")
    }
}

/// The menu bar item: a coloured box with prompts running, prompts finished and the time of the
/// longest running one ("▶ 3  ✓ 2  ⏱ 12m04s"), a hand first when a task waits for you.
struct MenuBarBox: Equatable {
    struct Segment: Equatable {
        var symbol: String
        var text: String
    }

    var segments: [Segment]
    var pace: Pace?
    var waiting: Bool
    var idle: Bool
    /// A celebration: the box takes the outcome's colours.
    var outcome: Outcome? = nil

    private var colors: (NSColor, NSColor) {
        if let outcome { return (NSColor(outcome.palette[0]), NSColor(outcome.palette[1 % outcome.palette.count])) }
        if waiting { return (NSColor(red: 1.00, green: 0.70, blue: 0.25, alpha: 1), .systemOrange) }
        if idle { return (NSColor(white: 0.62, alpha: 1), NSColor(white: 0.48, alpha: 1)) }
        switch pace {
        case .green: return (NSColor(red: 0.30, green: 0.80, blue: 0.68, alpha: 1), NSColor(red: 0.16, green: 0.68, blue: 0.40, alpha: 1))
        case .yellow: return (NSColor(red: 1.00, green: 0.80, blue: 0.35, alpha: 1), NSColor(red: 1.00, green: 0.58, blue: 0.10, alpha: 1))
        case .red: return (NSColor(red: 1.00, green: 0.50, blue: 0.33, alpha: 1), NSColor(red: 0.90, green: 0.20, blue: 0.38, alpha: 1))
        default: return (NSColor.controlAccentColor.withAlphaComponent(0.75), .controlAccentColor)
        }
    }

    /// The symbols, made once: looking them up every second was most of the item's cost.
    private static var symbols: [String: NSImage] = [:]

    private var ink: NSColor { pace == .yellow && !waiting ? NSColor.black.withAlphaComponent(0.8) : .white }

    func image() -> NSImage {
        let height: CGFloat = 18
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .heavy)
            .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
        let parts = segments.map { seg -> (NSImage?, NSAttributedString) in
            let key = "\(seg.symbol)|\(ink == .white)"
            if MenuBarBox.symbols[key] == nil {
                MenuBarBox.symbols[key] = NSImage(systemSymbolName: seg.symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
            }
            return (MenuBarBox.symbols[key], NSAttributedString(string: seg.text, attributes: attrs))
        }
        let pad: CGFloat = 8, iconGap: CGFloat = 3, segmentGap: CGFloat = 9
        var width = pad * 2 + segmentGap * CGFloat(max(0, parts.count - 1))
        for (icon, text) in parts { width += (icon?.size.width ?? 0) + iconGap + ceil(text.size().width) }
        let (light, deep) = colors
        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { rect in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: height / 2, yRadius: height / 2)
            NSGradient(starting: light, ending: deep)?.draw(in: shape, angle: 0)
            // Light from above, as on the bars.
            NSGradient(starting: NSColor.white.withAlphaComponent(0.35), ending: NSColor.white.withAlphaComponent(0))?
                .draw(in: shape, angle: -90)
            var x = pad
            for (icon, text) in parts {
                if let icon {
                    icon.draw(in: NSRect(x: x, y: (height - icon.size.height) / 2, width: icon.size.width,
                                         height: icon.size.height))
                    x += icon.size.width + iconGap
                }
                let size = text.size()
                text.draw(at: NSPoint(x: x, y: (height - size.height) / 2))
                x += ceil(size.width) + segmentGap
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = segments.map(\.text).joined(separator: " ")
        return image
    }
}
