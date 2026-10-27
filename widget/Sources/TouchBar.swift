import AppKit

// TaskETA in the Touch Bar, to the spec of an outside design review.
//
// The button in the Control Strip, next to brightness and volume, always 100 points wide, shows
// the most urgent thing first: what the sessions waiting for you want (orange), for 6 seconds the
// golf name of a hole just finished, the clock of the running task most at risk on its pace
// gradient, the jobs in the background, the turns ended in the last 10 minutes not opened yet,
// and when nothing runs today's round. The other sessions in the same state peek out on the right
// as cards stacked behind it, one per session: no bare number to decode.
//
// A tap fills the Touch Bar: a close button, 4 sessions in view as chips (a tap opens that chat),
// the others a swipe to the left or a tap on the pager away, and the round against par (a tap opens the dashboard). It closes by itself
// 20 seconds after the last touch. Uses the private DFRFoundation calls that Touch Bar tools such
// as MTMR and Pock use; on a Mac without a Touch Bar they do nothing.

/// The private calls, looked up at run time: nothing to link, nothing breaks if they are gone.
private enum PrivateTouchBar {
    private static let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

    static func setInControlStrip(_ id: NSTouchBarItem.Identifier, _ on: Bool) {
        guard let dfr, let sym = dlsym(dfr, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        typealias Fn = @convention(c) (CFString, Bool) -> Void
        unsafeBitCast(sym, to: Fn.self)(id.rawValue as CFString, on)
    }

    @discardableResult
    private static func callClass(_ cls: AnyClass, _ name: String, _ arg: AnyObject) -> Bool {
        let sel = NSSelectorFromString(name)
        guard let method = class_getClassMethod(cls, sel) else { return false }
        typealias Fn = @convention(c) (AnyClass, Selector, AnyObject) -> Void
        unsafeBitCast(method_getImplementation(method), to: Fn.self)(cls, sel, arg)
        return true
    }

    static func addTray(_ item: NSTouchBarItem) { callClass(NSTouchBarItem.self, "addSystemTrayItem:", item) }
    static func removeTray(_ item: NSTouchBarItem) { callClass(NSTouchBarItem.self, "removeSystemTrayItem:", item) }

    static func present(_ bar: NSTouchBar, tray id: NSTouchBarItem.Identifier) {
        let cls: AnyClass = NSTouchBar.self
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        if let method = class_getClassMethod(cls, sel) {
            typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, NSString) -> Void
            unsafeBitCast(method_getImplementation(method), to: Fn.self)(cls, sel, bar, 1, id.rawValue as NSString)
            return
        }
        let old = NSSelectorFromString("presentSystemModalFunctionBar:systemTrayItemIdentifier:")
        if let method = class_getClassMethod(cls, old) {
            typealias Fn = @convention(c) (AnyClass, Selector, NSTouchBar, NSString) -> Void
            unsafeBitCast(method_getImplementation(method), to: Fn.self)(cls, old, bar, id.rawValue as NSString)
        }
    }

    static func dismiss(_ bar: NSTouchBar) {
        if !callClass(NSTouchBar.self, "dismissSystemModalTouchBar:", bar) {
            callClass(NSTouchBar.self, "dismissSystemModalFunctionBar:", bar)
        }
    }
}

/// The OLED palette: true black around, chips a step above, orange for "it's your move".
private enum TB {
    static let chip = NSColor(white: 0.11, alpha: 1)       // #1C1C1E
    static let button = NSColor(white: 0.17, alpha: 1)     // #2C2C2E
    static let waiting = NSColor(red: 1.0, green: 0.624, blue: 0.039, alpha: 1)  // #FF9F0A
    static let waitingLight = NSColor(red: 1.0, green: 0.78, blue: 0.36, alpha: 1)  // #FFC75C, the gradient's start
    static let card = NSColor(white: 0.32, alpha: 1)       // a grey card stacked behind
    static let ink = NSColor(white: 0, alpha: 0.85)       // text on yellow and orange
    static func white(_ a: CGFloat) -> NSColor { NSColor(white: 1, alpha: a) }
}

