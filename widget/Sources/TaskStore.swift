import AppKit

/// One file of ~/.claude/task-eta/live/, written by the task-eta hooks (task_eta.py).
struct LiveTask: Decodable {
    var session: String?
    var cwd: String?
    var transcript: String?
    var prompt: String?
    var startTs: Double
    var model: String?
    var effort: String?
    var modelKnown: Bool?
    var category: String?
    var estimateS: Double?     // suggested estimate, seconds
    var estimateLabel: String? // the same, as the hook wrote it ("~2 min")
    var lowS: Double?          // likely range around the suggested estimate, seconds
    var highS: Double?
    var estimateMin: Double?   // the estimate Claude declared in its reply (known at the end)
    var idleS: Double?         // time the index does not count: elapsed = now - start - idle
    var status: String?        // "running", "background" (turn over, jobs still running) or "done"
    var endTs: Double?         // end of the last turn
    var durS: Double?          // real duration from the index
    var transcriptOffset: Double? = nil // transcript size at the prompt: Claude's ⏱ line comes after it
    var entrypoint: String? = nil       // "sdk-cli": a headless `claude -p` run (tests, scripts)
    var bgJobs: [String]? = nil         // background jobs still running when the turn ended
    var kinds: [String: [Double?]]? = nil // per kind of work: [estimate, low, high] seconds, from the hook
    var kindHint: String? = nil         // the kind the similar past requests point to (the hook's guess)
    var kindDeclared: String? = nil     // the kind Claude declared in its ⏱ line (known at the end)
    var estRange: [Double]? = nil       // the range Claude declared in its ⏱ line, seconds (known at the end)

    /// The same task with every number that is not a plausible time (NaN, infinite, absurdly large)
    /// dropped, so hostile or broken files cannot crash the conversions further on. Nil if even
    /// the start time is not plausible.
    func sanitized() -> LiveTask? {
        guard let start = sane(startTs), start > 0 else { return nil }
        var t = self
        t.startTs = start
        t.estimateS = sane(estimateS); t.lowS = sane(lowS); t.highS = sane(highS)
        t.estimateMin = sane(estimateMin); t.idleS = sane(idleS); t.endTs = sane(endTs); t.durS = sane(durS)
        t.transcriptOffset = sane(transcriptOffset)
        if let r = estRange, r.count == 2, let lo = sane(r[0]), let hi = sane(r[1]), lo >= 0, hi > lo {
            t.estRange = [lo, hi]
        } else {
            t.estRange = nil
        }
        t.kinds = kinds.map { all in
            all.filter { kindNames.contains($0.key) }.mapValues { row in row.prefix(3).map { sane($0) } }
        }
        if let k = kindDeclared, !kindNames.contains(k) { t.kindDeclared = nil }
        if let k = kindHint, !kindNames.contains(k) { t.kindHint = nil }
        return t
    }
}

/// Size and modification date of a file: when they are the same, its content is too.
func fileStamp(_ path: String) -> String {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let date = attrs[.modificationDate] as? Date, let size = attrs[.size] as? NSNumber else { return "" }
    return "\(size.intValue)@\(date.timeIntervalSince1970)"
}

/// The kinds of work task_eta.py estimates (KINDS there).
let kindNames: Set<String> = ["quick", "medium", "long", "agents"]

/// A number usable as seconds or a timestamp: finite and within ±1e11 (about 3,000 years).
func sane(_ value: Double?) -> Double? {
    guard let v = value, v.isFinite, abs(v) < 1e11 else { return nil }
    return v
}

/// Int of a Double that never traps: NaN and infinities become 0, the rest is clamped.
func safeInt(_ value: Double) -> Int {
    guard value.isFinite else { return 0 }
    return Int(max(-1e12, min(1e12, value)))
}

/// True for a plain file: reading a FIFO or a device would block the app.
func isRegularFile(_ path: String) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeRegular
}

/// <session>.input: the session waits for the user. Written by the hooks, deleted as soon as a
/// tool runs again or the user writes.
struct InputMarker: Decodable {
    var kind: String?   // question, plan, choice, permission, reply (older versions: Italian names)
    var detail: String?
    var ts: Double?

    /// The marker with a time that is plausible and not in the future (a hostile 1e300 made the
    /// clock negative).
    func sanitized(now: Double) -> InputMarker {
        var m = self
        m.ts = sane(ts).map { min($0, now) }
        return m
    }
}

/// In list order: what needs you first, finished tasks last.
enum TaskState: Int { case waiting, running, background, stale, done }

enum Pace { case neutral, green, yellow, red, grey }

/// A running task whose transcript is silent this long is stopped: interrupted, or stuck.
let staleAfter: Double = 15 * 60
/// Background jobs write nothing in the transcript until they report back: give them longer.
let backgroundStaleAfter: Double = 3 * 3600
/// Finished and stopped tasks disappear after this; a task waiting for you stays longer.
let hideAfter: Double = 60 * 60
let waitingHideAfter: Double = 3 * 3600

