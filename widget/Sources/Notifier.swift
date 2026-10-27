import AppKit
import Combine
import SwiftUI
import UserNotifications

/// Opens a session's chat in the Claude app (a claude://code/continue link), else the app itself.
func openChat(_ url: URL?) {
    if let url, url.scheme == "claude" {
        NSWorkspace.shared.open(url)
        return
    }
    if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Announcements when a task finishes or starts waiting for you. Only changes seen while the app
/// runs count: what was already done or waiting at start-up is not announced again. They go to
/// macOS when it allows them; an app signed ad hoc, as this one is when built on the Mac, is
/// refused ("Notifications are not allowed for this application"), so the app then shows its own
/// in the top right corner. A click on either opens the session's chat.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let store: TaskStore
    private let prefs: Prefs
    private let center = UNUserNotificationCenter.current()
    private let toasts = ToastController()
    private var native = false
    private let startedAt = Date().timeIntervalSince1970
    private var seen: [String: TaskState] = [:]
    /// Finished tasks, announced a few seconds later: a turn that ends with a question shows up
    /// first as done, then as waiting, and only "waiting" should be announced.
    private var pendingDone: [String: Double] = [:]
    private var primed = false
    private var subscriptions: Set<AnyCancellable> = []

    /// Whether the widget is in view (the list open, or the desktop panel visible on a screen).
    var isWatched: () -> Bool = { true }

    /// Wait before announcing a finished task.
    static let doneDelay: Double = 3

    init(store: TaskStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
        super.init()
        center.delegate = self
        store.$items.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.check() }
            .store(in: &subscriptions)
        prefs.$notifyDone.combineLatest(prefs.$notifyWaiting)
            .sink { [weak self] done, waiting in if done || waiting { self?.authorize() } }
            .store(in: &subscriptions)
    }

    private func check() {
        let now = Date().timeIntervalSince1970
        var next: [String: TaskState] = [:]
        for item in store.items where store.showAutomated || !item.automated {
            let key = item.key
            let state = item.state
            let before = seen[key]
            next[key] = state
            guard primed else { continue }
            if state == .waiting, before != .waiting {
                pendingDone[key] = nil
                if prefs.notifyWaiting { post(item, waiting: true) }
            } else if state == .done, before != .done, before != .waiting,
                      before != nil || item.data.startTs > startedAt {
                pendingDone[key] = pendingDone[key] ?? now
            }
            if state == .done, let since = pendingDone[key], now - since >= Notifier.doneDelay {
                pendingDone[key] = nil
                if prefs.notifyDone { post(item, waiting: false) }
            }
        }
        pendingDone = pendingDone.filter { next[$0.key] == .done }
        seen = next
        primed = true
    }

    private func post(_ item: TaskItem, waiting: Bool) {
        switch prefs.notifyMode {
        case .never: return
        case .watching: if !isWatched() { return }
        case .always: break
        }
        let hide = store.hidePrompts
        let now = Date().timeIntervalSince1970
        let title = waiting ? L("Claude needs you", "Claude ti aspetta")
            : item.outcome(at: now).map { L("\($0.outcome.emoji) Task done", "\($0.outcome.emoji) Task finito") } ?? L("Task done", "Task finito")
        let subtitle = item.shownName(hidePrompts: hide)
        let body: String
        if waiting {
            body = item.waitingText(hidePrompts: hide)
        } else {
            var parts = [L("Actual \(clock(item.elapsed(at: now)))", "Reale \(clock(item.elapsed(at: now)))")]
            if let est = item.estimateText { parts.append(L("est. \(est)", "stima \(est)")) }
            if let over = item.overrunText(at: now) { parts.append(over) }
            body = parts.joined(separator: ", ")
        }
        guard native else {
            toasts.show(Toast(waiting: waiting, title: title, subtitle: subtitle, body: body,
                              late: !waiting && item.overrun(at: now) != nil, url: item.chatURL))
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.threadIdentifier = item.data.session ?? item.id
        if let url = item.chatURL { content.userInfo = ["url": url.absoluteString] }
        let id = "\(item.key)|\(waiting ? "waiting" : "done")"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// One notification of each kind, of the app's own (tests only).
    func showSamplesForDebug() {
        toasts.show(Toast(waiting: false, title: L("Task done", "Task finito"), subtitle: L("Sample finished task", "Esempio di task finito"),
                          body: L("Actual 4m10s, est. ~3 min, +1 min over the estimate", "Reale 4m10s, stima ~3 min, +1 min oltre la stima"), late: true))
        toasts.show(Toast(waiting: true, title: L("Claude needs you", "Claude ti aspetta"), subtitle: L("Sample waiting task", "Esempio di task in attesa"),
                          body: L("has a question for you", "ha una domanda per te")))
    }

    private func authorize() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.native = granted }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shown even while the list is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["url"] as? String
        DispatchQueue.main.async { openChat(raw.flatMap { URL(string: $0) }) }
        completionHandler()
    }
}

