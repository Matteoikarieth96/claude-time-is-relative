import AppKit
import SwiftUI

// TaskETA: the Claude Code tasks of this Mac, each with a bar (elapsed time, estimate,
// likely range), in a panel on the desktop and in the menu bar. Data: the live files the
// task-eta hooks write in ~/.claude/task-eta/live/.
//
//   TaskETA                         the app (menu bar count + desktop panel)
//   TaskETA --login on|off          open at login, then exit (used by build.sh)
//   TaskETA --snapshot FILE.png [--dark] [--demo]   render the panel to a PNG, then exit
//   TaskETA --selftest              check the parsers of files written by others, exit 0 if all pass
//   TASKETA_DEBUG_DIR=DIR TaskETA    the app, also writing its state to DIR 4 times a second (for tests)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TaskStore()
    private let prefs = Prefs()
    private var panel: PanelController?
    private var status: StatusController?
    private var debugTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One app at a time: a lock only the menu bar app holds. Checking the running apps with the
        // same bundle id also caught a `--snapshot` run of the same binary, and the app quit.
        if !AppDelegate.takeInstanceLock() {
            NSApp.terminate(nil) // already running
            return
        }
        let panel = PanelController(store: store) { [weak self] in self?.prefs.panelVisible = false }
        prefs.onPanel = { visible in visible ? panel.show() : panel.hide() }
        self.panel = panel
        status = StatusController(store: store, prefs: prefs)
        store.start()
        if prefs.panelVisible { panel.show() }
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
            "list shown=\(min(store.pageLimit, store.visible.count)) of \(store.visible.count) hidden_tests=\(store.hiddenAutomated)",
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
    static func render(to url: URL, dark: Bool, demo: Bool) -> Bool {
        let store = demo ? TaskStore.demo() : TaskStore()
        if !demo { store.reload() }
        let view = PanelView(store: store)
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

        print(failures.isEmpty ? "selftest ok" : "selftest failed: " + failures.joined(separator: "; "))
        return failures.isEmpty
    }
}

extension TaskStore {
    /// Sample tasks for the snapshot: one per colour of the bar.
    static func demo() -> TaskStore {
        let now = Date().timeIntervalSince1970
        func task(_ prompt: String, _ cwd: String, _ model: String, _ effort: String, start: Double,
                  est: Double?, low: Double?, high: Double?, status: String = "running",
                  dur: Double? = nil, end: Double? = nil, declared: Double? = nil) -> LiveTask {
            LiveTask(session: nil, cwd: cwd, transcript: nil, prompt: prompt, startTs: now - start,
                     model: model, effort: effort, modelKnown: true, category: nil, estimateS: est,
                     estimateLabel: est.map(approxEstimate), lowS: low, highS: high, estimateMin: declared,
                     idleS: 0, status: status, endTs: end.map { now - $0 }, durS: dur)
        }
        let items = [
            TaskItem(id: "a", data: task("Add dark mode to the settings page", "acme-web", "opus-5-5", "high",
                                         start: 75, est: 120, low: 68, high: 150), quiet: 4),
            TaskItem(id: "b", data: task("Fix the flaky login test", "acme-api", "sonnet-5-5", "medium",
                                         start: 170, est: 140, low: 90, high: 260), quiet: 10),
            TaskItem(id: "c", data: task("Research three note-taking apps and compare them", "notes",
                                         "opus-5-5", "xhigh", start: 1500, est: 600, low: 300, high: 1200),
                     quiet: 20),
            TaskItem(id: "d", data: task("Convert the photos folder to WebP", "photos", "opus-5-5", "high",
                                         start: 2400, est: 300, low: 180, high: 600), quiet: 1250),
            TaskItem(id: "e", data: task("Write the release notes for v2.1", "acme-web", "opus-5-5", "high",
                                         start: 900, est: 60, low: 40, high: 90, status: "done", dur: 130,
                                         end: 600, declared: 1), quiet: nil),
            TaskItem(id: "f", data: task("Draw a simple logo for the newsletter", "newsletter", "opus-5-5",
                                         "xhigh", start: 400, est: 240, low: 150, high: 400, status: "done",
                                         dur: 95, end: 300, declared: 4), quiet: nil,
                     input: InputMarker(kind: "reply", detail: "", ts: now - 300)),
            TaskItem(id: "g", data: {
                var t = task("Run the test suite on three Python versions", "acme-api", "opus-5-5", "high",
                             start: 1300, est: 1200, low: 700, high: 2000, status: "background", end: 1250)
                t.idleS = 0
                t.bgJobs = ["Run the tests in the background"]
                return t
            }(), quiet: 1250),
            TaskItem(id: "h", data: task("Summarise yesterday's meeting notes", "notes", "sonnet-5-5", "medium",
                                         start: 2000, est: 40, low: 25, high: 70, status: "done", dur: 35,
                                         end: 1960, declared: nil), quiet: nil),
        ]
        return TaskStore(demoItems: items, now: now)
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
if args.contains("--selftest") {
    let ok = MainActor.assumeIsolated { SelfTest.run() }
    exit(ok ? 0 : 1)
}
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    _ = NSApplication.shared
    let ok = MainActor.assumeIsolated {
        Snapshot.render(to: URL(fileURLWithPath: args[i + 1]), dark: args.contains("--dark"),
                        demo: args.contains("--demo"))
    }
    exit(ok ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