struct TaskItem: Identifiable {
    let id: String
    let data: LiveTask
    let quiet: Double?             // seconds since the transcript last changed (open tasks only)
    var input: InputMarker? = nil  // the session waits for you
    var declared: Double? = nil    // Claude's ⏱ estimate, read from the transcript, seconds
    var declaredRange: (low: Double, high: Double)? = nil  // the range in Claude's ⏱ line, seconds
    var declaredKind: String? = nil  // the kind of work in Claude's ⏱ line
    var title: String? = nil       // the session's title in the Claude app sidebar
    var appSession: String? = nil  // the session's id in the Claude app ("local_…"), for the chat link

    var state: TaskState {
        if input != nil { return .waiting }
        switch data.status {
        case "done": return .done
        case "background": return (quiet ?? 0) > backgroundStaleAfter ? .stale : .background
        default: return (quiet ?? 0) > staleAfter ? .stale : .running
        }
    }

    /// Elapsed time without what the index leaves out. The clock stops while the task waits
    /// for you and at the last activity of a stopped task.
    func elapsed(at now: Double) -> Double {
        let upTo = { (t: Double) in max(0, t - self.data.startTs - (self.data.idleS ?? 0)) }
        let finished = data.durS ?? upTo(data.endTs ?? now)
        switch state {
        case .done:
            return finished
        case .waiting:
            if data.status == "done" { return finished }
            if data.status == "background" { return upTo(now) }
            return upTo(min(input?.ts ?? now, now))
        case .stale:
            return upTo(now - (quiet ?? 0))
        case .running, .background:
            return upTo(now)
        }
    }

    /// The tick on the bar: Claude's own estimate (its ⏱ line) once known, else the hook's.
    var estimate: Double? {
        if let m = data.estimateMin, m > 0 { return m * 60 }
        if let d = declared, d > 0 { return d }
        return data.estimateS
    }

    /// The likely range: the one in Claude's own ⏱ line (from the index at the end, or read from the
    /// transcript), else the hook's range for the kind Claude declared, else the hook's suggestion
    /// moved along when Claude wrote a different estimate.
    var range: (low: Double, high: Double)? {
        if let r = data.estRange, r.count == 2 { return (r[0], r[1]) }
        if let r = declaredRange, r.high > r.low { return r }
        if let kind = declaredKind ?? data.kindDeclared, let row = data.kinds?[kind], row.count == 3,
           let lo = row[1], let hi = row[2], hi > lo {
            return (lo, hi)
        }
        guard let lo = data.lowS, let hi = data.highS, hi > lo else { return nil }
        guard let est = estimate, let suggested = data.estimateS, suggested > 0 else { return (lo, hi) }
        let k = est / suggested
        return (lo * k, hi * k)
    }

    func pace(at now: Double) -> Pace {
        if state == .stale { return .grey }
        guard let est = estimate, est > 0 else { return .neutral }
        let e = elapsed(at: now)
        if e <= est { return .green }
        if e <= max(range?.high ?? est, est) { return .yellow }
        return .red
    }

    func visible(at now: Double) -> Bool {
        switch state {
        case .running, .background: return true
        case .waiting: return now - (input?.ts ?? now) < waitingHideAfter
        case .stale:
            let after = data.status == "background" ? backgroundStaleAfter : staleAfter
            return (quiet ?? 0) < after + hideAfter
        case .done: return now - (data.endTs ?? data.startTs) < hideAfter
        }
    }

    /// The same task across the renames of its live file (<session>.json, then <session>-<start>.json).
    var key: String { "\(data.session ?? id)|\(safeInt(data.startTs))" }

    /// The session's chat in the Claude app, when it is one of the app's sidebar sessions.
    var chatURL: URL? { appSession.flatMap { URL(string: "claude://code/continue?session=\($0)") } }

    /// Seconds past the estimate and how many times the estimate, once the task runs over it.
    func overrun(at now: Double) -> (seconds: Double, ratio: Double)? {
        guard state != .stale, let est = estimate, est > 0 else { return nil }
        let e = elapsed(at: now)
        return e > est ? (e - est, e / est) : nil
    }

    /// Headless `claude -p` runs (benchmarks, scripts), hidden unless the user asks for them.
    /// Older live files have no entrypoint: a session in a temporary folder counts as one.
    var automated: Bool {
        if let e = data.entrypoint { return e == "sdk-cli" }
        let t = data.transcript ?? ""
        return t.contains("/-private-tmp-") || t.contains("/-tmp-")
    }
}

/// The visible tasks of one session: the first is the one the row shows, the others are the
/// session's earlier requests.
struct TaskGroup: Identifiable {
    let id: String
    let items: [TaskItem]
    var main: TaskItem { items[0] }
    var earlier: [TaskItem] { Array(items.dropFirst()) }
    /// A finished (or stopped) section can be taken off the list.
    var closable: Bool { main.state == .done || main.state == .stale }
}