@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let trayID = NSTouchBarItem.Identifier("io.github.matteoikarieth96.TaskETA.tray")
    static let panelID = NSTouchBarItem.Identifier("io.github.matteoikarieth96.TaskETA.panel")

    /// `TaskETA --touchbar-demo` posts it: the running app shows the demo on the real Touch Bar.
    nonisolated static let demoNotice = Notification.Name("io.github.matteoikarieth96.TaskETA.touchbarDemo")

    let store: TaskStore
    private var tray: NSCustomTouchBarItem?
    private var button: StripButton?
    private var panel: NSTouchBar?
    private var panelView: TouchBarPanelView?
    private var timer: Timer?
    private var lastTouch: Double = 0
    /// Finished sessions opened from the Touch Bar: no longer "your move".
    private var seen: Set<String> = []
    /// The demo, for a minute: the button goes through its states every 3 seconds and the full
    /// bar shows the demo sessions (6, to try the swipe). Then back to the real ones.
    private var demo: (start: Double, store: TaskStore)?
    /// The Control Strip forgets system tray items when it starts again (after sleep, the lock screen, the
    /// login window, a user switch…): these put the button back. Removed in stop().
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var lastPresence: Double = 0
    /// When the button was last seen out of every window (dropped), and when it last went back.
    private var goneSince: Double?
    private var lastReattach: Double = 0
    private var reattached = 0
    /// For TASKETA_DEBUG_DIR: whether the button sits in one of the Touch Bar's windows, and how often it went back.
    var stateForDebug: String { "touchbar on=\(tray != nil) shown=\(button?.window != nil) panel=\(panel != nil) reattached=\(reattached)" }

    init(store: TaskStore) {
        self.store = store
    }

    /// The sessions shown: the demo ones while the demo lasts.
    private var source: TaskStore { demo?.store ?? store }

    func apply(_ on: Bool) { on ? start() : stop() }

    @objc private func startDemo(_ note: Notification) {
        demo = (store.now, TaskStore.demo())
        update()
    }

    private func start() {
        guard tray == nil else { return }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(startDemo), name: Self.demoNotice, object: nil)
        let button = StripButton(model: stripModel(now: store.now), target: self, action: #selector(togglePanel))
        button.widthAnchor.constraint(equalToConstant: 100).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let item = NSCustomTouchBarItem(identifier: Self.trayID)
        item.view = button
        self.button = button
        tray = item
        PrivateTouchBar.addTray(item)
        PrivateTouchBar.setInControlStrip(Self.trayID, true)
        lastPresence = store.now
        update()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        watchControlStrip()
    }

    /// After a wake, a screen wake, a user switch or an unlock: the button again, now and a few seconds later
    /// (the Control Strip may start after the notice). On every app switch only the presence, which is cheap.
    private func watchControlStrip() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let again: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.didWakeNotification), (workspace, NSWorkspace.screensDidWakeNotification),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification),
            (distributed, Notification.Name("com.apple.screenIsUnlocked")),
        ]
        for (center, name) in again {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reattach() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.reattach() }
            }))
        }
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.assertPresence() }
        }))
    }

    /// The tray item out and in again, then its place in the Control Strip.
    private func reattach() {
        guard let tray else { return }
        closePanel()
        PrivateTouchBar.removeTray(tray)
        PrivateTouchBar.addTray(tray)
        assertPresence()
        reattached += 1
        lastReattach = store.now
        goneSince = nil
    }

    private func assertPresence() {
        guard tray != nil else { return }
        PrivateTouchBar.setInControlStrip(Self.trayID, true)
        lastPresence = store.now
    }

    private func stop() {
        DistributedNotificationCenter.default().removeObserver(self, name: Self.demoNotice, object: nil)
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        demo = nil
        timer?.invalidate()
        timer = nil
        closePanel()
        PrivateTouchBar.setInControlStrip(Self.trayID, false)
        if let tray { PrivateTouchBar.removeTray(tray) }
        tray = nil
        button = nil
    }

    // MARK: - what to show

    private static func rank(_ pace: Pace) -> Int {
        switch pace {
        case .red: return 3
        case .yellow: return 2
        case .green: return 1
        case .neutral: return 0
        case .grey: return -1
        }
    }

    /// The sessions in the order that matters: waiting for you (longest wait first), running from
    /// the most at risk, in the background, finished in the last 10 minutes (newest first), stalled.
    func sessions(now: Double) -> [TaskItem] {
        let visible = source.visible
        let waiting = visible.filter { $0.state == .waiting }.sorted { ($0.input?.ts ?? now) < ($1.input?.ts ?? now) }
        let running = visible.filter { $0.state == .running }.sorted {
            (Self.rank($0.pace(at: now)), $0.elapsed(at: now)) > (Self.rank($1.pace(at: now)), $1.elapsed(at: now))
        }
        let background = visible.filter { $0.state == .background }
        let done = visible.filter { $0.state == .done && now - ($0.data.endTs ?? 0) < 600 }
            .sorted { ($0.data.endTs ?? 0) > ($1.data.endTs ?? 0) }
        let stale = visible.filter { $0.state == .stale }
        // One chip per session: its most urgent task (a session that just finished a prompt and
        // runs the next one shows only once).
        var seenSessions: Set<String> = []
        return (waiting + running + background + done + stale).filter {
            seenSessions.insert($0.data.session ?? $0.key).inserted
        }
    }

    private static func short(_ seconds: Double) -> String {
        seconds < 60 ? "\(safeInt(seconds))s" : "\(safeInt(seconds / 60))m"
    }

    private static func waitWord(_ kind: String?) -> String {
        switch kind {
        case "question", "domanda": return L("question", "domanda")
        case "plan", "piano": return L("plan", "piano")
        case "permission", "permesso": return L("permission", "permesso")
        case "choice", "scelta": return L("choice", "scelta")
        case "reply", "risposta": return L("reply", "risposta")
        default: return L("needs you", "ti aspetta")
        }
    }

    func chipModel(_ item: TaskItem, now: Double, wide: Bool) -> ChipModel {
        let name = store.hidePrompts ? URL(fileURLWithPath: item.folderText).lastPathComponent : item.shownName(hidePrompts: false)
        switch item.state {
        case .waiting:
            let what = Self.waitWord(item.input?.kind)
            let since = now - (item.input?.ts ?? now)
            return ChipModel(key: item.key, glyph: "hand.raised.fill", glyphSize: 12, tint: .black, name: name,
                             detail: wide ? L("\(what), waiting \(Self.short(since))", "\(what), da \(Self.short(since))") : what,
                             style: .waiting, progress: nil)
        case .running, .background:
            let elapsed = item.elapsed(at: now)
            var detail = Self.short(elapsed)
            if wide, let est = item.estimateText { detail = L("\(clock(elapsed)) of \(est)", "\(clock(elapsed)) su \(est)") }
            let running = item.state == .running
            return ChipModel(key: item.key, glyph: running ? "circle.fill" : "hourglass", glyphSize: running ? 7 : 12,
                             tint: running ? item.pace(at: now).touchBarFill : TB.white(0.6), name: name, detail: detail,
                             style: .normal, progress: item.estimate.map { elapsed / max($0, 1) })
        case .done:
            var detail = L("done", "fatto")
            if wide, let est = item.estimate, est > 0 {
                let real = item.elapsed(at: now)
                let result = GameMood.current == .miniera ? Ore(real: real, estimate: est, range: item.range).short
                    : GameMood.current.name(Gem(outcomeOf(real: real, estimate: est, range: item.range)))
                detail = L("done, \(result)", "fatto, \(result)")
            }
            return ChipModel(key: item.key, glyph: "checkmark", glyphSize: 12, tint: TB.white(0.6), name: name,
                             detail: detail, style: .done, progress: nil)
        case .stale:
            return ChipModel(key: item.key, glyph: "pause.circle", glyphSize: 12, tint: TB.white(0.45), name: name,
                             detail: L("stalled", "fermo"), style: .stale, progress: nil)
        }
    }

    /// Today's round against par: a hole in one is −2, a birdie −1, a par 0, a bogey +1. In the mine:
    /// the blocks of diamond and the diamonds toward the next.
    func roundText() -> NSAttributedString {
        if GameMood.current == .miniera {
            let mine = MineStats.current(store.indexURL)
            let blocks = mine.blocks == 1 ? L("1 Block of Diamond, ", "1 blocco di diamante, ")
                : L("\(mine.blocks) Blocks of Diamond, ", "\(mine.blocks) blocchi di diamante, ")
            let text = NSMutableAttributedString(string: blocks, attributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: TB.white(0.6),
            ])
            text.append(NSAttributedString(string: "\(mine.toNext)/9", attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: TB.white(0.9),
            ]))
            return text
        }
        let round = gemStats().round
        let score = CampoData.signed(round.holes.reduce(0) { $0 + CampoHole.toPar($1.gem) }, par: true)
        let line = L("Round \(round.number), hole \(round.holes.count)/\(GemStats.roundHoles), ",
                     "Giro \(round.number), buca \(round.holes.count)/\(GemStats.roundHoles), ")
        let text = NSMutableAttributedString(string: line, attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: TB.white(0.6),
        ])
        text.append(NSAttributedString(string: score, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: TB.white(0.9),
        ]))
        return text
    }

    /// The gems from task-eta's index (one cache with the iPhone's server).
    func gemStats() -> GemStats { GemStats.current(store.indexURL) }

    // MARK: - the button in the Control Strip

    private func update() {
        let now = store.now
        // A safety net for a Control Strip that started again with no notice: its place, every 20 s.
        if now - lastPresence >= 20 || now < lastPresence { assertPresence() }
        // Shown, the button lives in one of the Touch Bar's windows; dropped, it has none. Out for 5 s
        // (not while our full bar is up), it goes back, at most every 30 s.
        if tray != nil, panel == nil, button?.window == nil {
            if goneSince == nil { goneSince = now }
            if let since = goneSince, now - since >= 5, now - lastReattach >= 30 { reattach() }
        } else {
            goneSince = nil
        }
        if let panelView {
            panelView.refresh(now: now)
            if now - lastTouch > 20 { closePanel() }
        }
        if let demo, now - demo.start < 60 {
            let states = demoStates()
            button?.model = states[max(0, safeInt((now - demo.start) / 3)) % states.count].model
        } else {
            demo = nil
            button?.model = stripModel(now: now)
        }
    }

    /// The button in each of its states, for the demo and --touchbar-snapshot: the first from the
    /// sessions shown, the others made up, the worst cases included (3 waiting, 102 minutes).
    func demoStates() -> [(caption: String, model: StripModel)] {
        [
            (L("demo: needs you", "demo: ti aspetta"), stripModel(now: store.now)),
            (L("3 need you", "3 ti aspettano"), .waiting(L("needs you", "ti aspetta"), count: 3)),
            (L("1 running", "1 in corso"), .running(75, pace: .green, estimate: 120, high: 150, behind: [])),
            (L("2 running", "2 in corso"), .running(724, pace: .red, estimate: 300, high: 600, behind: [.green])),
            (L("4 running", "4 in corso"), .running(6125, pace: .yellow, estimate: 5000, high: 9000, behind: [.green, .green, .neutral])),
            GameMood.current == .miniera ? (L("ore found", "minerale trovato"), .ore(.smeraldo)) : (L("hole closed", "buca chiusa"), .hole(.sapphire)),
            (L("2 in background", "2 in background"), .background(1300, count: 2)),
            (L("2 done", "2 finite"), .finished(count: 2)),
            GameMood.current == .miniera ? (L("nothing running", "niente in corso"), .diamonds(3, blocks: 2))
                : (L("nothing running", "niente in corso"), .round(11)),
        ]
    }

    func stripModel(now: Double) -> StripModel {
        let visible = source.visible
        let waiting = visible.filter { $0.state == .waiting }.sorted { ($0.input?.ts ?? now) < ($1.input?.ts ?? now) }
        let running = visible.filter { $0.state == .running }.sorted {
            (Self.rank($0.pace(at: now)), $0.elapsed(at: now)) > (Self.rank($1.pace(at: now)), $1.elapsed(at: now))
        }
        let background = visible.filter { $0.state == .background }.sorted { $0.elapsed(at: now) > $1.elapsed(at: now) }
        let yourMove = visible.filter { $0.state == .done && now - ($0.data.endTs ?? 0) < 600 && !seen.contains($0.key) }.count
        let fresh = source.celebrations.values.filter { now - $0.start < 6 }.max { $0.start < $1.start }
        if let first = waiting.first { return .waiting(Self.waitWord(first.input?.kind), count: waiting.count) }
        if let fresh {
            if GameMood.current == .miniera, let ore = fresh.ore { return .ore(ore) }
            return .hole(Gem(fresh.outcome))
        }
        if let worst = running.first {
            return .running(worst.elapsed(at: now), pace: worst.pace(at: now), estimate: worst.estimate,
                            high: worst.range?.high, behind: running.dropFirst().map { $0.pace(at: now) })
        }
        if let job = background.first { return .background(job.elapsed(at: now), count: background.count) }
        if yourMove > 0 { return .finished(count: yourMove) }
        if GameMood.current == .miniera {
            let mine = MineStats.current(store.indexURL)
            return .diamonds(mine.toNext, blocks: mine.blocks)
        }
        return .round(gemStats().round.holes.count)
    }

    // MARK: - the full Touch Bar

    func touched() { lastTouch = store.now }

    @objc private func togglePanel() {
        if panel != nil {
            closePanel()
            return
        }
        let view = TouchBarPanelView(controller: self)
        view.refresh(now: store.now)
        panelView = view
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.panelID]
        panel = bar
        touched()
        PrivateTouchBar.present(bar, tray: Self.trayID)
    }

    @objc func closePanel() {
        if let panel { PrivateTouchBar.dismiss(panel) }
        panel = nil
        panelView = nil
    }

    @objc func openDashboard() {
        DashboardController.shared.show()
        closePanel()
    }

    @objc func openClaude() {
        openChat(nil)
        closePanel()
    }

    /// A chip: the session's chat (or the Claude app); a finished one counts as seen.
    func openTask(_ key: String) {
        let item = source.visible.first { $0.key == key }
        if let item, item.state == .done { seen.insert(key) }
        openChat(item?.chatURL)
        closePanel()
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.panelID, let panelView else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = panelView
        return item
    }

    /// The full Touch Bar drawn off screen, for --touchbar-snapshot.
    func snapshotView() -> TouchBarPanelView {
        let view = TouchBarPanelView(controller: self)
        view.frame = NSRect(x: 0, y: 0, width: 1085, height: 30)
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.refresh(now: store.now)
        view.layoutSubtreeIfNeeded()
        return view
    }
}

