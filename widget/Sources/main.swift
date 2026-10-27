import AppKit
import SwiftUI

// TaskETA: the Claude Code tasks of this Mac, each with a bar (elapsed time, estimate,
// likely range), in a panel on the desktop and in the menu bar. Data: the live files the
// task-eta hooks write in ~/.claude/task-eta/live/.
//
//   TaskETA                         the app (menu bar count + desktop panel)
//   TaskETA --login on|off          open at login, then exit (used by install.py)
//   TaskETA --snapshot FILE.png [--dark] [--golf] [--demo | --celebrate] [--compact] [--burst]
//                                   render the panel to a PNG (example tasks, the four celebrations,
//                                   the short panel, the 69 dots), then exit
//   TaskETA --dashboard-snapshot FILE.png [--dark]   render the dashboard from the real index, then exit
//   TaskETA --switch-snapshot BASE   the panel in a window, in English then after a live switch to Italian
//                                   (BASE-en.png, BASE-it.png; nothing saved), then exit
//   TASKETA_LANG=en|it TaskETA …    any run in that language, without touching the saved choice
//   TaskETA --touchbar-snapshot F.png  render the full Touch Bar with demo tasks, then exit
//   TaskETA --touchbar-demo         the running app shows the Touch Bar demo for a minute, then exit
//   TaskETA --phone-script          write the iPhone script to iCloud Drive > Scriptable, then exit
//   TaskETA --selftest              check the parsers of files written by others, exit 0 if all pass
//   TaskETA --course-report         where you are on Il campo, every trial with its reason, then exit
//   TASKETA_DEBUG_DIR=DIR TaskETA    the app, also writing its state to DIR 4 times a second (for tests);
//                                   with TASKETA_DEBUG_CLICK=1 it clicks the panel's first button, with
//                                   TASKETA_DEBUG_POPOVER=1 it draws the menu bar list to DIR/popover.png
//   TASKETA_DEBUG_REGULAR=1 TaskETA  the app with a Dock icon, for screen tools that list only regular apps
//   TASKETA_DEBUG_TOAST=1 TaskETA    the app, showing one notification of each kind at start (the app's own)
//   TASKETA_DEBUG_CELEBRATE=1 TaskETA the app, celebrating the first rows (one outcome each) every 5 seconds
//   TASKETA_DEBUG_GOLF=1 TaskETA     the app with the mini golf unlocked (not saved), sample games in the dashboard
//   TASKETA_DEBUG_GEMS=1             a sample day of gems in the dashboard
//   TASKETA_DEBUG_COMBO=N            the mini golf's free play as with a combo of N (obstacles from 5)
//   TASKETA_DEBUG_HOLE=N             every game is hole N of the day's round, not written down
//   TASKETA_DEBUG_DASH=edit,all,…    how the dashboard snapshot is drawn (see DashboardGrid.swift)
//   TaskETA --cheer 0|1|2|3         plays the cheer of a hole off that many cushions, then exits
//   TaskETA --snapshot F --demo --holeinone N   the panel with the show of a hole off N cushions
//   TaskETA --snapshot F --demo --dino S        the panel with the dinosaur of the 69th cushion, S seconds in

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TaskStore()
    private let prefs = Prefs()
    private var panel: PanelController?
    private var status: StatusController?
    private var notifier: Notifier?
    private var phone: PhoneServer?
    private var touchBar: TouchBarController?
    private var debugTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One app at a time: a lock only the menu bar app holds. Checking the running apps with the
        // same bundle id also caught a `--snapshot` run of the same binary, and the app quit.
        if !AppDelegate.takeInstanceLock() {
            NSApp.terminate(nil) // already running
            return
        }
        Loc.shared.start()
        NotificationCenter.default.addObserver(forName: Loc.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { NSApp.mainMenu = self?.mainMenu() }
        }
        let panel = PanelController(store: store) { [weak self] in self?.prefs.panelVisible = false }
        prefs.onPanel = { visible in visible ? panel.show() : panel.hide() }
        self.panel = panel
        status = StatusController(store: store, prefs: prefs)
        notifier = Notifier(store: store, prefs: prefs)
        DashboardController.shared.store = store
        SettingsController.shared.store = store
        SettingsController.shared.prefs = prefs
        let phone = PhoneServer(store: store, prefs: prefs)
        prefs.onPhone = { on in phone.apply(on) }
        SettingsController.shared.phone = phone
        self.phone = phone
        let touchBar = TouchBarController(store: store)
        prefs.onTouchBar = { on in MainActor.assumeIsolated { touchBar.apply(on) } }
        self.touchBar = touchBar
        NSApp.mainMenu = mainMenu()
        notifier?.isWatched = { [weak self] in
            (self?.status?.isListShown ?? false) || (self?.panel?.isOnScreen ?? false)
        }
        if ProcessInfo.processInfo.environment["TASKETA_DEBUG_TOAST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.notifier?.showSamplesForDebug() }
        }
        store.start()
        if ProcessInfo.processInfo.environment["TASKETA_DEBUG_CELEBRATE"] != nil {
            // Again every 5 seconds, so a screenshot taken any time catches one.
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.store.celebrateForDebug() }
        }
        if prefs.panelVisible { panel.show() }
        if prefs.phoneOn { phone.apply(true) }
        if prefs.touchBarOn { touchBar.apply(true) }
        if let dir = ProcessInfo.processInfo.environment["TASKETA_DEBUG_DIR"] {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            debugTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.writeDebug(to: url)
            }
            if ProcessInfo.processInfo.environment["TASKETA_DEBUG_CLICK"] != nil {
                // The panel is shown for the test even when the user keeps it off, then put back.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.panel?.show() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    let ok = self?.panel?.clickFirstButtonForDebug() ?? false
                    try? "clicked \(ok) at \(Date().timeIntervalSince1970)\n".write(
                        to: url.appendingPathComponent("click.txt"), atomically: true, encoding: .utf8)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    if self?.prefs.panelVisible == false { self?.panel?.hide() }
                }
            }
            if ProcessInfo.processInfo.environment["TASKETA_DEBUG_POPOVER"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    self?.status?.dumpPopoverForDebug(to: url.appendingPathComponent("popover.png"))
                }
            }
        }
    }

    /// The menu bar while one of the app's windows is in front: the dashboard and the settings
    /// are there too, and the Edit menu makes copy and paste work in the search field.
    private func mainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem()
            holder.submenu = menu
            main.addItem(holder)
            return menu
        }
        func item(_ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            return item
        }
        _ = submenu("TaskETA", [
            item(L("Open the dashboard", "Apri la dashboard"), #selector(openDashboard), "d", target: self),
            item(L("Settings…", "Impostazioni…"), #selector(openSettings), ",", target: self),
            .separator(),
            item(L("Hide TaskETA", "Nascondi TaskETA"), #selector(NSApplication.hide(_:)), "h"),
            item(L("Quit TaskETA", "Esci da TaskETA"), #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = submenu(L("Edit", "Modifica"), [
            item(L("Undo", "Annulla"), Selector(("undo:")), "z"),
            item(L("Redo", "Ripeti"), Selector(("redo:")), "Z"),
            .separator(),
            item(L("Cut", "Taglia"), #selector(NSText.cut(_:)), "x"),
            item(L("Copy", "Copia"), #selector(NSText.copy(_:)), "c"),
            item(L("Paste", "Incolla"), #selector(NSText.paste(_:)), "v"),
            item(L("Select All", "Seleziona tutto"), #selector(NSText.selectAll(_:)), "a"),
        ])
        NSApp.windowsMenu = submenu(L("Window", "Finestra"), [
            item(L("Minimize", "Riduci"), #selector(NSWindow.performMiniaturize(_:)), "m"),
            item(L("Close", "Chiudi"), #selector(NSWindow.performClose(_:)), "w"),
        ])
        return main
    }

    @objc private func openDashboard() { DashboardController.shared.show() }
    @objc private func openSettings() { SettingsController.shared.show() }

    /// flock on ~/.claude/task-eta/.tasketa.lock, kept for the life of the process (the system
    /// drops it when the app exits, even after a crash).
    private static var lockFD: Int32 = -1

    static func takeInstanceLock() -> Bool {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/task-eta")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let fd = open(dir.appendingPathComponent(".tasketa.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return true } // no lock file possible: better two apps than none
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        lockFD = fd
        return true
    }

    private func writeDebug(to dir: URL) {
        guard let panel, let status else { return }
        let f = panel.panel.frame
        var lines = [
            "time \(Date().timeIntervalSince1970)",
            "menubar \(status.titleForDebug)",
            "panel visible=\(panel.panel.isVisible) level=\(panel.panel.level.rawValue) frame=\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))",
            "celebrations \(store.celebrations.values.map { "\($0.outcome)" }.sorted())",
            "list shown=\(min(store.pageLimit, store.groups.count)) of \(store.groups.count) hidden_tests=\(store.hiddenAutomated)",
            MainActor.assumeIsolated { touchBar?.stateForDebug } ?? "touchbar none",
        ]
        for item in store.visible {
            let est = item.estimate.map { clock($0) } ?? "-"
            lines.append("task \(item.state) \(clock(item.elapsed(at: store.now))) est=\(est) declared=\(item.declared.map { clock($0) } ?? "-") pace=\(item.pace(at: store.now)) end=\(Int(item.data.endTs ?? 0)) session=\(item.data.session ?? "-") name=\(item.name)")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("state.txt"), atomically: true, encoding: .utf8)
        if let png = panel.pngForDebug() { try? png.write(to: dir.appendingPathComponent("panel.png")) }
    }
}

@MainActor
enum Snapshot {
    static func render(to url: URL, dark: Bool, demo: Bool, celebrate: Bool = false) -> Bool {
        let store = celebrate ? TaskStore.celebrationDemo() : demo ? TaskStore.demo() : TaskStore()
        let dinoFrame = args.firstIndex(of: "--dino").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil }
        if args.contains("--compact") {
            store.compact = true
            store.blink(waiting: false)
        }
        if args.contains("--burst") { store.dotBurst = DotBurst(count: 69, start: Date().timeIntervalSince1970 - 1.2) }
        if celebrate, GameMood.current == .miniera {
            // The mine's finds already on the ground of their rows (Drops.swift).
            for (key, c) in store.celebrations { if let ore = c.ore { DropStore.shared.add(key, .init(ore: ore, start: 0, detail: c.oreDetail)) } }
        }
        if args.contains("--golf") {
            // A game on, for the golf strip's place: the ball just shot from the first row's dot.
            store.golfUnlocked = true
            for place in ["panel", "popover"] {
                let game = GolfGame.game(place)
                game.size = CGSize(width: 340, height: 300)
                game.pull(from: CGPoint(x: 300, y: 70), to: CGPoint(x: 330, y: 95))
                game.release()
            }
        }
        if !demo && !celebrate { store.reload() }
        let cushions = args.firstIndex(of: "--holeinone").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil }
        let view = PanelView(store: store, scrolls: false)
            .overlay { if let cushions { HoleInOne(start: Date().timeIntervalSince1970 - 1.1, shots: 1, cushions: cushions) } }
            .overlay { if let dinoFrame { DinoComingSoon(start: Date().timeIntervalSince1970 - dinoFrame) } }
            .background(dark ? Color(white: 0.16) : Color(white: 0.95))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}

/// Checks of the code that reads files written by others (Claude's ⏱ line in the transcript, the
/// hooks' live and marker files). Run by CI and by tests/test_review.py.
@MainActor
enum SelfTest {
    static func run() -> Bool {
        let failures = Loc.testing(.it) { checks() } + Loc.testing(.en) { englishChecks() }
        print(failures.isEmpty ? "selftest ok" : "selftest failed: " + failures.joined(separator: "; "))
        return failures.isEmpty
    }

    /// The checks, in Italian where they read text (as they were written).
    private static func checks() -> [String] {
        var failures: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }

        // The line, with its range and kind; the effort "medium" before the colon is not the kind.
        let line = parseDeclaredLine("⏱ Estimated time with sonnet-5-5 medium: ~4 min (likely 2 to 9 min, long)")
        check(line?.seconds == 240, "estimate of the line")
        check(line?.range?.low == 120 && line?.range?.high == 540, "range of the line")
        check(line?.kind == "long", "kind of the line")
        let italian = parseDeclaredLine("⏱ Tempo richiesto con opus-5-5 high: ~10 min (probabile tra 4 e 24 min, medio)")
        check(italian?.seconds == 600 && italian?.range?.low == 240 && italian?.range?.high == 1440
              && italian?.kind == "medium", "older Italian line")
        let agents = parseDeclaredLine("⏱ Estimated time with opus-5-5 high: ~20 min (with subagents)")
        check(agents?.kind == "agents" && agents?.range == nil, "line with subagents and no range")
        check(parseDeclaredLine("⏱ Estimated time with sonnet-5-5 medium: ~40 s")?.kind == nil, "no kind given")
        check(parseDeclaredLine("⏱ Actual time: ~4 min (likely 2 to 9 min: inside)") == nil, "closing line")
        let started = Date()
        _ = parseDeclaredLine("⏱ Estimated time with x: " + String(repeating: "~1 ", count: 200_000))
        check(Date().timeIntervalSince(started) < 1, "a hostile line stays fast")

        // A hostile marker time cannot make the clock negative, infinite or run ahead.
        let now = Date().timeIntervalSince1970
        let task = LiveTask(session: "s", cwd: "acme", transcript: nil, prompt: "secret plan for client X",
                            startTs: now - 100, model: "opus-5-5", effort: "high", modelKnown: true,
                            category: nil, estimateS: 60, estimateLabel: "~1 min", lowS: 30, highS: 90,
                            estimateMin: nil, idleS: 0, status: "running", endTs: nil, durS: nil)
        for ts in [1e300, -1e300, now + 1e9, Double.nan, Double.infinity] {
            let marker = InputMarker(kind: "question", detail: nil, ts: ts).sanitized(now: now)
            let e = TaskItem(id: "t", data: task, quiet: 1, input: marker).elapsed(at: now)
            check(e.isFinite && e >= 0 && e <= 100.5, "marker time \(ts)")
        }

        // The range of the kind Claude declared, from the hook's per-kind numbers.
        var withKinds = task
        withKinds.kinds = ["long": [600, 300, 1200], "bogus": [1, 2, 3]]
        withKinds.kindDeclared = "long"
        let kindRange = withKinds.sanitized().map { TaskItem(id: "k", data: $0, quiet: 1).range } ?? nil
        check(kindRange?.low == 300 && kindRange?.high == 1200, "range of the declared kind")
        check(withKinds.sanitized()?.kinds?["bogus"] == nil, "unknown kinds dropped")

        // Prompts and titles hidden for screen sharing.
        let item = TaskItem(id: "h", data: task, quiet: 1, title: "Client X roadmap")
        let hidden = item.shownName(hidePrompts: true)
        check(hidden == "Task in acme" && !hidden.contains("secret") && !hidden.contains("Client"), "hidden name")

        // Past the estimate: how far and how many times, in Italian.
        check(overText(40) == "+40s" && overText(610) == "+10 min", "overrun text")
        check(timesText(2.5) == "×2,5" && timesText(6.04) == "×6" && timesText(12.3) == "×12", "times text")
        var late = task
        late.estimateS = 30
        let lateItem = TaskItem(id: "l", data: late, quiet: 1)
        check(lateItem.overrunText(at: now) == "+1 min oltre la stima (×3,3)", "overrun of a late task")
        check(TaskItem(id: "t", data: task, quiet: 1).overrun(at: now) != nil, "task past its estimate")

        // One group per session, the current task first.
        let demo = TaskStore.demo()
        let groups = demo.groups
        check(groups.count == Set(groups.map(\.id)).count, "one group per session")
        check(groups.contains { $0.items.count == 3 && $0.main.state == .running }, "a session with earlier requests")

        // The chat link: only plausible ids of the Claude app.
        check(appSessionID(fromFileName: "local_ab12-cd34.json") == "local_ab12-cd34", "app session id")
        for bad in ["local_.json", "local_a b.json", "local_a&x=1.json", "other_ab.json", "local_ab.txt",
                    "local_" + String(repeating: "a", count: 65) + ".json"] {
            check(appSessionID(fromFileName: bad) == nil, "app session id \(bad)")
        }
        var linked = TaskItem(id: "c", data: task, quiet: 1)
        linked.appSession = "local_ab12"
        check(linked.chatURL?.absoluteString == "claude://code/continue?session=local_ab12", "chat link")

        // The outcome of a finished task, one per celebration.
        let outcomes = TaskStore.celebrationDemo().items.compactMap { $0.outcome(at: now)?.outcome }
        check(outcomes == [.faster, .onTime, .exact, .slower], "outcomes \(outcomes)")
        let slow = Celebration(outcome: .slower, start: now, delta: 610, estimate: 120)
        check(slow.detail == "+10 min (×6,1)", "detail of a slow task: \(slow.detail)")
        check(Celebration(outcome: .faster, start: now, delta: -100).detail == "−1m40s", "detail of a speedrun")

        // Mini golf: the ball stays inside the list and stops; it drops in the hole only once away.
        var shot = GolfBall(position: CGPoint(x: 50, y: 50), velocity: CGVector(dx: 1400, dy: -900), leftHole: true)
        var inside = true
        for _ in 0..<2000 {
            _ = Golf.advance(&shot, dt: 1.0 / 60, size: CGSize(width: 100, height: 80), hole: CGPoint(x: -100, y: -100))
            if shot.position.x < 0 || shot.position.x > 100 || shot.position.y < 0 || shot.position.y > 80 { inside = false }
        }
        check(inside && shot.velocity == .zero, "golf ball stays inside and stops")
        check(shot.cushions >= 3, "cushions counted: \(shot.cushions)")
        var putt = GolfBall(position: CGPoint(x: 20, y: 50), velocity: CGVector(dx: 200, dy: 0), leftHole: true)
        check(Golf.advance(&putt, dt: 0.25, size: CGSize(width: 300, height: 100), hole: CGPoint(x: 60, y: 52)),
              "golf ball over the hole")
        var tee = GolfBall(position: CGPoint(x: 60, y: 50), velocity: CGVector(dx: 50, dy: 0))
        check(!Golf.advance(&tee, dt: 0.1, size: CGSize(width: 300, height: 100), hole: CGPoint(x: 60, y: 50)),
              "not in the hole before leaving it")

        // The mini golf's history: points, streaks, records, par.
        var golf = GolfStats()
        let ace = golf.finish(start: 0, end: 5, shots: 1, sunk: true, cushions: 0, totalCushions: 0, nearMisses: 0)
        check(ace.record.points == 200 && ace.par == "Ace" && ace.streak == 1, "ace: \(ace.record.points) \(ace.par)")
        let bank = golf.finish(start: 10, end: 30, shots: 2, sunk: true, cushions: 3, totalCushions: 4, nearMisses: 1)
        check(bank.record.points == 275 && bank.newCushionRecord && bank.streak == 2, "bank shot: \(bank.record.points)")
        _ = golf.finish(start: 40, end: 99, shots: 5, sunk: false, cushions: 0, totalCushions: 2, nearMisses: 2)
        check(golf.streak == 0 && golf.bestStreak == 2 && golf.holes == 2 && golf.bestCushions == 3, "golf streaks")
        check(golf.nearMisses == 3 && golf.totalCushions == 6 && golf.shots == 8, "golf totals")
        check(golf.parCounts.map(\.count) == [1, 1, 0, 0, 0], "golf par counts")
        let earned = Set(golf.achievements(dotClicks: 70, unlocked: true, unlockedByKeys: false).filter(\.earned).map(\.id))
        check(earned == ["curious", "nice", "unlocked", "first", "ace", "bank", "billiard"], "achievements: \(earned.sorted())")
        check(GolfChallenge.ace.isMet(by: ace.record, streak: 1) && !GolfChallenge.twoShots.isMet(by: ace.record, streak: 1),
              "challenge of the day")

        // The dots of the easter egg bounce off the walls and stay inside.
        check(bounce(5, 10) == 5 && bounce(15, 10) == 5 && bounce(25, 10) == 5 && bounce(-3, 10) == 3, "bounce")
        check((0..<500).allSatisfy { let b = bounce(Double($0) * 7.3 - 900, 40); return b >= 0 && b <= 40 }, "bounce stays inside")

        // The dashboard's reading of the index: headless runs out, outcomes, the home folder.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sample: [String: Any] = ["version": 2, "tasks": [
            "a": ["start_ts": now - 3600, "dur_s": 125, "estimate_min": 2, "est_range": [60, 300], "cwd": home,
                  "model": "opus-5-5", "effort": "high", "prompt": "Sistema  il\nbug"],
            "b": ["start_ts": now - 7200, "dur_s": 900, "estimate_min": 2, "est_range": [60, 300], "cwd": "/x/acme"],
            "c": ["start_ts": now - 60, "dur_s": 30, "headless": true],
            "d": ["start_ts": now - 30 * 86400, "dur_s": 40, "cwd": "/x/acme"],
            "e": ["start_ts": Double.nan, "dur_s": 40]]]
        let sampleURL = FileManager.default.temporaryDirectory.appendingPathComponent("tasketa-selftest-\(getpid()).json")
        if let raw = try? JSONSerialization.data(withJSONObject: sample.mapValues { v -> Any in
            guard let tasks = v as? [String: [String: Any]] else { return v }
            return tasks.filter { ($0.value["start_ts"] as? Double)?.isNaN != true }
        }) {
            try? raw.write(to: sampleURL)
            let past = PastTask.load(from: sampleURL)
            try? FileManager.default.removeItem(at: sampleURL)
            check(past.count == 3 && past.first?.id == "a", "index tasks read: \(past.map(\.id))")
            check(past.first?.project == "Home" && past.first?.prompt == "Sistema il bug", "project and prompt")
            check(past.first?.outcome == .exact && past.dropFirst().first?.outcome == .slower, "outcomes from the index")
            let stats = DashStats(past)
            check(stats.withEstimate == 2 && stats.inside == 1 && stats.bestStreak == 1, "dashboard stats")
        }

        // The iPhone script, as the app writes it to iCloud: every blank filled in.
        if let script = PhoneScript.text(token: "tok123") {
            check(!script.contains("\"__TASKETA_URL__\"") && !script.contains("\"__TASKETA_IP_URL__\"")
                  && !script.contains("\"__TASKETA_TOKEN__\"") && script.contains("\"tok123\"")
                  && script.contains("LANG_SET = \"it\""), "iPhone script filled in")
        }

        // The gems: one per outcome, points with the streak, the levels, the round of 18.
        check(Gem(.exact) == .diamond && Gem(.faster) == .sapphire && Gem(.onTime) == .emerald && Gem(.slower) == .pebble, "gems")
        let gems = GemStats.sample(now: Date(timeIntervalSince1970: now))
        check(gems.holes.map(\.points).prefix(5) == [100, 325, 150, 0, 150], "gem points: \(gems.holes.map(\.points))")
        check(gems.streak == 1 && gems.bestStreak == 5, "gem streaks: \(gems.streak) \(gems.bestStreak)")
        check(GemLevel.of(0).name == "Principiante" && GemLevel.of(4_000).name == "Caddie"
              && GemLevel.of(3_999).next?.name == "Caddie" && GemLevel.of(10_000_000).next == nil, "gem levels")
        check(GemChallenge.cleanFive.progress(gems.holes) == 1 && GemChallenge.twoDiamonds.progress(gems.holes) == 3,
              "gem challenges")

        // The game's map: the days numbered as Python's date.toordinal(), the holes closed in order, the numbers
        // for the page. A full round of 18 diamonds on one day closes holes 1 and 2, not 3 (10.000 points).
        check(CampoGame.ordinal(1970, 1, 1) == 719_163 && CampoGame.ordinal(2024, 2, 29) == 738_945
              && CampoGame.ordinal(2026, 10, 24) == 739_913, "campo day numbers")
        let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))?.timeIntervalSince1970 ?? now
        let round = (0..<18).map { i in
            PastTask(id: "r\(i)", start: morning + Double(i) * 600, real: 300, estimate: 300, range: (200, 450),
                     model: "opus-5-5", project: "demo", prompt: "", session: "s", kind: "quick")
        }
        let roundGems = GemStats(round, now: Date(timeIntervalSince1970: morning + 18 * 600))
        let field = CampoGame(round, points: roundGems.points).course()
        check(roundGems.points == 8_525 && field.prefix(3).map(\.closed) == [true, true, false], "campo holes: \(field.map(\.closed))")
        let page = CampoData.make(round, golf: [], phone: .init(synced: nil, note: ""), now: Date(timeIntervalSince1970: morning + 18 * 600))
        check(page.nowHole == 3 && page.prevGreen == 4_000 && page.played == 18 && page.restart == 0 && page.clean == 100
              && page.holes[0].s == "done" && page.holes[2].s == "now" && page.json.hasPrefix("{"), "campo page: \(page.nowHole) \(page.restart)")

        // Il campo's engine: powers, reasons, the mini golf's courses and Claude's own score (CampoEngine.swift).
        failures += CampoEngineTest.failures()
        failures += GolfRulesTest.failures()
        failures += GameMoodTest.failures()
        failures += MineTest.failures()

        return failures
    }

    /// The same texts in English, the base language.
    private static func englishChecks() -> [String] {
        var failures: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { failures.append("en: " + what) } }
        let n = 3
        let text: LText = "\(n) running"
        check(text.template == "{1} running" && text.text == "3 running", "template of a text")
        check(L("\(n) running", "\(n) in corso") == "3 running", "the English text")
        check(Loc.testing(.it) { L("\(n) running", "\(n) in corso") } == "3 in corso", "the Italian text")
        check(timesText(2.5) == "×2.5" && timesText(6.04) == "×6", "times text")
        let now = Date().timeIntervalSince1970
        let task = LiveTask(session: "s", cwd: "acme", transcript: nil, prompt: "p", startTs: now - 100,
                            model: "opus-5-5", effort: "high", modelKnown: true, category: nil, estimateS: 30,
                            estimateLabel: "~1 min", lowS: 20, highS: 45, estimateMin: nil, idleS: 0,
                            status: "running", endTs: nil, durS: nil)
        check(TaskItem(id: "l", data: task, quiet: 1).overrunText(at: now) == "+1 min over the estimate (×3.3)", "overrun")
        check(TaskItem(id: "h", data: task, quiet: 1).shownName(hidePrompts: true) == "Task in acme", "hidden name")
        check(TaskItem(id: "w", data: task, quiet: 1, input: InputMarker(kind: "plan", detail: nil, ts: now)).waitingText
              == "plan to approve", "waiting text")
        check(Celebration(outcome: .slower, start: now, delta: 610, estimate: 120).detail == "+10 min (×6.1)", "detail")
        check(Outcome.exact.stamp == "🤌 Chef's kiss" && Outcome.onTime.stamp == "🎉 GG", "stamps")
        check(NotifyMode.watching.label == "With the widget in view", "notify mode")
        check(Loc.decimal(2.5) == "2.5" && Loc.testing(.it) { Loc.decimal(2.5) } == "2,5", "decimals")
        check(Loc.integer(12345) == "12,345" && Loc.testing(.it) { Loc.integer(12345) } == "12.345", "thousands")
        check(LangChoice.en.resolved == .en && LangChoice.it.resolved == .it && LangChoice.it.label == "Italiano", "choices")
        return failures
    }
}

