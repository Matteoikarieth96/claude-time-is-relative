import Foundation

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
        return t
    }
}

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
/// The menu bar counts the tasks finished within this window.
let doneRecentlyWindow: Double = 30 * 60

struct TaskItem: Identifiable {
    let id: String
    let data: LiveTask
    let quiet: Double?             // seconds since the transcript last changed (open tasks only)
    var input: InputMarker? = nil  // the session waits for you
    var declared: Double? = nil    // Claude's ⏱ estimate, read from the transcript, seconds
    var title: String? = nil       // the session's title in the Claude app sidebar

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
            return upTo(input?.ts ?? now)
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

    /// The likely range, moved along when Claude wrote a different estimate than the hook's.
    var range: (low: Double, high: Double)? {
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

    /// Headless `claude -p` runs (benchmarks, scripts), hidden unless the user asks for them.
    /// Older live files have no entrypoint: a session in a temporary folder counts as one.
    var automated: Bool {
        if let e = data.entrypoint { return e == "sdk-cli" }
        let t = data.transcript ?? ""
        return t.contains("/-private-tmp-") || t.contains("/-tmp-")
    }
}

/// Reads the live folder every 2 seconds and ticks the clock every second. Besides the small
/// live files it reads only the start of each running task's reply, once, for Claude's ⏱ line.
final class TaskStore: ObservableObject {
    @Published private(set) var items: [TaskItem] = []
    @Published private(set) var now = Date().timeIntervalSince1970
    /// How many tasks the list shows: 5, then 5 more per click on "5 more".
    @Published var pageLimit = 5
    @Published var showAutomated: Bool {
        didSet { UserDefaults.standard.set(showAutomated, forKey: "showAutomated") }
    }

    static let pageSize = 5

    let dir: URL
    private var timer: Timer?
    private var ticks = 0
    private let demo: Bool
    private var declaredFound: [String: Double] = [:]  // task key -> Claude's estimate, seconds
    private var scannedUpTo: [String: UInt64] = [:]    // task key -> transcript bytes already read
    private var titles: [String: String] = [:]         // CLI session id -> title in the app sidebar
    private var titlesReadAt: Double = 0

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

    init(dir: URL = TaskStore.defaultDir) {
        self.dir = dir
        self.demo = false
        self.showAutomated = UserDefaults.standard.bool(forKey: "showAutomated")
    }

    init(demoItems: [TaskItem], now: Double) {
        self.dir = TaskStore.defaultDir
        self.demo = true
        self.showAutomated = false
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

    private func tick() {
        ticks += 1
        if ticks % 2 == 0 { reload() }
        now = Date().timeIntervalSince1970
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
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let url = dir.appendingPathComponent(name)
            guard isRegularFile(url.path), let raw = try? Data(contentsOf: url),
                  let decoded = try? decoder.decode(LiveTask.self, from: raw),
                  let task = decoded.sanitized() else { continue }
            var quiet: Double?
            if task.status != "done" {
                if let path = task.transcript,
                   let attrs = try? fm.attributesOfItem(atPath: path),
                   let modified = attrs[.modificationDate] as? Date {
                    quiet = now - modified.timeIntervalSince1970
                } else if now - task.startTs > 3 * 3600 {
                    quiet = now - task.startTs // no transcript to look at: give up after 3 hours
                }
            }
            var item = TaskItem(id: name, data: task, quiet: quiet)
            item.title = task.session.flatMap { titles[$0] }
            // The marker belongs to the session's current task, <session>.json.
            let marker = task.session.map { dir.appendingPathComponent("\($0).input") }
            if let session = task.session, name == "\(session).json", let marker, isRegularFile(marker.path),
               let raw = try? Data(contentsOf: marker) {
                item.input = (try? decoder.decode(InputMarker.self, from: raw)) ?? InputMarker()
            }
            if task.estimateMin == nil, task.status != "done" {
                item.declared = declaredEstimate(task)
            }
            out.append(item)
        }
        items = out
    }

