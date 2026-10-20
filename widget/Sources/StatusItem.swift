import AppKit
import Combine
import SwiftUI

/// Menu bar item: a tick and the number of tasks finished in the last 30 minutes, nothing else.
/// A click opens the list and the settings.
final class StatusController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: TaskStore
    private var subscription: AnyCancellable?

    init(store: TaskStore, prefs: Prefs) {
        self.store = store
        super.init()
        let host = NSHostingController(rootView: MenuView(store: store, prefs: prefs))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle(_:))
            button.imagePosition = .imageLeft
            let icon = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Claude Code tasks done")
            icon?.isTemplate = true
            button.image = icon
        }
        subscription = store.$now.sink { [weak self] _ in self?.refresh() }
    }

    var titleForDebug: String { "title='\(item.button?.attributedTitle.string ?? "")'" }

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
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func refresh() {
        guard let button = item.button else { return }
        let done = store.doneRecentlyCount
        button.attributedTitle = NSAttributedString(string: " \(done)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        ])
        button.toolTip = "\(done) task\(done == 1 ? "" : "s") done in the last 30 minutes"
    }
}