/// One session as a chip: what it shows, worked out at each tick.
struct ChipModel: Equatable {
    enum Style { case normal, waiting, done, stale }
    var key: String
    var glyph: String
    var glyphSize: CGFloat
    var tint: NSColor
    var name: String
    var detail: String
    var style: Style
    var progress: Double?
}

/// A session in the full Touch Bar: glyph, name cut at the end, the time (or what Claude waits
/// for) on the right, and a 2-point line of the time gone against the estimate. A real button.
final class TaskChip: NSButton {
    var model: ChipModel {
        didSet {
            guard model != oldValue else { return }
            needsDisplay = true
            setAccessibilityLabel("\(model.name), \(model.detail)")
        }
    }

    init(model: ChipModel, target: AnyObject, action: Selector) {
        self.model = model
        super.init(frame: .zero)
        isBordered = false
        title = ""
        self.target = target
        self.action = action
        setAccessibilityLabel("\(model.name), \(model.detail)")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 30) }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        switch model.style {
        case .normal:
            TB.chip.setFill()
            shape.fill()
        case .waiting:
            TB.waiting.setFill()
            shape.fill()
        case .done, .stale:
            TB.white(0.18).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        let ink: NSColor = model.style == .waiting ? .black : model.style == .normal ? TB.white(0.92) : TB.white(0.6)
        var x: CGFloat = 10
        if let glyph = NSImage(systemSymbolName: model.glyph, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: model.glyphSize, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [model.style == .waiting ? .black : model.tint]))) {
            let size = glyph.size
            glyph.draw(in: NSRect(x: x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += max(size.width, 12) + 6
        }
        let detail = NSAttributedString(string: model.detail, attributes: [
            .font: NSFont.touchBarTime(14),
            .foregroundColor: model.style == .normal ? model.tint : ink,
        ])
        let detailSize = detail.size()
        let y = (bounds.height - detailSize.height) / 2
        detail.draw(at: NSPoint(x: bounds.width - 10 - detailSize.width, y: y))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: model.name, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: ink, .paragraphStyle: paragraph,
        ]).draw(with: NSRect(x: x, y: y, width: max(0, bounds.width - detailSize.width - 18 - x), height: detailSize.height),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        if let progress = model.progress, model.style == .normal {
            // Along the bottom edge (a button's view is flipped: y grows downwards).
            let track = NSRect(x: 7, y: isFlipped ? bounds.height - 3 : 1, width: bounds.width - 14, height: 2)
            TB.white(0.12).setFill()
            track.fill()
            model.tint.setFill()
            NSRect(x: track.minX, y: track.minY, width: track.width * min(1, max(0, progress)), height: 2).fill()
        }
    }
}