    private func readTitles() {
        let fm = FileManager.default
        guard let accounts = try? fm.contentsOfDirectory(atPath: TaskStore.appSessionsDir.path) else { return }
        guard let cliRe = try? NSRegularExpression(pattern: #""cliSessionId"\s*:\s*"([^"]+)""#),
              let titleRe = try? NSRegularExpression(pattern: #""title"\s*:\s*("(?:[^"\\]|\\.)*")"#)
        else { return }
        var found: [String: String] = [:]
        for account in accounts {
            let accountDir = TaskStore.appSessionsDir.appendingPathComponent(account)
            for org in (try? fm.contentsOfDirectory(atPath: accountDir.path)) ?? [] {
                let orgDir = accountDir.appendingPathComponent(org)
                for name in (try? fm.contentsOfDirectory(atPath: orgDir.path)) ?? []
                where name.hasPrefix("local_") && name.hasSuffix(".json") {
                    let path = orgDir.appendingPathComponent(name).path
                    guard isRegularFile(path), let fh = FileHandle(forReadingAtPath: path) else { continue }
                    let head = fh.readData(ofLength: 4096)
                    try? fh.close()
                    guard let text = String(data: head, encoding: .utf8) ?? String(data: head.prefix(3000), encoding: .utf8)
                    else { continue }
                    let range = NSRange(text.startIndex..., in: text)
                    guard let c = cliRe.firstMatch(in: text, range: range), let cr = Range(c.range(at: 1), in: text),
                          let t = titleRe.firstMatch(in: text, range: range), let tr = Range(t.range(at: 1), in: text),
                          let title = try? JSONDecoder().decode(String.self, from: Data(text[tr].utf8)),
                          !title.isEmpty else { continue }
                    found[String(text[cr])] = title
                }
            }
        }
        titles = found
    }

    /// Claude's ⏱ line, from its first reply after the prompt: the transcript is read from the
    /// offset the hook saved, at most 512 KB per reload, until the line shows up (or 8 MB in).
    private func declaredEstimate(_ task: LiveTask) -> Double? {
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
                if let seconds = parseDeclaredEstimate(block["text"] as? String ?? "") {
                    declaredFound[key] = seconds
                    return seconds
                }
            }
        }
        return nil
    }

    /// Needs you first, then running, in the background, stopped (newest first), finished last
    /// (last finished first).
    var visible: [TaskItem] {
        items.filter { $0.visible(at: now) && (showAutomated || !$0.automated) }
            .sorted { a, b in
                if a.state != b.state { return a.state.rawValue < b.state.rawValue }
                if a.state == .done { return (a.data.endTs ?? 0) > (b.data.endTs ?? 0) }
                return a.data.startTs > b.data.startTs
            }
    }

    var hiddenAutomated: Int {
        showAutomated ? 0 : items.filter { $0.visible(at: now) && $0.automated }.count
    }

    var runningCount: Int { visible.filter { $0.state == .running || $0.state == .background }.count }
    var waitingCount: Int { visible.filter { $0.state == .waiting }.count }
    /// For the menu bar: tasks finished in the last 30 minutes (Claude's turn over, no jobs left
    /// in the background), including those that end by asking you something. Automated runs
    /// count only when they are shown.
    var doneRecentlyCount: Int {
        items.filter { $0.data.status == "done" && now - ($0.data.endTs ?? 0) < doneRecentlyWindow
            && (showAutomated || !$0.automated) }.count
    }
}

/// Seconds from Claude's "⏱ Estimated time with <model> <effort>: ~N min" line (older versions
/// wrote "⏱ Tempo richiesto con ..."). Only the first 300 characters of the line are looked at,
/// with a pattern that has no adjacent open-ended repeats, so a hostile line stays fast.
func parseDeclaredEstimate(_ text: String) -> Double? {
    guard let re = try? NSRegularExpression(
        pattern: #":[ \t]*(?:\*\*[ \t]*)?(?:~[ \t]*)?(\d{1,9}(?:[.,]\d{1,3})?)[ \t]*(hours?|h|ore|ora|minutes?|min|m|seconds?|sec|s)\b"#)
    else { return nil }
    for line in text.split(separator: "\n")
    where line.contains("⏱") && (line.contains("Estimated time") || line.contains("richiesto")) {
        let s = String(line.prefix(300))
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let numberRange = Range(m.range(at: 1), in: s), let unitRange = Range(m.range(at: 2), in: s),
              let n = Double(s[numberRange].replacingOccurrences(of: ",", with: ".")) else { continue }
        let seconds: Double
        switch s[unitRange] {
        case "h", "hour", "hours", "ore", "ora": seconds = n * 3600
        case "s", "sec", "second", "seconds": seconds = n
        default: seconds = n * 60
        }
        return seconds > 0 && seconds <= 7 * 24 * 3600 ? seconds : nil  // a week at most
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

extension TaskItem {
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

    /// What the session waits for, in words.
    var waitingText: String {
        let detail = input?.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let what: String
        switch input?.kind {
        case "question", "domanda": what = "question for you"
        case "plan", "piano": what = "plan to approve"
        case "choice", "scelta": what = "pick where to run it"
        case "permission", "permesso": what = "permission needed"
        case "reply", "risposta": what = "asked you something"
        default: what = "waiting for your reply"
        }
        return detail.isEmpty ? what : "\(what): \(detail)"
    }
}

/// The bar's time scale: room for the elapsed time, the likely range and the estimate.
func barScale(elapsed: Double, estimate: Double?, high: Double?) -> Double {
    let scale = max(elapsed * 1.05, (high ?? 0) * 1.15, (estimate ?? 0) * 1.3, 30)
    return scale.isFinite ? min(scale, 1e10) : 30
}