extension TaskStore {
    /// Four tasks just finished, one per outcome, each caught in the middle of its celebration.
    static func celebrationDemo() -> TaskStore {
        let now = Date().timeIntervalSince1970
        func done(_ id: String, _ prompt: String, est: Double, low: Double, high: Double, dur: Double,
                  end: Double) -> TaskItem {
            TaskItem(id: id, data: LiveTask(session: id, cwd: "acme-web", transcript: nil, prompt: prompt,
                                            startTs: now - end - dur, model: "opus-5-5", effort: "high",
                                            modelKnown: true, category: nil, estimateS: est,
                                            estimateLabel: approxEstimate(est), lowS: low, highS: high,
                                            estimateMin: nil, idleS: 0, status: "done", endTs: now - end,
                                            durS: dur), quiet: nil)
        }
        let items = [
            done("c1", L("Redo the app icon", "Rifai l'icona dell'app"), est: 600, low: 300, high: 1200, dur: 160, end: 10),
            done("c2", L("Add filters to the table", "Aggiungi i filtri alla tabella"), est: 300, low: 180, high: 600, dur: 420, end: 20),
            done("c3", L("Fix the login bug", "Correggi il bug del login"), est: 240, low: 150, high: 400, dur: 236, end: 30),
            done("c4", L("Move the database to Postgres", "Migra il database a Postgres"), est: 120, low: 68, high: 150, dur: 730, end: 40),
        ]
        let store = TaskStore(demoItems: items, now: now)
        let starts: [String: Double] = ["c1": 0.75, "c2": 1.1, "c3": 0.55, "c4": 1.2]
        for item in items {
            guard let result = item.outcome(at: now) else { continue }
            store.celebrations[item.key] = Celebration(outcome: result.outcome, start: now - (starts[item.id] ?? 1),
                                                       delta: result.delta, estimate: item.estimate ?? 0, range: item.range)
        }
        return store
    }