/// What the button in the Control Strip shows, worked out at each tick.
struct StripModel: Equatable {
    enum Fill: Equatable { case gradient(NSColor, NSColor), solid(NSColor), outline }
    var fill: Fill
    var ink: NSColor
    var glyph: String?
    var glyphTint: NSColor?      // nil: the ink
    var text: String
    var tail = ""                // after the text, dimmer: the "/18" of the round
    var behind: [NSColor] = []   // the other sessions in the same state, as cards stacked behind
    var label: String            // for VoiceOver
    var filled: Double?          // the gradient fills this share of the capsule, on a dim track (nil: all)
    var tick: Double?            // where the estimate falls, as a share of the capsule

    /// The clock of the running task most at risk, on its pace; the other running sessions behind it.
    /// With an estimate the capsule is the app's bar: filled as far as the time gone, on the same scale.
    static func running(_ elapsed: Double, pace: Pace, estimate: Double? = nil, high: Double? = nil,
                        behind: [Pace]) -> StripModel {
        let (light, deep) = pace.touchBarGradient
        let n = behind.count + 1
        var model = StripModel(fill: .gradient(light, deep), ink: pace == .yellow ? TB.ink : .white, text: clock(elapsed),
                               behind: behind.map(\.touchBarFill),
                               label: n == 1 ? L("Running, \(clock(elapsed))", "In corso, \(clock(elapsed))")
                                   : L("\(n) sessions running, the most at risk at \(clock(elapsed))",
                                       "\(n) sessioni in corso, la più a rischio a \(clock(elapsed))"))
        if let estimate, estimate > 0 {
            let scale = barScale(elapsed: elapsed, estimate: estimate, high: high)
            model.filled = min(1, max(0, elapsed / scale))
            model.tick = min(1, estimate / scale)
        }
        return model
    }