/// The session id of the Claude app ("local_…") from the name of its session file, if plausible.
func appSessionID(fromFileName name: String) -> String? {
    guard name.hasSuffix(".json") else { return nil }
    let id = String(name.dropLast(5))
    let rest = id.dropFirst("local_".count)
    guard id.hasPrefix("local_"), (1...64).contains(rest.count),
          rest.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
    return id
}

/// Reads the live folder every 2 seconds and ticks the clock every second. Besides the small
/// live files it reads only the start of each running task's reply, once, for Claude's ⏱ line.
final class TaskStore: ObservableObject {
    @Published private(set) var items: [TaskItem] = [] { didSet { generation += 1 } }
    @Published private(set) var now = Date().timeIntervalSince1970 { didSet { generation += 1 } }
    /// Bumped whenever what `visible` depends on changes: the list is filtered and sorted once.
    private var generation = 0
    private var visibleCache: (generation: Int, items: [TaskItem]) = (-1, [])
    /// How many tasks the list shows: 5, then 5 more per click on "5 more".
    @Published var pageLimit = 5
    @Published var showAutomated: Bool {
        didSet {
            UserDefaults.standard.set(showAutomated, forKey: "showAutomated")
            generation += 1
        }
    }
    /// Show the folder instead of prompts, session titles, questions and job names: the panel is on
    /// every Space and the menu can be open while the screen is shared.
    @Published var hidePrompts: Bool {
        didSet { UserDefaults.standard.set(hidePrompts, forKey: "hidePrompts") }
    }
    /// Sessions opened to show their earlier requests.
    @Published var expanded: Set<String> = []
    /// Finished tasks taken off the list (their keys), remembered for a day.
    @Published private(set) var dismissed: Set<String> { didSet { generation += 1 } }
    /// The desktop panel shows only the counts, no times: a click on its header switches.
    @Published var compact: Bool {
        didSet { if !demo { UserDefaults.standard.set(compact, forKey: "panelCompact") } }
    }
    /// The short panel blinks when a task finishes or starts waiting for you.
    @Published private(set) var flash: Flash?
    /// The easter egg of the dot next to "in corso": every click ever, kept across restarts (101 in
    /// all open the mini golf, more than one sitting is fine).
    @Published private(set) var dotClicks: Int {
        didSet { if !demo { UserDefaults.standard.set(dotClicks, forKey: "dotClicks") } }
    }
    /// The clicks of this run, never stopping more than `runGap`: the surprises at 8, 69 and 101
    /// count these, so they come back every run. Not saved.
    @Published private(set) var dotRun = 0
    /// Clicks since the app started. Not saved.
    @Published private(set) var dotSession = 0
    /// The longest run ever.
    @Published private(set) var dotBestRun: Int {
        didSet { if !demo { UserDefaults.standard.set(dotBestRun, forKey: "dotBestRun") } }
    }
    private var lastDotTap = 0.0
    static let runGap = 1.5
    /// Mini golf on the dot, unlocked for good at its 101st click (see Golf.swift).
    @Published var golfUnlocked: Bool {
        didSet { if !demo { UserDefaults.standard.set(golfUnlocked, forKey: "golfUnlocked") } }
    }
    @Published var dotBurst: DotBurst?
    /// Rows celebrating a task that has just finished (task key -> celebration).
    @Published var celebrations: [String: Celebration] = [:]
    private var lastStates: [String: TaskState] = [:]
    /// Finished tasks, celebrated once still finished at the next reload: a turn that ends with a
    /// question shows up first as done, then as waiting, and that one is no win.
    private var pendingCelebration: [String: Double] = [:]
    private var statesPrimed = false

    static let pageSize = 5

    let dir: URL
    private var timer: Timer?
    private var ticks = 0
    private let demo: Bool
    private var declaredFound: [String: DeclaredLine] = [:]  // task key -> Claude's ⏱ line
    private var scannedUpTo: [String: UInt64] = [:]    // task key -> transcript bytes already read
    private var titles: [String: AppSession] = [:]     // CLI session id -> the session in the app sidebar
    private var titlesReadAt: Double = 0
    /// Live files already decoded, kept while their size and date do not change.
    private var decodedFiles: [String: (stamp: String, task: LiveTask)] = [:]
    /// The app's session files already read (path -> date, CLI session id, session).
    private var sessionFiles: [String: (stamp: String, cli: String, session: AppSession)] = [:]