    /// Sample tasks for the snapshot: one per colour of the bar, and a session with earlier requests.
    static func demo() -> TaskStore {
        let now = Date().timeIntervalSince1970
        func task(_ prompt: String, _ cwd: String, _ model: String, _ effort: String, start: Double,
                  est: Double?, low: Double?, high: Double?, status: String = "running",
                  dur: Double? = nil, end: Double? = nil, declared: Double? = nil, session: String) -> LiveTask {
            LiveTask(session: session, cwd: cwd, transcript: nil, prompt: prompt, startTs: now - start,
                     model: model, effort: effort, modelKnown: true, category: nil, estimateS: est,
                     estimateLabel: est.map(approxEstimate), lowS: low, highS: high, estimateMin: declared,
                     idleS: 0, status: status, endTs: end.map { now - $0 }, durS: dur)
        }
        let items = [
            TaskItem(id: "a", data: task(L("Add dark mode to the settings page", "Aggiungi il tema scuro alla pagina impostazioni"), "acme-web", "opus-5-5",
                                         "high", start: 75, est: 120, low: 68, high: 150, session: "s1"), quiet: 4),
            TaskItem(id: "a2", data: task(L("Fix the colour of the buttons", "Sistema il colore dei bottoni"), "acme-web", "opus-5-5", "high",
                                          start: 700, est: 60, low: 40, high: 90, status: "done", dur: 150,
                                          end: 540, declared: 1, session: "s1"), quiet: nil),
            TaskItem(id: "a3", data: task(L("Rename the form components", "Rinomina i componenti del form"), "acme-web", "opus-5-5", "high",
                                          start: 1100, est: 90, low: 50, high: 150, status: "done", dur: 55,
                                          end: 1040, declared: 2, session: "s1"), quiet: nil),
            TaskItem(id: "b", data: task(L("Fix the flaky login test", "Correggi il test di login instabile"), "acme-api", "sonnet-5-5", "medium",
                                         start: 170, est: 140, low: 90, high: 260, session: "s2"), quiet: 10),
            TaskItem(id: "c", data: task(L("Compare three note-taking apps", "Confronta tre app per prendere appunti"), "notes", "opus-5-5", "xhigh",
                                         start: 1500, est: 600, low: 300, high: 1200, session: "s3"), quiet: 20),
            TaskItem(id: "d", data: task(L("Convert the photos folder to WebP", "Converti la cartella delle foto in WebP"), "photos", "opus-5-5", "high",
                                         start: 2400, est: 300, low: 180, high: 600, session: "s4"), quiet: 1250),
            TaskItem(id: "e", data: task(L("Write the release notes for v2.1", "Scrivi le note di rilascio della v2.1"), "acme-web", "opus-5-5", "high",
                                         start: 900, est: 60, low: 40, high: 90, status: "done", dur: 130,
                                         end: 600, declared: 1, session: "s5"), quiet: nil),
            TaskItem(id: "f", data: task(L("Draw a simple logo for the newsletter", "Disegna un logo semplice per la newsletter"), "newsletter", "opus-5-5",
                                         "xhigh", start: 400, est: 240, low: 150, high: 400, status: "done",
                                         dur: 95, end: 300, declared: 4, session: "s6"), quiet: nil,
                     input: InputMarker(kind: "reply", detail: "", ts: now - 300)),
            TaskItem(id: "g", data: {
                var t = task(L("Run the tests on three Python versions", "Lancia i test su tre versioni di Python"), "acme-api", "opus-5-5", "high",
                             start: 1300, est: 1200, low: 700, high: 2000, status: "background", end: 1250,
                             session: "s7")
                t.idleS = 0
                t.bgJobs = [L("Tests in the background", "Test in background")]
                return t
            }(), quiet: 1250),
            TaskItem(id: "h", data: task(L("Summarise yesterday's meeting notes", "Riassumi gli appunti della riunione di ieri"), "notes", "sonnet-5-5",
                                         "medium", start: 2000, est: 40, low: 25, high: 70, status: "done", dur: 35,
                                         end: 1960, declared: nil, session: "s8"), quiet: nil),
        ]
        let store = TaskStore(demoItems: items, now: now)
        store.expanded = ["s1"] // the snapshot shows a session opened on its earlier requests
        return store
    }
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--login"), i + 1 < args.count {
    let on = args[i + 1] == "on"
    if let error = LoginItem.set(on) {
        FileHandle.standardError.write("Open at login not changed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
    print(on ? "Open at login on (status: \(LoginItem.status.rawValue))." : "Open at login off.")
    exit(0)
}
if args.contains("--phone-script") {
    // Writes the iPhone script to iCloud Drive > Scriptable as the app does, says how it went, exits.
    let folder = PhoneScript.iCloudFolder
    let token = UserDefaults.standard.string(forKey: "phoneToken") ?? ""
    guard let text = PhoneScript.text(token: token) else { print("script not in the app's Resources"); exit(1) }
    print("folder visible: \(FileManager.default.fileExists(atPath: folder.path))")
    do {
        try text.write(to: folder.appendingPathComponent("TaskETA.js"), atomically: true, encoding: .utf8)
        print("written: \(text.count) characters")
        exit(0)
    } catch {
        print("not written: \(error)")
        exit(1)
    }
}
if args.contains("--course-report") {
    // Where the user is on the course, with every reason, from the index on disk (CampoEngine.swift).
    let started = Date()
    let engine = CampoNow.shared.engine()
    print(engine.report)
    print(String(format: L("(read and worked out in %.0f ms)", "(letto e calcolato in %.0f ms)"), Date().timeIntervalSince(started) * 1000))
    exit(0)
}
if args.contains("--selftest") {
    let ok = MainActor.assumeIsolated { SelfTest.run() }
    exit(ok ? 0 : 1)
}
if let i = args.firstIndex(of: "--cheer"), i + 1 < args.count {
    // Plays the cheer of a level (0-3) and exits: for trying the sounds.
    _ = NSApplication.shared
    HoleCheer.cheer(level: Int(args[i + 1]) ?? 0)
    RunLoop.main.run(until: Date().addingTimeInterval(6))
    exit(0)
}
if args.contains("--touchbar-demo") {
    // Tells the running app to go through the Touch Bar's states on the real Touch Bar, then exits.
    DistributedNotificationCenter.default().postNotificationName(TouchBarController.demoNotice, object: nil,
                                                                 userInfo: nil, deliverImmediately: true)
    exit(0)
}
/// The canvas of --touchbar-snapshot, laid out from the top.
private final class SnapshotCanvas: NSView {
    override var isFlipped: Bool { true }
}

if let i = args.firstIndex(of: "--touchbar-snapshot"), i + 1 < args.count {
    // The full Touch Bar as it opens, with the demo tasks, at its real size (1085 × 30 points, 2x),
    // the same after a swipe, and under them the button in the Control Strip in each of its states
    // (the first from the demo tasks).
    _ = NSApplication.shared
    let ok = MainActor.assumeIsolated { () -> Bool in
        let controller = TouchBarController(store: TaskStore.demo())
        let states = controller.demoStates()
        let view = SnapshotCanvas(frame: NSRect(x: 0, y: 0, width: 1085, height: 162))
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        func caption(_ text: String, _ frame: NSRect, _ alignment: NSTextAlignment = .center) {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 10)
            label.textColor = NSColor(white: 1, alpha: 0.5)
            label.alignment = alignment
            label.frame = frame
            view.addSubview(label)
        }
        view.addSubview(controller.snapshotView())
        caption(L("As it opens: 4 sessions, the fifth peeks out on the right", "Come si apre: 4 sessioni, la quinta spunta a destra"), NSRect(x: 60, y: 33, width: 738, height: 14), .left)
        let swiped = controller.snapshotView()
        swiped.showNext(animated: false)
        swiped.frame.origin.y = 52
        view.addSubview(swiped)
        caption(L("After a swipe to the left (or a tap on +N)", "Dopo uno swipe verso sinistra (o un tocco su +N)"), NSRect(x: 60, y: 85, width: 738, height: 14), .left)
        let step = (1085 - 100) / CGFloat(states.count - 1)
        for (n, (text, model)) in states.enumerated() {
            let x = CGFloat(n) * step
            let button = StripButton(model: model, target: controller, action: #selector(TouchBarController.closePanel))
            button.frame = NSRect(x: x, y: 110, width: 100, height: 30)
            view.addSubview(button)
            caption(text, NSRect(x: x - 10, y: 144, width: 120, height: 14))
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: args[i + 1]))) != nil
    }
    exit(ok ? 0 : 1)
}
if let i = args.firstIndex(of: "--dashboard-snapshot"), i + 1 < args.count {
    _ = NSApplication.shared
    let ok = MainActor.assumeIsolated { () -> Bool in
        let model = DashboardModel(indexURL: TaskStore.indexURL,
                                   chatLink: { _ in nil })
        model.historyLimit = 12
        model.loadNow()
        CampoSnapshot.prepare(model.all, dark: args.contains("--dark"), width: 940)
        let view = DashboardContent(model: model).padding(20).frame(width: 980)
            .background(args.contains("--dark") ? Color(white: 0.12) : Color(white: 0.96))
            .environment(\.colorScheme, args.contains("--dark") ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.5
        renderer.proposedSize = ProposedViewSize(width: 980, height: nil)
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: args[i + 1]))) != nil
    }
    exit(ok ? 0 : 1)
}
if let i = args.firstIndex(of: "--switch-snapshot"), i + 1 < args.count {
    // The panel in a window in English, then the same window after a live switch to Italian (nothing
    // saved): BASE-en.png and BASE-it.png, to check that an open window follows the language.
    _ = NSApplication.shared
    let ok = MainActor.assumeIsolated { () -> Bool in
        Loc.shared.preview(.en)
        let host = NSHostingView(rootView: PanelView(store: TaskStore.demo(), scrolls: false))
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 350, height: 900),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        func shot(_ lang: Lang) -> Bool {
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            host.setFrameSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { return false }
            return (try? png.write(to: URL(fileURLWithPath: args[i + 1] + "-\(lang.rawValue).png"))) != nil
        }
        let en = shot(.en)
        Loc.shared.preview(.it)
        let it = shot(.it)
        window.orderOut(nil)
        return en && it
    }
    exit(ok ? 0 : 1)
}
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    _ = NSApplication.shared
    let ok = MainActor.assumeIsolated {
        Snapshot.render(to: URL(fileURLWithPath: args[i + 1]), dark: args.contains("--dark"),
                        demo: args.contains("--demo"), celebrate: args.contains("--celebrate"))
    }
    exit(ok ? 0 : 1)
}

GameMood.migrate()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// TASKETA_DEBUG_REGULAR: a Dock icon, so screen tools that list only regular apps can see the windows (tests only).
app.setActivationPolicy(ProcessInfo.processInfo.environment["TASKETA_DEBUG_REGULAR"] != nil ? .regular : .accessory)
app.run()