    /// What the session waiting longest wants, in orange.
    static func waiting(_ word: String, count: Int) -> StripModel {
        StripModel(fill: .gradient(TB.waitingLight, TB.waiting), ink: TB.ink, glyph: "hand.raised.fill", text: word,
                   behind: Array(repeating: TB.waiting, count: count - 1),
                   label: count == 1 ? L("A session needs you: \(word)", "Una sessione ti aspetta: \(word)")
                       : L("\(count) sessions need you", "\(count) sessioni ti aspettano"))
    }

    /// For 6 seconds, the name of a hole just finished (in the game's mood), on the colours of its celebration.
    static func hole(_ gem: Gem) -> StripModel {
        let pair: (NSColor, NSColor)
        switch gem {
        case .diamond: pair = (NSColor(red: 1.00, green: 0.74, blue: 0.20, alpha: 1), NSColor(red: 1.00, green: 0.42, blue: 0.60, alpha: 1))
        case .sapphire: pair = (NSColor(red: 0.20, green: 0.70, blue: 0.94, alpha: 1), NSColor(red: 0.48, green: 0.38, blue: 1.00, alpha: 1))
        case .emerald: pair = Pace.green.touchBarGradient
        case .pebble: pair = Pace.red.touchBarGradient
        }
        return StripModel(fill: .gradient(pair.0, pair.1), ink: .white, glyph: "flag.fill", text: GameMood.current.name(gem), label: GameMood.current.name(gem))
    }