    /// The Claude app keeps one file per session, with the CLI session id and the title shown in
    /// its sidebar near the top: the first 4 KB of each are enough.
    static let appSessionsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)

    /// ~/.claude/task-eta/live, or where TASK_ETA_LIVE_DIR, TASK_ETA_DIR or CLAUDE_CONFIG_DIR put it
    /// (the same order as task_eta.py; an app opened from the Finder sees none of them).
    static let defaultDir: URL = {
        let env = ProcessInfo.processInfo.environment
        if let live = env["TASK_ETA_LIVE_DIR"], !live.isEmpty { return URL(fileURLWithPath: live, isDirectory: true) }
        if let data = env["TASK_ETA_DIR"], !data.isEmpty {
            return URL(fileURLWithPath: data, isDirectory: true).appendingPathComponent("live", isDirectory: true)
        }
        let claude = env["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
        return claude.appendingPathComponent("task-eta/live", isDirectory: true)
    }()

    /// task-eta's index, next to the live folder: what the dashboard, the game and the gems read.
    static var indexURL: URL { defaultDir.deletingLastPathComponent().appendingPathComponent("index.json") }
    var indexURL: URL { dir.deletingLastPathComponent().appendingPathComponent("index.json") }
    /// The clicks on the "in corso" dot that open the mini golf.
    static let golfClicks = 101

    init(dir: URL = TaskStore.defaultDir) {
        self.dir = dir
        self.demo = false
        self.showAutomated = UserDefaults.standard.bool(forKey: "showAutomated")
        self.hidePrompts = UserDefaults.standard.bool(forKey: "hidePrompts")
        self.compact = UserDefaults.standard.bool(forKey: "panelCompact")
        self.dotClicks = UserDefaults.standard.integer(forKey: "dotClicks")
        self.dotBestRun = UserDefaults.standard.integer(forKey: "dotBestRun")
        self.golfUnlocked = UserDefaults.standard.bool(forKey: "golfUnlocked")
            || DashDebug.golf
        let cutoff = Date().timeIntervalSince1970 - 24 * 3600
        self.dismissed = Set((UserDefaults.standard.stringArray(forKey: "dismissed") ?? []).filter {
            (Double($0.split(separator: "|").last ?? "") ?? 0) > cutoff
        })
    }

    init(demoItems: [TaskItem], now: Double) {
        self.dir = TaskStore.defaultDir
        self.demo = true
        self.showAutomated = false
        self.hidePrompts = false
        self.compact = false
        self.dotClicks = 0
        self.dotBestRun = 0
        self.golfUnlocked = false
        self.dismissed = []
        self.items = demoItems
        self.now = now
    }

    func start() {
        guard !demo, timer == nil else { return }
        reload()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common) // keeps ticking while a menu or popover is open
        self.timer = timer
    }

    /// The clock moves every second only while a task runs (its time is on screen); otherwise every
    /// 15 seconds is enough, for finished tasks to leave the list after an hour.
    private func tick() {
        ticks += 1
        if ticks % 2 == 0 { reload() }
        let running = items.contains { $0.state == .running || $0.state == .background }
        if running || ticks % 15 == 0 { now = Date().timeIntervalSince1970 }
    }

    func reload() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else {
            if !items.isEmpty { items = [] }
            return
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let now = Date().timeIntervalSince1970
        if now - titlesReadAt > 10 { readTitles(); titlesReadAt = now }
        var out: [TaskItem] = []
        var seenFiles: Set<String> = []
        defer { decodedFiles = decodedFiles.filter { seenFiles.contains($0.key) } }
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let url = dir.appendingPathComponent(name)
            guard isRegularFile(url.path) else { continue }
            let stamp = fileStamp(url.path)
            let task: LiveTask
            if let cached = decodedFiles[name], cached.stamp == stamp, !stamp.isEmpty {
                task = cached.task
            } else {
                guard let raw = try? Data(contentsOf: url),
                      let decoded = try? decoder.decode(LiveTask.self, from: raw),
                      let fresh = decoded.sanitized() else { continue }
                task = fresh
                decodedFiles[name] = (stamp, fresh)
            }
            seenFiles.insert(name)
            var quiet: Double?
            if task.status != "done" {
                if let path = task.transcript,
                   let attrs = try? fm.attributesOfItem(atPath: path),
                   let modified = attrs[.modificationDate] as? Date {
                    quiet = now - modified.timeIntervalSince1970
                } else if let path = task.transcript, !path.isEmpty, now - task.startTs > 120,
                          !fm.fileExists(atPath: path) {
                    continue // the transcript is gone (the session was deleted): nothing left to follow
                } else if now - task.startTs > 3 * 3600 {
                    quiet = now - task.startTs // no transcript to look at: give up after 3 hours
                }
            }
            var item = TaskItem(id: name, data: task, quiet: quiet)
            if let session = task.session, let app = titles[session] {
                item.title = app.title
                item.appSession = app.id
            }
            // The marker belongs to the session's current task, <session>.json.
            let marker = task.session.map { dir.appendingPathComponent("\($0).input") }
            if let session = task.session, name == "\(session).json", let marker, isRegularFile(marker.path),
               let raw = try? Data(contentsOf: marker) {
                item.input = ((try? decoder.decode(InputMarker.self, from: raw)) ?? InputMarker()).sanitized(now: now)
            }
            if task.estimateMin == nil, task.status != "done", let line = declaredLine(task) {
                item.declared = line.seconds
                item.declaredRange = line.range
                item.declaredKind = line.kind
            }
            out.append(item)
        }
        items = out
        updateCelebrations(out, now: now)
    }

    private func readTitles() {
        let fm = FileManager.default
        guard let accounts = try? fm.contentsOfDirectory(atPath: TaskStore.appSessionsDir.path) else { return }
        guard let cliRe = try? NSRegularExpression(pattern: #""cliSessionId"\s*:\s*"([^"]+)""#),
              let titleRe = try? NSRegularExpression(pattern: #""title"\s*:\s*("(?:[^"\\]|\\.)*")"#)
        else { return }
        var found: [String: AppSession] = [:]
        var fresh: [String: (stamp: String, cli: String, session: AppSession)] = [:]
        defer { sessionFiles = fresh }
        for account in accounts {
            let accountDir = TaskStore.appSessionsDir.appendingPathComponent(account)
            for org in (try? fm.contentsOfDirectory(atPath: accountDir.path)) ?? [] {
                let orgDir = accountDir.appendingPathComponent(org)
                for name in (try? fm.contentsOfDirectory(atPath: orgDir.path)) ?? []
                where name.hasPrefix("local_") && name.hasSuffix(".json") {
                    let path = orgDir.appendingPathComponent(name).path
                    guard isRegularFile(path) else { continue }
                    let stamp = fileStamp(path)
                    if let cached = sessionFiles[path], cached.stamp == stamp, !stamp.isEmpty {
                        found[cached.cli] = cached.session
                        fresh[path] = cached
                        continue
                    }
                    guard let fh = FileHandle(forReadingAtPath: path) else { continue }
                    let head = fh.readData(ofLength: 4096)
                    try? fh.close()
                    guard let text = String(data: head, encoding: .utf8) ?? String(data: head.prefix(3000), encoding: .utf8)
                    else { continue }
                    let range = NSRange(text.startIndex..., in: text)
                    guard let c = cliRe.firstMatch(in: text, range: range), let cr = Range(c.range(at: 1), in: text)
                    else { continue }
                    let title = titleRe.firstMatch(in: text, range: range)
                        .flatMap { Range($0.range(at: 1), in: text) }
                        .flatMap { try? JSONDecoder().decode(String.self, from: Data(text[$0].utf8)) }
                    let session = AppSession(title: title?.isEmpty == false ? title : nil,
                                             id: appSessionID(fromFileName: name))
                    found[String(text[cr])] = session
                    fresh[path] = (stamp, String(text[cr]), session)
                }
            }
        }
        titles = found
    }

    /// Claude's ⏱ line, from its first reply after the prompt: the transcript is read from the
    /// offset the hook saved, at most 512 KB per reload, until the line shows up (or 8 MB in).
    private func declaredLine(_ task: LiveTask) -> DeclaredLine? {
        guard let path = task.transcript, let offset = task.transcriptOffset, offset >= 0,
              isRegularFile(path) else { return nil }
        let key = "\(task.session ?? path)|\(task.startTs)"
        if let found = declaredFound[key] { return found }
        let step: UInt64 = 512 * 1024
        let start = UInt64(offset)  // sanitized: finite and below 1e11
        let limit = start + 16 * step
        let from = scannedUpTo[key] ?? start
        guard from < limit, let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        guard let end = try? fh.seekToEnd(), end > from else { return nil }
        try? fh.seek(toOffset: from)
        let want = min(min(end, limit) - from, step)
        let chunk = fh.readData(ofLength: Int(want))
        guard let cut = chunk.lastIndex(of: 0x0A) else {
            // Inside one very long line (a pasted image): skip it piece by piece. A line that is
            // still being written is read again at the next reload.
            if UInt64(chunk.count) == step { scannedUpTo[key] = from + step }
            return nil
        }
        let whole = chunk[chunk.startIndex...cut]
        scannedUpTo[key] = from + UInt64(whole.count)
        for line in whole.split(separator: 0x0A) {
            let data = Data(line)
            guard let text = String(data: data, encoding: .utf8),
                  text.contains("\"assistant\""), text.contains("⏱") || text.contains("\\u23f1"),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { continue }
            for block in content where block["type"] as? String == "text" {
                if let line = parseDeclaredLine(block["text"] as? String ?? "") {
                    declaredFound[key] = line
                    return line
                }
            }
        }
        return nil
    }

    /// Needs you first, then running, in the background, stopped (newest first), finished last
    /// (last finished first).
    var visible: [TaskItem] {
        if visibleCache.generation == generation { return visibleCache.items }
        let list = items.filter { $0.visible(at: now) && (showAutomated || !$0.automated) && !dismissed.contains($0.key) }
            .sorted { a, b in
                if a.state != b.state { return a.state.rawValue < b.state.rawValue }
                if a.state == .done { return (a.data.endTs ?? 0) > (b.data.endTs ?? 0) }
                return a.data.startTs > b.data.startTs
            }
        visibleCache = (generation, list)
        return list
    }

    var hiddenAutomated: Int {
        showAutomated ? 0 : items.filter { $0.visible(at: now) && $0.automated && !dismissed.contains($0.key) }.count
    }

    /// The visible tasks, one group per session, in the order of each session's first task.
    var groups: [TaskGroup] {
        var order: [String] = []
        var bySession: [String: [TaskItem]] = [:]
        for item in visible {
            let session = item.data.session ?? item.id
            if bySession[session] == nil { order.append(session) }
            bySession[session, default: []].append(item)
        }
        return order.map { TaskGroup(id: $0, items: bySession[$0] ?? []) }
    }

    /// The task the menu bar follows: the newest running one, else one with jobs in the background.
    var active: TaskItem? {
        let all = visible
        return all.first { $0.state == .running } ?? all.first { $0.state == .background }
    }

    /// Starts the short panel's blink, and ends it once over (so nothing animates after).
    func blink(waiting: Bool) {
        let f = Flash(waiting: waiting, start: Date().timeIntervalSince1970)
        flash = f
        DispatchQueue.main.asyncAfter(deadline: .now() + Flash.duration + 0.2) { [weak self] in
            if self?.flash == f { self?.flash = nil }
        }
    }

    /// A click on the dot (held: how long it was pressed): a jolt and a sound every time, rising with
    /// the run. In a run one dot flies off at the 8th click, 69 at the 69th, 101 and the cheer at the
    /// 101st, every run again. The 101st click in all (or of a run) opens the mini golf for good.
    func tapDot(held: Double = 0) {
        let now = Date().timeIntervalSince1970
        dotRun = now - lastDotTap <= TaskStore.runGap ? dotRun + 1 : 1
        lastDotTap = now
        dotClicks = min(dotClicks + 1, 999_999)
        dotSession += 1
        if dotRun > dotBestRun { dotBestRun = dotRun }
        DotSound.shared.click(count: dotRun, held: held)
        var count: Int?
        if dotRun == 8 { count = 1 }
        if dotRun == 69 { count = 69 }
        if !golfUnlocked && dotClicks >= TaskStore.golfClicks {
            unlockGolf(by: "clic")
            return
        } else if dotRun == TaskStore.golfClicks {
            HoleCheer.cheer(level: 1)
            count = 101
        } else if count != nil {
            NSSound(named: count == 69 ? "Hero" : "Pop")?.play()
        }
        guard let count else { return }
        let burst = DotBurst(count: count, start: Date().timeIntervalSince1970)
        dotBurst = burst
        DispatchQueue.main.asyncAfter(deadline: .now() + burst.duration + 0.3) { [weak self] in
            if self?.dotBurst == burst { self?.dotBurst = nil }
        }
    }

    /// The mini golf opens for good: 101 dots and the cheer. By "clic" (the 101st) or "tasti" (the dot
    /// dragged while holding ⌘, M and G).
    func unlockGolf(by way: String) {
        guard !golfUnlocked else { return }
        golfUnlocked = true
        if !demo { UserDefaults.standard.set(way, forKey: "golfUnlockedBy") }
        HoleCheer.cheer(level: 1)
        let burst = DotBurst(count: 101, start: Date().timeIntervalSince1970)
        dotBurst = burst
        DispatchQueue.main.asyncAfter(deadline: .now() + burst.duration + 0.3) { [weak self] in
            if self?.dotBurst == burst { self?.dotBurst = nil }
        }
    }

    /// The Claude app's session for a CLI session id, as last read from the app's files.
    func appSession(forCLI cli: String) -> AppSession? { titles[cli] }

    /// A still copy of the list, with the same rows and the same size, that never updates.
    func frozenCopy() -> TaskStore {
        let copy = TaskStore(demoItems: items, now: now)
        copy.showAutomated = showAutomated
        copy.hidePrompts = hidePrompts
        copy.expanded = expanded
        copy.pageLimit = pageLimit
        copy.dismissed = dismissed
        copy.compact = compact
        return copy
    }

    /// Starts the celebration of the tasks that have just finished, ends those that are over.
    private func updateCelebrations(_ items: [TaskItem], now: Double) {
        var states: [String: TaskState] = [:]
        for item in items {
            let key = item.key
            let state = item.state
            states[key] = state
            if statesPrimed, state == .done, let before = lastStates[key], before != .done, before != .waiting {
                pendingCelebration[key] = pendingCelebration[key] ?? now
            }
            if statesPrimed, state == .waiting, let before = lastStates[key], before != .waiting,
               showAutomated || !item.automated {
                blink(waiting: true)
            }
            if state == .done, let since = pendingCelebration[key], now - since >= 1.5,
               let result = item.outcome(at: now) {
                pendingCelebration[key] = nil
                var outcome = result.outcome
                if GameMood.current == .miniera, let est = item.estimate, est > 0 {
                    outcome = Ore(real: est + result.delta, estimate: est, range: item.range).celebration(slow: result.delta > 0)
                }
                celebrations[key] = Celebration(outcome: outcome, start: Date().timeIntervalSince1970,
                                                delta: result.delta, estimate: item.estimate ?? 0, range: item.range)
                if showAutomated || !item.automated { blink(waiting: false) }
            }
        }
        pendingCelebration = pendingCelebration.filter { states[$0.key] == .done }
        let over = celebrations.filter { now - $0.value.start > Celebration.duration + 0.5 }
        if !over.isEmpty { celebrations = celebrations.filter { over[$0.key] == nil } }
        lastStates = states
        statesPrimed = true
    }

    /// Celebrates the first rows, one outcome each (tests only).
    func celebrateForDebug() {
        let start = Date().timeIntervalSince1970
        for (group, outcome) in zip(groups, Outcome.allCases) {
            let delta: Double = [Outcome.exact: 4, .faster: -100, .onTime: 40, .slower: 600][outcome] ?? 0
            celebrations[group.main.key] = Celebration(outcome: outcome, start: start, delta: delta, estimate: 120)
        }
    }

    /// Takes a finished section off the list: its finished and stopped tasks, not a new one.
    func dismiss(_ group: TaskGroup) {
        for item in group.items where item.state == .done || item.state == .stale {
            dismissed.insert(item.key)
        }
        expanded.remove(group.id)
        if !demo { UserDefaults.standard.set(Array(dismissed), forKey: "dismissed") }
    }

    var runningCount: Int { visible.filter { $0.state == .running || $0.state == .background }.count }
    var waitingCount: Int { visible.filter { $0.state == .waiting }.count }
    /// Finished in the last hour and still in the list: the menu bar's, the panel's and the iPhone's count.
    var doneCount: Int { visible.filter { $0.state == .done }.count }
}

/// A session of the Claude app: its sidebar title and its id for the chat link.
struct AppSession {
    var title: String?
    var id: String?
}

/// Claude's ⏱ line: the estimate, the likely range and the kind of work it declared.
struct DeclaredLine {
    var seconds: Double
    var range: (low: Double, high: Double)? = nil
    var kind: String? = nil
}

private let estimateRe = try? NSRegularExpression(
    pattern: #":[ \t]*(?:\*\*[ \t]*)?(?:~[ \t]*)?(\d{1,9}(?:[.,]\d{1,3})?)[ \t]*(hours?|h|ore|ora|minutes?|min|m|seconds?|sec|s)\b"#)
private let rangeRe = try? NSRegularExpression(
    pattern: #"(?:\blikely|\btra)[ \t]+~?(\d{1,9}(?:[.,]\d{1,3})?)[ \t]*(s|min|h|ore)?[ \t]+(?:to|e)[ \t]+~?(\d{1,9}(?:[.,]\d{1,3})?)[ \t]*(s|min|h|ore)\b"#)
/// The kinds' Italian names in older ⏱ lines and index entries (LEGACY_KINDS in task_eta.py).
let legacyKinds = ["veloce": "quick", "medio": "medium", "lungo": "long", "agenti": "agents"]

private let kindRe = try? NSRegularExpression(
    pattern: #"\b(quick|medium|long|veloce|medio|lungo|sub ?agents?)\b"#, options: [.caseInsensitive])

private func inSeconds(_ number: Substring, _ unit: Substring) -> Double? {
    guard let n = Double(number.replacingOccurrences(of: ",", with: ".")) else { return nil }
    switch unit {
    case "h", "hour", "hours", "ore", "ora": return n * 3600
    case "s", "sec", "second", "seconds": return n
    default: return n * 60
    }
}

/// Claude's "⏱ Estimated time with <model> <effort>: ~N min (likely X to Y min, <kind>)" line (older
/// versions: no kind, or in Italian "⏱ Tempo richiesto con ...: ~N min (probabile tra X e Y min,
/// medio)"). Only the first 300 characters of the line are looked at, with patterns that have no
/// adjacent open-ended repeats, so a hostile line stays fast. The range and the kind are read only
/// after the estimate: the effort "medium" before the colon is not the kind.
func parseDeclaredLine(_ text: String) -> DeclaredLine? {
    guard let estimateRe, let rangeRe, let kindRe else { return nil }
    for line in text.split(separator: "\n")
    where line.contains("⏱") && (line.contains("Estimated time") || line.contains("richiesto")) {
        let s = String(line.prefix(300))
        let all = NSRange(s.startIndex..., in: s)
        guard let m = estimateRe.firstMatch(in: s, range: all),
              let numberRange = Range(m.range(at: 1), in: s), let unitRange = Range(m.range(at: 2), in: s),
              let value = inSeconds(s[numberRange], s[unitRange]), value > 0, value <= 7 * 24 * 3600  // a week at most
        else { continue }
        var out = DeclaredLine(seconds: value)
        let after = m.range.location + m.range.length
        let rest = NSRange(location: after, length: all.length - after)
        if let r = rangeRe.firstMatch(in: s, range: rest),
           let lo = Range(r.range(at: 1), in: s), let hi = Range(r.range(at: 3), in: s),
           let hiUnit = Range(r.range(at: 4), in: s) {
            let loUnit = Range(r.range(at: 2), in: s).map { s[$0] } ?? s[hiUnit]
            if let low = inSeconds(s[lo], loUnit), let high = inSeconds(s[hi], s[hiUnit]),
               high > low, high <= 7 * 24 * 3600 {
                out.range = (low, high)
            }
        }
        if let k = kindRe.firstMatch(in: s, range: rest), let kr = Range(k.range(at: 1), in: s) {
            let word = s[kr].lowercased()
            out.kind = word.hasPrefix("sub") ? "agents" : (legacyKinds[word] ?? word)
        }
        return out
    }
    return nil
}

// MARK: - formatting

/// "45s", "2m10s", "65m12s"
func clock(_ seconds: Double) -> String {
    let s = max(0, safeInt(seconds.rounded(.toNearestOrEven)))
    if s < 60 { return "\(s)s" }
    return String(format: "%dm%02ds", s / 60, s % 60) // minutes only, never hours: "102m05s"
}

/// Estimates are always in whole minutes, never seconds or hours: "~1 min",
/// "~40 min", "~102 min".
func approxEstimate(_ seconds: Double) -> String {
    "~\(max(1, safeInt((seconds / 60).rounded(.toNearestOrEven)))) min"
}

/// The likely range in whole minutes, widened outwards: "17-102 min", "1-2 min".
func minuteRange(_ low: Double, _ high: Double) -> String {
    let lo = max(1, safeInt((low / 60).rounded(.down)))
    let hi = max(lo, safeInt((high / 60).rounded(.up)))
    return lo == hi ? "\(lo) min" : "\(lo)-\(hi) min"
}

/// How far past the estimate: "+45s", "+10 min".
func overText(_ seconds: Double) -> String {
    seconds < 60 ? "+\(clock(seconds))" : "+\(max(1, safeInt((seconds / 60).rounded()))) min"
}

/// How many times the estimate: "×2,5", "×6".
func timesText(_ ratio: Double) -> String {
    let r = (ratio * 10).rounded() / 10
    if r >= 10 || r == r.rounded() { return "×\(safeInt(r.rounded()))" }
    return "×" + Loc.decimal(r)
}

extension TaskItem {
    /// The overrun in words: "+40s oltre la stima", "+10 min oltre la stima (×6)"; short: "+10 min (×6)".
    func overrunText(at now: Double, short: Bool = false) -> String? {
        guard let o = overrun(at: now) else { return nil }
        let times = o.ratio >= 2 ? " (\(timesText(o.ratio)))" : ""
        return short ? overText(o.seconds) + times
            : L("\(overText(o.seconds)) over the estimate\(times)", "\(overText(o.seconds)) oltre la stima\(times)")
    }

    var estimateText: String? {
        if let m = data.estimateMin, m > 0 { return approxEstimate(m * 60) }
        if let d = declared, d > 0 { return approxEstimate(d) }
        return data.estimateS.map(approxEstimate)
    }

    var rangeText: String? {
        guard let r = range else { return nil }
        return minuteRange(r.low, r.high)
    }

    var modelText: String {
        let model = (data.model ?? "?") + (data.modelKnown == false ? "?" : "")
        return [model, data.effort].compactMap { $0 }.joined(separator: " ")
    }

    var folderText: String { (data.cwd?.isEmpty == false ? data.cwd : nil) ?? "?" }

    /// The row's name: the session title from the app sidebar, else the prompt.
    var name: String { title ?? data.prompt ?? "…" }

    /// The row's name as shown: with prompts hidden, only the folder.
    func shownName(hidePrompts: Bool) -> String { hidePrompts ? "Task in \(folderText)" : name }

    /// What the session waits for, in words.
    var waitingText: String { waitingText(hidePrompts: false) }

    func waitingText(hidePrompts: Bool) -> String {
        let detail = hidePrompts ? "" : input?.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let what: String
        switch input?.kind {
        case "question", "domanda": what = L("has a question for you", "ha una domanda per te")
        case "plan", "piano": what = L("plan to approve", "piano da approvare")
        case "choice", "scelta": what = L("pick where to run it", "scegli dove eseguirlo")
        case "permission", "permesso": what = L("permission needed", "serve un permesso")
        case "reply", "risposta": what = L("asked you something", "ti ha chiesto qualcosa")
        default: what = L("waiting for your reply", "aspetta la tua risposta")
        }
        return detail.isEmpty ? what : "\(what): \(detail)"
    }
}

/// The bar's time scale: room for the elapsed time, the likely range and the estimate.
func barScale(elapsed: Double, estimate: Double?, high: Double?) -> Double {
    let scale = max(elapsed * 1.05, (high ?? 0) * 1.15, (estimate ?? 0) * 1.3, 30)
    return scale.isFinite ? min(scale, 1e10) : 30
}