// MARK: - the app's own notifications

struct Toast {
    var waiting: Bool
    var title: String
    var subtitle: String
    var body: String
    var late = false
    var url: URL?
}

/// One notification: an icon in the colour of what happened, the task and the times. With the
/// pointer on it a small ✕ shows up: it closes the notification without opening the chat.
struct ToastView: View {
    let toast: Toast
    let onClick: () -> Void
    var onClose: () -> Void = {}
    @State private var hover = false

    var body: some View {
        let tint: Color = toast.waiting ? .orange : (toast.late ? Pace.red.textColor : Pace.green.color)
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: toast.waiting ? "hand.raised.fill" : "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(toast.title).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 4)
                    if toast.url != nil {
                        Text(L("Open the chat", "Apri la chat"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(hover ? Color.primary : Color.secondary)
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(hover ? 1 : 0)
                    .allowsHitTesting(hover)
                    .help(L("Close the notification", "Chiudi la notifica"))
                    .accessibilityLabel(L("Close the notification", "Chiudi la notifica"))
                }
                Text(toast.subtitle).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                Text(toast.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 340, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: onClick)
    }
}

/// Shows the app's own notifications in the top right corner, under the menu bar and above every
/// window, one under the other. Each goes away after a few seconds, on its ✕, or on a click, which
/// also opens the session's chat. One per session: a new one from the same chat takes the old one's place.
final class ToastController {
    private var shown: [NSPanel] = []
    /// The chat each notification opens, by panel: a session's new one replaces its old one.
    private var chats: [ObjectIdentifier: String] = [:]

    func show(_ toast: Toast) {
        if let chat = toast.url?.absoluteString {
            for old in shown where chats[ObjectIdentifier(old)] == chat { close(old) }
        }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let host = FirstClickHostingView(rootView: ToastView(toast: toast, onClick: { [weak self, weak panel] in
            openChat(toast.url)
            if let panel { self?.close(panel) }
        }, onClose: { [weak self, weak panel] in
            if let panel { self?.close(panel) }
        }))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        var glassed = false
        #if compiler(>=6.2) // NSGlassEffectView is in the macOS 26 SDK only
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: host.frame)
            glass.cornerRadius = 18
            glass.contentView = host
            panel.contentView = glass
            glassed = true
        }
        #endif
        if !glassed {
            let effect = NSVisualEffectView(frame: host.frame)
            effect.material = .popover
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 14
            effect.layer?.masksToBounds = true
            effect.addSubview(host)
            panel.contentView = effect
        }
        panel.setContentSize(size)
        shown.append(panel)
        if let chat = toast.url?.absoluteString { chats[ObjectIdentifier(panel)] = chat }
        layout()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
        NSSound(named: toast.waiting ? "Ping" : "Glass")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + (toast.waiting ? 12 : 7)) { [weak self, weak panel] in
            if let panel { self?.close(panel) }
        }
    }

    private func close(_ panel: NSPanel) {
        guard shown.contains(panel) else { return }
        shown.removeAll { $0 === panel }
        chats[ObjectIdentifier(panel)] = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
        layout()
    }

    /// Newest on top, the others below it.
    private func layout() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        var top = area.maxY - 10
        for panel in shown.reversed() {
            let size = panel.frame.size
            panel.setFrameTopLeftPoint(NSPoint(x: area.maxX - size.width - 10, y: top))
            top -= size.height + 8
        }
    }
}