    /// For 6 seconds, the ore the pickaxe just found: its name only, on its colours (no icons in the Touch Bar).
    static func ore(_ ore: Ore) -> StripModel {
        let ink: NSColor = ore.lightTone ? TB.ink : .white
        return StripModel(fill: .gradient(ore.tones.light, ore.tones.deep), ink: ink, text: ore.short, label: L("Found: \(ore.name)", "Trovato: \(ore.name)"))
    }

    /// Nothing runs, in the mine: the diamonds on the crafting table toward the next block.
    static func diamonds(_ toNext: Int, blocks: Int) -> StripModel {
        StripModel(fill: .outline, ink: TB.white(0.85), glyph: "square.grid.3x3.fill", glyphTint: TB.white(0.45), text: "\(toNext)",
                   tail: "/\(MineStats.perBlock)",
                   label: L("\(toNext == 1 ? "1 diamond" : "\(toNext) diamonds") of 9 toward block \(blocks + 1)",
                            "\(toNext == 1 ? "1 diamante" : "\(toNext) diamanti") su 9 verso il \(ordinal(blocks + 1)) blocco"))
    }

    /// The job longest in the background, on grey.
    static func background(_ elapsed: Double, count: Int) -> StripModel {
        StripModel(fill: .solid(TB.button), ink: TB.white(0.85), glyph: "hourglass", glyphTint: TB.white(0.6),
                   text: clock(elapsed), behind: Array(repeating: TB.card, count: count - 1),
                   label: count == 1 ? L("A job in background, \(clock(elapsed))", "Un job in background, \(clock(elapsed))")
                       : L("\(count) jobs in the background", "\(count) job in background"))
    }

    /// Turns ended in the last 10 minutes, not opened yet.
    static func finished(count: Int) -> StripModel {
        StripModel(fill: .solid(TB.button), ink: .white, glyph: "checkmark", glyphTint: Pace.green.touchBarFill,
                   text: count == 1 ? L("done", "fatto") : L("done", "fatti"), behind: Array(repeating: TB.card, count: count - 1),
                   label: count == 1 ? L("A session finished", "Una sessione ha finito")
                       : L("\(count) sessions finished", "\(count) sessioni hanno finito"))
    }

    /// Nothing runs: today's round, holes played out of 18.
    static func round(_ holes: Int) -> StripModel {
        StripModel(fill: .outline, ink: TB.white(0.85), glyph: "flag.fill", glyphTint: TB.white(0.45), text: "\(holes)",
                   tail: "/\(GemStats.roundHoles)",
                   label: L("Today's round, hole \(holes) of \(GemStats.roundHoles)", "Giro di oggi, buca \(holes) su \(GemStats.roundHoles)"))
    }
}

/// The button in the Control Strip, drawn: a capsule on a gradient (or grey, or an outline), the
/// glyph and text centred, and the other sessions as cards behind it, each a step shorter and
/// darker, cut off by a black hairline. Redrawn only when what it shows changes.
final class StripButton: NSButton {
    var model: StripModel {
        didSet {
            guard model != oldValue else { return }
            needsDisplay = true
            setAccessibilityLabel(model.label)
        }
    }

    init(model: StripModel, target: AnyObject, action: Selector) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        isBordered = false
        title = ""
        self.target = target
        self.action = action
        setAccessibilityLabel(model.label)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 100, height: 30) }

    private static func capsule(_ rect: NSRect) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let cards = Array(model.behind.prefix(3))
        let peek: CGFloat = [0, 8, 7, 6][cards.count]   // the more cards, the less each shows: room for the text
        let front = NSRect(x: 0, y: 0, width: bounds.width - peek * CGFloat(cards.count), height: bounds.height)
        for (i, color) in cards.enumerated().reversed() {
            let level = CGFloat(i + 1)
            let card = front.offsetBy(dx: peek * level, dy: 0).insetBy(dx: 0, dy: 3 * level)
            color.withAlphaComponent(1 - 0.2 * level).setFill()
            Self.capsule(card).fill()
            // The black hairline that parts it from the card in front.
            let next = front.offsetBy(dx: peek * (level - 1), dy: 0).insetBy(dx: 0, dy: 3 * (level - 1))
            NSColor.black.setFill()
            Self.capsule(next.insetBy(dx: -2, dy: -2)).fill()
        }
        let shape = Self.capsule(front)
        // Where the fill ends: all of the capsule, or as far as the time gone (at least a round end, as in the app).
        var split = front.maxX
        switch model.fill {
        case let .gradient(light, deep):
            guard let filled = model.filled else {
                NSGradient(starting: light, ending: deep)?.draw(in: shape, angle: 0)
                break
            }
            TB.button.setFill()
            shape.fill()
            split = front.minX + max(front.height, front.width * filled)
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            NSGradient(starting: light, ending: deep)?
                .draw(in: NSRect(x: front.minX, y: front.minY, width: split - front.minX, height: front.height), angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        case let .solid(color):
            color.setFill()
            shape.fill()
        case .outline:
            TB.white(0.2).setStroke()
            let ring = Self.capsule(front.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1
            ring.stroke()
        }
        if let tick = model.tick {
            // The estimate: a notch at the top and one at the bottom, never across the clock.
            let x = front.minX + front.width * tick - 0.75
            (x < split ? model.ink.withAlphaComponent(0.5) : TB.white(0.6)).setFill()
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            NSRect(x: x, y: front.minY, width: 1.5, height: 5).fill()
            NSRect(x: x, y: front.maxY - 5, width: 1.5, height: 5).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        if isHighlighted {
            NSColor.black.withAlphaComponent(0.25).setFill()
            shape.fill()
        }
        var glyph = model.glyph.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [model.glyphTint ?? model.ink])))
        func text(_ size: CGFloat, _ ink: NSColor) -> NSAttributedString {
            let font = NSFont.touchBarTime(size)
            let text = NSMutableAttributedString(string: model.text, attributes: [.font: font, .foregroundColor: ink])
            text.append(NSAttributedString(string: model.tail, attributes: [
                .font: font, .foregroundColor: ink.withAlphaComponent(0.45),
            ]))
            return text
        }
        // 15 points, smaller if it does not fit, and at last without the glyph: the word stays whole.
        var gap: CGFloat = glyph == nil ? 0 : 5
        var room = front.width - 14 - (glyph?.size.width ?? 0) - gap
        var fontSize: CGFloat = 15
        func fits() -> Bool { text(fontSize, model.ink).size().width <= room }
        while !fits(), fontSize > 12 { fontSize -= 1 }
        if !fits(), let shown = glyph {
            room += shown.size.width + gap
            glyph = nil
            gap = 0
            fontSize = 13
            if !fits() { fontSize = 12 }
        }
        let size = text(fontSize, model.ink).size()
        var x = front.midX - ((glyph?.size.width ?? 0) + gap + min(size.width, room)) / 2
        if let glyph {
            glyph.draw(in: NSRect(x: x, y: (bounds.height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += glyph.size.width + gap
        }
        let rect = NSRect(x: x, y: (bounds.height - size.height) / 2, width: room, height: size.height)
        // The text in the ink over the fill, light over the track (dark on yellow, white past it).
        for (part, ink) in [(NSRect(x: bounds.minX, y: bounds.minY, width: split - bounds.minX, height: bounds.height), model.ink),
                            (NSRect(x: split, y: bounds.minY, width: bounds.maxX - split, height: bounds.height), TB.white(0.95))]
            where part.width > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath.clip(part)
            text(fontSize, ink).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

/// The full Touch Bar: close (52) · the sessions as chips, 4 in view and the others a swipe away,
/// the 5th peeking out on the right (738) · pager (56) · the round (215).
final class TouchBarPanelView: NSView {
    private weak var controller: TouchBarController?
    private let scroll = NSScrollView()
    private let chips = NSStackView()
    private let pager = NSButton(title: "", target: nil, action: nil)
    private let round = NSButton(title: "", target: nil, action: nil)
    private var close: NSButton?
    private var shown: [String] = []
    private var shownWidth: CGFloat = 0
    private var count = 0
    /// The width of the chips in view, fixed: known before the first layout.
    private static let chipsWidth: CGFloat = 738
    /// Rebuilding the chips can move the scroll: that is not a touch.
    private var rebuilding = false

    init(controller: TouchBarController) {
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: 1085, height: 30))
        let close = NSButton(image: Self.closeImage(), target: controller, action: #selector(TouchBarController.closePanel))
        close.bezelColor = TB.button
        self.close = close
        chips.orientation = .horizontal
        chips.spacing = 6
        chips.alignment = .centerY
        scroll.documentView = chips
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .allowed
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: Loc.changed, object: nil)
        pager.target = self
        pager.action = #selector(pagerTapped)
        pager.bezelColor = TB.button
        round.isBordered = false
        round.target = controller
        round.action = #selector(TouchBarController.openDashboard)
        round.alignment = .left
        let row = NSStackView(views: [close, scroll, pager, round])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        for (view, width) in [(close, 52.0), (scroll, Self.chipsWidth), (pager, 56), (round, 215)] as [(NSView, CGFloat)] {
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: 30),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static func closeImage() -> NSImage {
        NSImage(systemSymbolName: "xmark", accessibilityDescription: L("Close", "Chiudi")) ?? NSImage()
    }

    /// The language changed while the bar is open: the close button's name (the chips and the round
    /// are worked out anew at each tick), and the chips built again at once.
    @objc private func languageChanged(_ note: Notification) {
        close?.image = Self.closeImage()
        shown = []
        if let controller { refresh(now: controller.store.now) }
    }

    @objc private func pagerTapped() {
        controller?.touched()
        showNext(animated: true)
    }

    /// A swipe on the chips keeps the Touch Bar open like a tap, and moves the pager's count.
    @objc private func scrolled(_ note: Notification) {
        if !rebuilding { controller?.touched() }
        updatePager()
    }

    /// The chips not yet wholly in view on the right.
    private func hiddenOnRight() -> [NSView] {
        let edge = scroll.contentView.bounds.minX + Self.chipsWidth + 1
        return chips.arrangedSubviews.filter { $0 is TaskChip && $0.frame.maxX > edge }
    }

    /// The pager: on to the first chip not wholly in view, or back to the start from the end.
    func showNext(animated: Bool) {
        let room = max(0, chips.frame.width - Self.chipsWidth)
        let origin = NSPoint(x: hiddenOnRight().first.map { min($0.frame.minX, room) } ?? 0, y: 0)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                scroll.contentView.animator().setBoundsOrigin(origin)
            }
        } else {
            scroll.contentView.setBoundsOrigin(origin)
        }
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func updatePager() {
        let more = hiddenOnRight().count
        pager.alphaValue = count > 4 ? 1 : 0
        pager.isEnabled = count > 4
        pager.title = more > 0 ? "+\(more) ›" : "‹"
    }

    @objc private func chipTapped(_ sender: TaskChip) { controller?.openTask(sender.model.key) }

    func refresh(now: Double) {
        guard let controller else { return }
        let all = controller.sessions(now: now)
        count = all.count
        let width: CGFloat = count == 1 ? 360 : count == 2 ? 366 : count == 3 ? 242 : count == 4 ? 180 : 168
        let keys = all.map(\.key)
        if keys != shown || width != shownWidth || count == 0 {
            rebuilding = true
            defer { rebuilding = false }
            chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
            if count == 0 {
                let empty = NSTextField(labelWithString: L("No sessions in the last hour", "Nessuna sessione nell'ultima ora"))
                empty.font = .systemFont(ofSize: 14)
                empty.textColor = TB.white(0.5)
                empty.widthAnchor.constraint(equalToConstant: 300).isActive = true
                let open = NSButton(title: L("Open Claude", "Apri Claude"), target: controller, action: #selector(TouchBarController.openClaude))
                open.bezelColor = TB.button
                open.widthAnchor.constraint(equalToConstant: 180).isActive = true
                chips.addView(empty, in: .leading)
                chips.addView(open, in: .leading)
            }
            for item in all {
                let chip = TaskChip(model: controller.chipModel(item, now: now, wide: width >= 242), target: self,
                                    action: #selector(chipTapped(_:)))
                chip.widthAnchor.constraint(equalToConstant: width).isActive = true
                chip.heightAnchor.constraint(equalToConstant: 30).isActive = true
                chips.addView(chip, in: .leading)
            }
            let content = CGFloat(count) * width + CGFloat(max(0, count - 1)) * chips.spacing
            chips.frame = NSRect(x: 0, y: 0, width: max(Self.chipsWidth, content), height: 30)
            chips.layoutSubtreeIfNeeded()
            shown = keys
            shownWidth = width
        } else {
            for case let chip as TaskChip in chips.arrangedSubviews {
                if let item = all.first(where: { $0.key == chip.model.key }) {
                    chip.model = controller.chipModel(item, now: now, wide: width >= 242)
                }
            }
        }
        updatePager()
        round.attributedTitle = controller.roundText()
    }
}

extension NSFont {
    /// The app's clock face: rounded, digits of equal width.
    static func touchBarTime(_ size: CGFloat) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
}

extension Pace {
    /// The button's colour: the deep end of the bar's gradient, bright on the OLED black.
    var touchBarFill: NSColor {
        switch self {
        case .green: return NSColor(red: 0.18, green: 0.75, blue: 0.44, alpha: 1)
        case .yellow: return NSColor(red: 1.00, green: 0.70, blue: 0.20, alpha: 1)
        case .red: return NSColor(red: 0.94, green: 0.22, blue: 0.42, alpha: 1)
        case .grey: return NSColor(white: 0.40, alpha: 1)
        case .neutral: return NSColor.controlAccentColor
        }
    }

    /// The bar's gradient in the app (Views.swift), light on the left, deep on the right.
    var touchBarGradient: (NSColor, NSColor) {
        switch self {
        case .green: return (NSColor(red: 0.37, green: 0.88, blue: 0.77, alpha: 1), touchBarFill)
        case .yellow: return (NSColor(red: 1.00, green: 0.84, blue: 0.42, alpha: 1), NSColor(red: 1.00, green: 0.62, blue: 0.11, alpha: 1))
        case .red: return (NSColor(red: 1.00, green: 0.54, blue: 0.36, alpha: 1), touchBarFill)
        case .grey: return (NSColor(white: 0.55, alpha: 1), touchBarFill)
        case .neutral:
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
            return (accent.blended(withFraction: 0.35, of: .white) ?? accent, accent)
        }
    }
}
