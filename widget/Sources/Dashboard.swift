import AppKit
import Charts
import SwiftUI

// The dashboard: a window with the history of task-eta's index (every finished task, with its real
// time, Claude's estimate, the model and the project). It reads the index only while it is open.

/// A finished task from the index.
struct PastTask: Identifiable {
    let id: String
    let start: Double
    let real: Double          // seconds
    let estimate: Double?     // Claude's ⏱ estimate, seconds
    let range: (low: Double, high: Double)?
    let model: String
    let project: String
    let prompt: String
    let session: String?
    /// The kind of work in Claude's ⏱ line: quick, medium, long or agents.
    var kind: String? = nil
    /// For the useless statistics: Claude's working seconds, the seconds it waited for you, its
    /// tools and the files it changed (by extension), the subagents, and whether you stopped it.
    var active: Double = 0
    var wait: Double = 0
    var toolNames: [String: Int] = [:]
    var editExts: [String: Int] = [:]
    var agents = 0
    var interrupted = false
    /// For the game's clean shot: the times the task stopped and started again, and its tool calls.
    var segments = 1
    var tools = 0

    var outcome: Outcome? { estimate.map { outcomeOf(real: real, estimate: $0, range: range) } }

    /// The tasks of an index.json (written by task_eta.py), headless runs left out.
    static func load(from url: URL) -> [PastTask] {
        guard isRegularFile(url.path), let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tasks = root["tasks"] as? [String: Any] else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // The index keeps the folder's name ("my-app"); the home folder is "Home" whatever its
        // form: the full path, its name, or the name Claude Code gives its project folder.
        let homeNames: Set<String> = [home, URL(fileURLWithPath: home).lastPathComponent,
                                      home.replacingOccurrences(of: "/", with: "-")]
        var out: [PastTask] = []
        out.reserveCapacity(tasks.count)
        for (key, value) in tasks {
            guard let t = value as? [String: Any], (t["headless"] as? Bool) != true,
                  let real = sane((t["dur_s"] as? NSNumber)?.doubleValue), real > 0,
                  let start = sane((t["start_ts"] as? NSNumber)?.doubleValue), start > 0 else { continue }
            let est = sane((t["estimate_min"] as? NSNumber)?.doubleValue).flatMap { $0 > 0 ? $0 * 60 : nil }
            var range: (low: Double, high: Double)?
            if let r = t["est_range"] as? [NSNumber], r.count == 2,
               let lo = sane(r[0].doubleValue), let hi = sane(r[1].doubleValue), hi > lo, lo >= 0 {
                range = (lo, hi)
            }
            let cwd = (t["cwd"] as? String) ?? ""
            let project = cwd.isEmpty ? "?" : homeNames.contains(cwd) ? "Home"
                : cwd.contains("/") ? URL(fileURLWithPath: cwd).lastPathComponent : cwd
            let model = [t["model"] as? String, t["effort"] as? String].compactMap { $0 }.joined(separator: " ")
            let prompt = ((t["prompt"] as? String) ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            out.append(PastTask(id: key, start: start, real: real, estimate: est, range: range,
                                model: model.isEmpty ? "?" : model, project: project,
                                prompt: String(prompt.prefix(300)), session: t["session"] as? String,
                                kind: t["kind_declared"] as? String,
                                active: sane((t["active_s"] as? NSNumber)?.doubleValue).map { max(0, $0) } ?? real,
                                wait: sane((t["wait_s"] as? NSNumber)?.doubleValue).map { max(0, $0) } ?? 0,
                                toolNames: counts(t["tool_names"]), editExts: counts(t["edit_exts"]),
                                agents: (t["agents"] as? NSNumber)?.intValue ?? 0,
                                interrupted: (t["interrupted"] as? Bool) ?? false,
                                segments: (t["segments"] as? NSNumber)?.intValue ?? 1,
                                // the protocol's own calls (elapsed, eta, piccone) are not work
                                tools: max(0, ((t["tools"] as? NSNumber)?.intValue ?? 0) - ((t["proto"] as? NSNumber)?.intValue ?? 0))))
        }
        return out.sorted { $0.start > $1.start }
    }

    /// {"Bash": 21, "Read": 14}: names and counts, anything else left out.
    private static func counts(_ value: Any?) -> [String: Int] {
        guard let dict = value as? [String: Any] else { return [:] }
        var out: [String: Int] = [:]
        for (k, v) in dict { if let n = (v as? NSNumber)?.intValue, n > 0, !k.isEmpty { out[String(k.prefix(80))] = n } }
        return out
    }
}

enum DashRange: String, CaseIterable, Identifiable {
    case week, month, all
    var id: String { rawValue }
    var label: String { self == .week ? L("7 days", "7 giorni") : self == .month ? L("30 days", "30 giorni") : L("All", "Tutto") }
    /// Whole days, today included: "7 giorni" is today and the 6 before.
    var days: Int? { self == .week ? 7 : self == .month ? 30 : nil }
    /// The period before, for the comparisons: "+12% sui 7 giorni prima".
    var before: String? {
        self == .week ? L("previous 7 days", "7 giorni prima") : self == .month ? L("previous 30 days", "30 giorni prima") : nil
    }
}

/// Everything the dashboard shows for one period, worked out once.
struct DashStats {
    struct Day: Identifiable { let date: Date; let hours: Double; var id: Date { date } }
    struct Point: Identifiable { let id: String; let estimate: Double; let real: Double; let outcome: Outcome }
    /// How the estimates of a group went: how many, how many inside the range, and how long the
    /// work took against the estimate (the median of real ÷ estimate: 2 is twice as long).
    struct Accuracy: Identifiable {
        let name: String
        let count: Int
        let inside: Int
        let ratio: Double
        /// A kind of work: `name` is its key ("quick"), shown in words in the language of the moment.
        var isKind = false
        var id: String { name }
        var share: Double { count == 0 ? 0 : Double(inside) / Double(count) }
        /// What the tables write.
        var label: String { isKind ? DashStats.kindName(name) : name }
    }

    var count = 0
    var hours = 0.0
    var medianMinutes = 0.0
    var withEstimate = 0
    var inside = 0
    var outcomes: [Outcome: Int] = [:]
    var bestStreak = 0
    var currentStreak = 0
    var days: [Day] = []
    var projects: [(name: String, hours: Double)] = []
    var models: [(name: String, hours: Double)] = []
    var heat = Array(repeating: Array(repeating: 0, count: 24), count: 7)  // Monday first
    var points: [Point] = []
    /// Where the estimates miss: by kind of work, by model, by project.
    var byKind: [Accuracy] = []
    var accuracyByModel: [Accuracy] = []
    var accuracyByProject: [Accuracy] = []
    /// The outcomes of the latest estimates, newest first.
    var recent: [Outcome] = []

    /// The kinds of the ⏱ line in their order, with the words of the dashboard.
    static var kinds: [(key: String, name: String)] {
        [("quick", L("Quick (1-3)", "Rapido (1-3)")), ("medium", L("Medium (4-15)", "Medio (4-15)")),
         ("long", L("Long (16+)", "Lungo (16+)")), ("agents", L("With subagents", "Con subagenti"))]
    }
    /// A kind's words, or the key itself for a kind the dashboard does not know.
    static func kindName(_ key: String) -> String { kinds.first { $0.key == key }?.name ?? key }
    /// Every estimate together: the line each group is compared with.
    var overall: Accuracy {
        let ratios = points.map { $0.real / max($0.estimate, 1) }.sorted()
        let mid = ratios.count / 2
        let median = ratios.isEmpty ? 0 : ratios.count % 2 == 1 ? ratios[mid] : (ratios[mid - 1] + ratios[mid]) / 2
        return Accuracy(name: L("All estimates", "Tutte le stime"), count: withEstimate, inside: inside, ratio: median)
    }

    init() {}

    init(_ tasks: [PastTask]) {
        count = tasks.count
        hours = tasks.reduce(0) { $0 + $1.real } / 3600
        let reals = tasks.map(\.real).sorted()
        if !reals.isEmpty {
            let mid = reals.count / 2
            medianMinutes = (reals.count % 2 == 1 ? reals[mid] : (reals[mid - 1] + reals[mid]) / 2) / 60
        }
        let calendar = Calendar.current
        var byDay: [Date: Double] = [:]
        var byProject: [String: Double] = [:]
        var byModel: [String: Double] = [:]
        for t in tasks {
            let date = Date(timeIntervalSince1970: t.start)
            byDay[calendar.startOfDay(for: date), default: 0] += t.real / 3600
            byProject[t.project, default: 0] += t.real / 3600
            byModel[t.model, default: 0] += t.real / 3600
            let weekday = (calendar.component(.weekday, from: date) + 5) % 7  // Sunday 1 -> 6, Monday 2 -> 0
            heat[weekday][calendar.component(.hour, from: date)] += 1
            if let est = t.estimate, let o = t.outcome {
                withEstimate += 1
                outcomes[o, default: 0] += 1
                if o == .exact || o == .onTime { inside += 1 }
                points.append(Point(id: t.id, estimate: est, real: t.real, outcome: o))
            }
        }
        days = byDay.map { Day(date: $0.key, hours: $0.value) }.sorted { $0.date < $1.date }
        projects = byProject.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
        models = byModel.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
        var run = 0
        for t in tasks.reversed() { // oldest first
            guard let o = t.outcome else { continue }
            run = (o == .exact || o == .onTime) ? run + 1 : 0
            bestStreak = max(bestStreak, run)
        }
        currentStreak = run
        recent = Array(tasks.compactMap(\.outcome).prefix(24))
        let kindOrder = DashStats.kinds.map(\.key)
        byKind = DashStats.accuracy(tasks, minCount: 1) { $0.kind }
            .sorted { (kindOrder.firstIndex(of: $0.name) ?? 9) < (kindOrder.firstIndex(of: $1.name) ?? 9) }
            .map { a in Accuracy(name: a.name, count: a.count, inside: a.inside, ratio: a.ratio, isKind: true) }
        accuracyByModel = DashStats.accuracy(tasks, minCount: 3) { $0.model }
        accuracyByProject = DashStats.accuracy(tasks, minCount: 3) { $0.project }
    }

    /// The groups with at least `minCount` estimates, the biggest first.
    private static func accuracy(_ tasks: [PastTask], minCount: Int, by key: (PastTask) -> String?) -> [Accuracy] {
        var groups: [String: (inside: Int, ratios: [Double])] = [:]
        for t in tasks {
            guard let est = t.estimate, est > 0, let o = t.outcome, let k = key(t) else { continue }
            var g = groups[k] ?? (0, [])
            g.ratios.append(t.real / est)
            if o == .exact || o == .onTime { g.inside += 1 }
            groups[k] = g
        }
        return groups.filter { $0.value.ratios.count >= minCount }
            .map { k, g in
                let r = g.ratios.sorted(), mid = r.count / 2
                return Accuracy(name: k, count: r.count, inside: g.inside,
                                ratio: r.count % 2 == 1 ? r[mid] : (r[mid - 1] + r[mid]) / 2)
            }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}

/// Today against yesterday, whatever the period picked.
struct DayFigures {
    var hours = 0.0
    var count = 0
    var yesterdayHours = 0.0
    /// Hours of the tasks started in each hour of today.
    var hourly = Array(repeating: 0.0, count: 24)

    init() {}

    init(_ tasks: [PastTask], now: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now).timeIntervalSince1970
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))?.timeIntervalSince1970 ?? today - 86400
        for t in tasks where t.start >= yesterday {
            if t.start >= today {
                hours += t.real / 3600
                count += 1
                hourly[calendar.component(.hour, from: Date(timeIntervalSince1970: t.start))] += t.real / 3600
            } else {
                yesterdayHours += t.real / 3600
            }
        }
    }
}

final class DashboardModel: ObservableObject {
    @Published private(set) var all: [PastTask] = []
    @Published private(set) var stats = DashStats()
    /// The period of the same length just before (nil for "Tutto"): the figures compare with it.
    @Published private(set) var previous: DashStats?
    @Published private(set) var today = DayFigures()
    @Published private(set) var loading = false
    /// The period, remembered; the first time the last 7 days, where every figure has the week
    /// before to compare with.
    @Published var range: DashRange = DashboardModel.savedRange {
        didSet {
            if !DashDebug.snapshot { UserDefaults.standard.set(range.rawValue, forKey: "dashboardRange") }
            recompute()
        }
    }
    @Published var query = ""
    /// From the mine (Miniera.swift): the History shows only the tasks of one find, in one week or ever.
    struct MineFilter: Equatable {
        let ore: Ore
        let week: Date?
    }
    @Published var mineFilter: MineFilter?
    /// A widget to scroll to: the History, when a find is clicked.
    @Published var jump: DashWidget?
    /// Rows of the history at most: the newest; a search finds the others.
    var historyLimit = 200
    let indexURL: URL
    let chatLink: (String) -> URL?

    /// TASKETA_DEBUG_DASH can pick it for a snapshot: week, month, everything.
    private static var savedRange: DashRange {
        let flags = DashDebug.flags
        if flags.contains("week") { return .week }
        if flags.contains("month") { return .month }
        if flags.contains("everything") { return .all }
        return UserDefaults.standard.string(forKey: "dashboardRange").flatMap(DashRange.init(rawValue:)) ?? .week
    }

    init(indexURL: URL, chatLink: @escaping (String) -> URL?) {
        self.indexURL = indexURL
        self.chatLink = chatLink
    }

    /// The index is read away from the main thread: 1-2 MB of JSON.
    func reload() {
        loading = true
        let url = indexURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tasks = PastTask.load(from: url)
            DispatchQueue.main.async {
                self?.all = tasks
                self?.loading = false
                self?.recompute()
            }
        }
    }

    /// The same, on the calling thread (snapshots and tests).
    func loadNow() {
        all = PastTask.load(from: indexURL)
        recompute()
    }

    /// Frees the history when the window closes.
    func drop() {
        all = []
        stats = DashStats()
        previous = nil
        today = DayFigures()
    }

    var inRange: [PastTask] {
        guard range.days != nil else { return all }
        let from = periodStart.timeIntervalSince1970
        return all.filter { $0.start >= from }
    }

    var history: [PastTask] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var base = inRange
        if let f = mineFilter {
            // Any period: a find of last month is in the History too.
            let cal = MineStats.calendar
            base = all.filter { t in
                guard let est = t.estimate, est > 0, Ore(real: t.real, estimate: est, range: t.range) == f.ore else { return false }
                guard let week = f.week else { return true }
                return cal.dateInterval(of: .weekOfYear, for: Date(timeIntervalSince1970: t.start + t.real))?.start == week
            }
        }
        let list = q.isEmpty ? base : base.filter { $0.prompt.lowercased().contains(q) || $0.project.lowercased().contains(q) }
        return Array(list.prefix(historyLimit))
    }

    /// The projects of the whole history, most hours first: the ones to give a logo to.
    var projectNames: [String] {
        var hours: [String: Double] = [:]
        for t in all { hours[t.project, default: 0] += t.real }
        return hours.sorted { $0.value > $1.value }.prefix(14).map(\.key)
    }

    /// The first day of the period: the start of the charts' axis.
    var periodStart: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if let days = range.days { return calendar.date(byAdding: .day, value: 1 - days, to: today) ?? today }
        return calendar.startOfDay(for: Date(timeIntervalSince1970: all.last?.start ?? Date().timeIntervalSince1970))
    }

    /// The period in words, for the widgets' subtitles.
    var periodText: String {
        switch range {
        case .week: return L("last 7 days", "ultimi 7 giorni")
        case .month: return L("last 30 days", "ultimi 30 giorni")
        case .all:
            let from = periodStart.formatted(.dateTime.day().month(.wide).locale(Loc.locale))
            return L("since \(from)", "dal " + from)
        }
    }

    private func recompute() {
        stats = DashStats(inRange)
        today = DayFigures(all)
        if let days = range.days {
            let end = periodStart
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            previous = DashStats(all.filter { $0.start >= start.timeIntervalSince1970 && $0.start < end.timeIntervalSince1970 })
        } else {
            previous = nil
        }
    }
}

// MARK: - the view

/// "2.5" or "2,5", in the language of the moment.
func decimal(_ value: Double, _ digits: Int = 1) -> String {
    Loc.decimal(value, digits: digits)
}

/// "+12% sui 7 giorni prima": the change against the period before; nil with nothing to compare.
func changeText(_ now: Double, _ before: Double, _ label: String) -> String? {
    guard before > 0, now.isFinite, before.isFinite else { return nil }
    let ratio = now / before
    if ratio >= 2 { return L("×\(decimal(ratio)) vs the \(label)", "×\(decimal(ratio)) sui \(label)") }
    let pct = safeInt(((ratio - 1) * 100).rounded())
    let sign = pct > 0 ? "+" : "−"
    return pct == 0 ? L("same as the \(label)", "come nei \(label)")
        : L("\(sign)\(abs(pct))% vs the \(label)", "\(sign)\(abs(pct))% sui \(label)")
}

/// "45s", "3m", "1h" for the log axes.
private func axisTime(_ s: Double) -> String {
    s < 60 ? "\(safeInt(s))s" : s < 3600 ? "\(safeInt(s / 60))m" : "\(safeInt(s / 3600))h"
}

private extension Outcome {
    var symbol: BasicChartSymbolShape {
        switch self {
        case .exact: return .triangle
        case .faster: return .square
        case .onTime: return .circle
        case .slower: return .diamond
        }
    }
}

extension Outcome {
    /// The outcome in plain words: what the dashboard writes, so a figure reads without a key.
    var name: String {
        switch self {
        case .exact: return L("Spot on", "Stima centrata")
        case .faster: return L("Faster", "Più veloce")
        case .onTime: return L("In range", "Nella forchetta")
        case .slower: return L("Over", "Sforata")
        }
    }
    /// The sticker's words without the emoji ("This is fine"): only a small aside now.
    var meme: String { String(stamp.dropFirst(2)) }
    /// The order of the dashboard: from the bullseye to the overrun.
    static let dashOrder: [Outcome] = [.exact, .faster, .onTime, .slower]
}

struct DashboardView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                DashboardContent(model: model, scroll: proxy).padding(20)
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .followsLanguage()
    }
}

/// The dashboard without its scroll view (the snapshot draws this).
struct DashboardContent: View {
    @ObservedObject var model: DashboardModel
    /// The window's scroll view: a widget brought back from "Aggiungi" is scrolled into view.
    var scroll: ScrollViewProxy?
    @StateObject private var grid = DashGridModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if model.loading && model.all.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else if model.stats.count == 0 {
                Text(L("No tasks in this period: Claude took a holiday. Try a longer period.",
                       "Nessun task in questo periodo: Claude si è preso una vacanza. Prova un periodo più lungo."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                DashboardGrid(model: model, grid: grid)
                if DashDebug.flags.contains("editors") {
                    HStack(alignment: .top, spacing: 14) {
                        FunStatsEditor().background(RoundedRectangle(cornerRadius: 12).fill(DashColor.plate))
                        ProjectLogosEditor(projects: Array(model.projectNames.prefix(6)))
                            .background(RoundedRectangle(cornerRadius: 12).fill(DashColor.plate))
                    }
                }
                if DashDebug.flags.contains("cards") {
                    // The game's cards whole, as they scroll inside their widgets.
                    if GameMood.current == .miniera {
                        MinieraCard(stats: MineStats(model.all), gems: GemStats(model.all)).fixedSize(horizontal: false, vertical: true)
                    } else {
                        CampoPlate(title: GameMood.current.cardTitle) { GemsCard(stats: GemStats(model.all)) }
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    MinigolfPlate(store: DashboardController.shared.store, played: model.all.filter { $0.estimate != nil }.count)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: model.jump) { _, widget in
            guard let widget else { return }
            model.jump = nil
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.35)) { scroll?.scrollTo(widget, anchor: .top) }
            }
        }
        .onChange(of: grid.added) { _, widget in
            guard let widget else { return }
            grid.added = nil
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.35)) { scroll?.scrollTo(widget, anchor: .center) }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L("Task analytics", "Analytics dei task")).font(.system(size: 24, weight: .bold))
                    Text("Gaming Mode").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                Text(grid.editing ? L("Drag a widget onto another to move it. Top right sets its size, top left hides it.",
                                      "Trascina un widget su un altro per spostarlo. In alto a destra la dimensione, a sinistra lo nascondi.")
                     : periodLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if grid.editing {
                Menu {
                    ForEach(grid.hidden, id: \.widget) { entry in
                        Button(entry.widget.title) { grid.show(entry.widget) }
                    }
                } label: {
                    Label(L("Add", "Aggiungi"), systemImage: "plus")
                }
                .fixedSize()
                .disabled(grid.hidden.isEmpty)
                .help(grid.hidden.isEmpty ? L("Every widget is already on the dashboard", "Tutti i widget sono già nella dashboard")
                      : L("Bring back a hidden widget", "Rimetti un widget nascosto"))
                Button(L("Reset", "Ripristina")) { grid.reset() }
                    .disabled(grid.isStandard)
                    .help(L("Back to the original layout", "Torna alla disposizione iniziale"))
                Button(L("Done", "Fine")) { grid.editing = false }
                    .keyboardShortcut("e")
                    .buttonStyle(.borderedProminent)
                    .help(L("Done editing (⌘E)", "Fine delle modifiche (⌘E)"))
                Button("") { grid.editing = false }
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            } else {
                Picker(L("Period", "Periodo"), selection: $model.range) {
                    ForEach(DashRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help(L("Reload the index (⌘R)", "Rileggi l'indice (⌘R)"))
                    .keyboardShortcut("r")
                    .dwellClick { model.reload() }
                Button { SettingsController.shared.show() } label: { Image(systemName: "gearshape") }
                    .help(L("Settings (⌘,)", "Impostazioni (⌘,)"))
                    .dwellClick { SettingsController.shared.show() }
                Button(L("Edit", "Modifica")) { grid.editing = true }
                    .keyboardShortcut("e")
                    .help(L("Move, resize, hide and add widgets (⌘E)", "Sposta, ridimensiona, nascondi e aggiungi i widget (⌘E)"))
            }
            // ⌘1, ⌘2, ⌘3: the periods, from the keyboard.
            ForEach(Array(DashRange.allCases.enumerated()), id: \.offset) { i, range in
                Button("") { model.range = range }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The period in full under the title: what every figure below counts.
    private var periodLine: String {
        let from = model.periodStart.formatted(.dateTime.day().month(.wide).locale(Loc.locale))
        switch model.range {
        case .week: return L("Last 7 days, from \(from) to today", "Ultimi 7 giorni, dal \(from) a oggi")
        case .month: return L("Last 30 days, from \(from) to today", "Ultimi 30 giorni, dal \(from) a oggi")
        case .all: return L("Full history, from \(from) to today", "Tutto lo storico, dal \(from) a oggi")
        }
    }
}

// MARK: - figures (1×1 and 2×1)

/// The hours of each day from the start of the period to today, zeros included: a sparkline.
private func dailySeries(_ days: [DashStats.Day], from start: Date) -> [Double] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let count = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: today).day ?? 0) + 1)
    var out = Array(repeating: 0.0, count: min(count, 400))
    for day in days {
        let i = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: day.date).day ?? -1
        if i >= 0 && i < out.count { out[i] = day.hours }
    }
    return out
}

private func barsWidth(_ size: WidgetSize) -> CGFloat { size.width > 1 ? 230 : 96 }

struct TodayWidget: View {
    @ObservedObject var model: DashboardModel
    let size: WidgetSize

    var body: some View {
        let t = model.today
        let yesterday = decimal(t.yesterdayHours)
        WidgetChrome(role: .figure, title: L("Today", "Oggi")) {
            FigureView(number: t.hours, format: { decimal($0) }, unit: "h",
                       caption: Text(t.count == 0
                                     ? L("nothing yet: Claude is still stretching. Yesterday \(yesterday) h",
                                         "ancora niente: Claude si sta stiracchiando. Ieri \(yesterday) h")
                                     : L("\(t.count) task\(t.count == 1 ? "" : "s"), yesterday \(yesterday) h",
                                         "\(t.count) task, ieri \(yesterday) h"))) {
                MiniBars(values: t.hourly).frame(maxWidth: barsWidth(size))
                    .help(L("Hours of work by start hour, from midnight", "Ore di lavoro per ora di inizio, da mezzanotte"))
            }
        }
    }
}

struct HoursWidget: View {
    @ObservedObject var model: DashboardModel
    let size: WidgetSize

    var body: some View {
        let s = model.stats
        let change = model.range.before.flatMap { label in model.previous.flatMap { changeText(s.hours, $0.hours, label) } }
        WidgetChrome(role: .figure, title: L("Hours worked", "Ore di lavoro")) {
            FigureView(number: s.hours, format: { decimal($0) }, unit: "h",
                       caption: Text([model.periodText, change].compactMap { $0 }.joined(separator: ", "))) {
                MiniBars(values: dailySeries(s.days, from: model.periodStart)).frame(maxWidth: barsWidth(size))
                    .help(L("Hours per day in the period", "Ore al giorno nel periodo"))
            }
        }
    }
}

struct HitRateWidget: View {
    @ObservedObject var model: DashboardModel
    let size: WidgetSize

    var body: some View {
        let s = model.stats
        let pct = s.withEstimate == 0 ? nil : Double(s.inside) / Double(s.withEstimate) * 100
        let before = model.previous.flatMap { $0.withEstimate == 0 ? nil : Double($0.inside) / Double($0.withEstimate) * 100 }
        WidgetChrome(role: .figure, title: L("Estimates in range", "Stime nella forchetta")) {
            FigureView(number: pct ?? 0, format: { pct == nil ? "–" : "\(safeInt($0.rounded()))" }, unit: "%", caption: caption(pct, before)) {
                MiniBars(values: Outcome.dashOrder.map { Double(s.outcomes[$0] ?? 0) },
                         colors: Outcome.dashOrder.map { $0.palette[0] })
                    .frame(maxWidth: size.width > 1 ? 120 : 52)
                    .help(Outcome.dashOrder.map { "\($0.name): \(s.outcomes[$0] ?? 0)" }.joined(separator: "\n"))
            }
        }
    }

    /// "95 su 153 stime", and the change in points against the period before, green or orange.
    private func caption(_ pct: Double?, _ before: Double?) -> Text {
        let s = model.stats
        let inside = Loc.integer(s.inside), all = Loc.integer(s.withEstimate) // grouped, as Text("…") did
        let base = Text(L("\(inside) of \(all) estimates", "\(inside) su \(all) stime"))
        guard let pct, let before, let label = model.range.before else { return base }
        let d = safeInt((pct - before).rounded())
        if d == 0 { return base + Text(L(", same as the \(label)", ", come nei \(label)")) }
        let sign = d > 0 ? "+" : "−"
        let points = L("\(sign)\(abs(d)) point\(abs(d) == 1 ? "" : "s")", "\(sign)\(abs(d)) punti")
        return base + Text(", ") + Text(points).foregroundStyle(d > 0 ? DashColor.good : DashColor.bad)
            + Text(L(" vs the \(label)", " sui \(label)"))
    }
}

struct TasksWidget: View {
    @ObservedObject var model: DashboardModel
    let size: WidgetSize

    var body: some View {
        let s = model.stats
        let change = model.range.before.flatMap { label in model.previous.flatMap { changeText(Double(s.count), Double($0.count), label) } }
        let median = decimal(s.medianMinutes)
        WidgetChrome(role: .figure, title: L("Tasks", "Task")) {
            FigureView(number: Double(s.count), format: { "\(safeInt($0.rounded()))" },
                       caption: Text([L("median \(median) min each", "mediana \(median) min l'uno"), change]
                                        .compactMap { $0 }.joined(separator: ", ")))
        }
    }
}

struct StreakWidget: View {
    let stats: DashStats
    let size: WidgetSize

    var body: some View {
        WidgetChrome(role: .figure, title: L("Best streak", "Serie migliore")) {
            FigureView(number: Double(stats.bestStreak), format: { "\(safeInt($0.rounded()))" }, unit: L("in a row", "di fila"),
                       caption: Text(L("estimates in range one after another, now \(stats.currentStreak)",
                                       "stime nella forchetta una dopo l'altra, ora \(stats.currentStreak)"))) {
                // The latest outcomes, newest on the right: filled when inside the range.
                HStack(spacing: 3) {
                    ForEach(Array(stats.recent.prefix(size.width > 1 ? 20 : 8).reversed().enumerated()), id: \.offset) { _, o in
                        let inside = o == .exact || o == .onTime
                        Circle()
                            .fill(inside ? o.palette[0] : Color.clear)
                            .overlay(Circle().strokeBorder(o.palette[0], lineWidth: inside ? 0 : 1.5))
                            .frame(width: 8, height: 8)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - now

/// The tasks running or waiting for you, with the panel's own rows and bars.
struct NowWidget: View {
    @ObservedObject var store: TaskStore
    let size: WidgetSize

    var body: some View {
        let open = store.visible.filter { $0.state == .running || $0.state == .waiting || $0.state == .background }
        let waiting = open.filter { $0.state == .waiting }.count
        let running = open.count - waiting
        let needYou = L("\(waiting) need\(waiting == 1 ? "s" : "") you", "\(waiting) ti \(waiting == 1 ? "aspetta" : "aspettano")")
        let summary = open.isEmpty ? lastDone
            : [running > 0 ? L("\(running) running", "\(running) in corso") : nil, waiting > 0 ? needYou : nil]
                .compactMap { $0 }.joined(separator: ", ")
        if size == .s1x1 {
            WidgetChrome(role: .figure, title: L("Now", "Adesso")) {
                FigureView(value: "\(open.count)", unit: L("running", "in corso"),
                           caption: waiting > 0 ? Text(needYou).foregroundStyle(Color.orange)
                                                : Text(open.isEmpty ? lastDone : L("nothing needs you", "nessuno ti aspetta")))
            }
        } else {
            WidgetChrome(role: .plate, title: L("Now", "Adesso"), subtitle: summary) {
                let done = store.visible.filter { $0.state == .done }
                if open.isEmpty && (done.isEmpty || size.height == 1) {
                    Text(L("Claude is on a coffee break. As soon as it starts again, the task shows up here with its bar.",
                           "Claude è in pausa caffè. Appena riparte, il task compare qui con la sua barra."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else if open.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(done.prefix(2 * (size.height - 1) * (size.width >= 3 ? 2 : 1))) {
                            TaskRow(item: $0, now: store.now, hidePrompts: store.hidePrompts)
                        }
                    }
                } else if size.height == 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(open.prefix(1)) { CompactRow(item: $0, now: store.now, hidePrompts: store.hidePrompts) }
                    }
                } else {
                    let perColumn = 2 * (size.height - 1)
                    let columns = size.width >= 3 ? 2 : 1
                    let shown = Array(open.prefix(perColumn * columns))
                    VStack(alignment: .leading, spacing: 10) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: columns),
                                  alignment: .leading, spacing: 14) {
                            ForEach(shown) { TaskRow(item: $0, now: store.now, hidePrompts: store.hidePrompts) }
                        }
                        if open.count > shown.count {
                            Text(L("\(open.count - shown.count) more in the panel", "Altri \(open.count - shown.count) nel pannello"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var lastDone: String {
        guard let last = store.visible.first(where: { $0.state == .done }) else { return L("no tasks running", "nessun task in corso") }
        let end = Date(timeIntervalSince1970: last.data.endTs ?? last.data.startTs)
        let at = end.formatted(date: .omitted, time: .shortened)
        return L("no tasks running, the last one ended at \(at)", "nessun task in corso, l'ultimo è finito alle " + at)
    }
}

// MARK: - hours

struct DaysWidget: View {
    @ObservedObject var model: DashboardModel
    let size: WidgetSize

    @Environment(\.dashIntro) private var intro

    var body: some View {
        let s = model.stats
        let worked = s.days.filter { $0.hours > 0 }
        let top = max(1, (s.days.map(\.hours).max() ?? 0) * 1.05)
        let average = worked.isEmpty ? 0 : s.hours / Double(worked.count)
        let start = model.periodStart
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let span = max(1, Int(end.timeIntervalSince(start) / 86400))
        let short = size.height == 1
        WidgetChrome(role: .plate, title: L("Hours per day", "Ore al giorno"),
                     subtitle: L("\(model.periodText), average \(decimal(average)) h on working days",
                                 "\(model.periodText), media \(decimal(average)) h nei giorni di lavoro")) {
            Chart {
                ForEach(s.days) { day in
                    BarMark(x: .value(L("Day", "Giorno"), day.date, unit: .day), y: .value(L("Hours", "Ore"), day.hours * intro))
                        .foregroundStyle(DashColor.data)
                        .cornerRadius(2)
                }
                if average > 0 {
                    RuleMark(y: .value(L("Average", "Media"), average))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: start...end)
            .chartYScale(domain: 0...top)
            .chartXAxis {
                AxisMarks(values: labelDays(start: start, span: span, every: max(1, span / (size.width >= 3 ? 10 : 5)))) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let h = value.as(Double.self) { Text("\(safeInt(h)) h") } }
                }
            }
            .chartXAxis(short && size.width < 4 ? .hidden : .automatic)
            .chartYAxis(short ? .hidden : .automatic)
        }
    }
}

/// Every `every` days from the start; when they skip days, none in the last stretch, where the
/// label would be cut at the edge.
private func labelDays(start: Date, span: Int, every: Int) -> [Date] {
    stride(from: 0, to: max(1, span - (every > 1 ? max(1, every / 2) : 0)), by: every).compactMap {
        Calendar.current.date(byAdding: .day, value: $0, to: start)
    }
}

/// Hours by project or by model: who takes the time.
struct HoursListWidget: View {
    let projects: Bool
    @ObservedObject var model: DashboardModel
    let size: WidgetSize

    var body: some View {
        let rows = projects ? model.stats.projects : model.stats.models
        let total = max(model.stats.hours, 0.000_1)
        if size == .s1x1 {
            let top = rows.first
            WidgetChrome(role: .figure, title: projects ? L("Top project", "Progetto principale") : L("Top model", "Modello principale")) {
                FigureView(value: top?.name ?? "–",
                           caption: Text(top.map { row -> String in
                               let h = decimal(row.hours), pct = safeInt((row.hours / total * 100).rounded())
                               return L("\(h) h, \(pct)% of the time", "\(h) h, il \(pct)% del tempo")
                           } ?? model.periodText),
                           isName: true) {
                    if let name = top?.name {
                        if projects { ProjectMark(project: name, size: 30) } else { ModelGlyph(model: name, size: 22) }
                    }
                }
            }
        } else {
            WidgetChrome(role: .plate, title: projects ? L("Projects", "Progetti") : L("Models", "Modelli"),
                         subtitle: projects ? L("where Claude's hours go, \(model.periodText)", "dove vanno le ore di Claude, \(model.periodText)")
                                            : L("who worked the most, \(model.periodText)", "chi ha lavorato di più, \(model.periodText)")) {
                HoursBars(rows: Array(rows.prefix(size.height == 1 ? 2 : 5)), total: total, inline: size.height == 1,
                          marks: projects ? .project : .model)
            }
        }
    }
}

/// Which mark goes before a name: a project's, a model's, or none.
enum MarkKind { case none, project, model }

/// The mark of a name, small, before it in a row.
@ViewBuilder
func markView(_ kind: MarkKind, _ name: String, size: CGFloat = 15) -> some View {
    switch kind {
    case .project: ProjectMark(project: name, size: size)
    case .model: ModelGlyph(model: name, size: size * 0.8).frame(width: size, height: size)
    case .none: EmptyView()
    }
}

struct HoursBars: View {
    let rows: [(name: String, hours: Double)]
    var total: Double = 0
    /// One line a row, the bar between the name and the hours (the short widgets).
    var inline = false
    var marks = MarkKind.none
    @Environment(\.dashIntro) private var intro

    var body: some View {
        let top = max(rows.map(\.hours).max() ?? 1, 0.01)
        VStack(alignment: .leading, spacing: inline ? 6 : 9) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if inline {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            markView(marks, row.name)
                            Text(row.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        }
                        .frame(width: 140, alignment: .leading)
                        bar(row.hours / top)
                        figures(row.hours)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .center, spacing: 6) {
                            markView(marks, row.name)
                            Text(row.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 6)
                            figures(row.hours)
                        }
                        bar(row.hours / top)
                    }
                }
            }
        }
    }

    private func bar(_ share: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DashColor.track)
                Capsule().fill(DashColor.data).frame(width: max(4, geo.size.width * share * intro))
            }
        }
        .frame(height: 5)
    }

    private func figures(_ hours: Double) -> some View {
        HStack(spacing: 6) {
            Text("\(decimal(hours)) h").font(.timer(11.5, .medium))
            if total > 0 {
                Text("\(safeInt((hours / total * 100).rounded()))%").font(.timer(11, .regular)).foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .fixedSize()
    }
}

// MARK: - estimates

/// The outcomes of the estimates as one bar, each outcome as wide as its share: the panel's bar,
/// at the size of the page. The one loud thing in the dashboard.
struct OutcomesWidget: View {
    let stats: DashStats
    let size: WidgetSize

    var body: some View {
        let wide = size.width >= 4
        let n = stats.withEstimate
        WidgetChrome(role: .hero, title: L("How the estimates went", "Gli esiti delle stime"),
                     subtitle: n == 0 ? L("no estimates in the period", "nessuna stima nel periodo")
                                      : L("\(n) task\(n == 1 ? "" : "s") with Claude's estimate", "\(n) task con la stima di Claude")) {
            VStack(alignment: .leading, spacing: 9) {
                OutcomeBar(stats: stats, height: wide ? 34 : 26)
                if wide {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Outcome.dashOrder, id: \.self) { legend($0, rule: true).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                        GridRow { legend(.exact, rule: false); legend(.faster, rule: false) }
                        GridRow { legend(.onTime, rule: false); legend(.slower, rule: false) }
                    }
                }
            }
        }
    }

    private func legend(_ o: Outcome, rule: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(o.palette[0]).frame(width: 9, height: 9).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 1) {
                Text(o.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if rule { Text(o.meme).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
}

struct OutcomeBar: View {
    let stats: DashStats
    var height: CGFloat = 34
    @Environment(\.dashIntro) private var intro

    var body: some View {
        GeometryReader { geo in
            let shown = Outcome.dashOrder.filter { (stats.outcomes[$0] ?? 0) > 0 }
            let total = Double(max(1, stats.withEstimate))
            let room = geo.size.width - CGFloat(max(0, shown.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(shown, id: \.self) { o in
                    let n = stats.outcomes[o] ?? 0
                    let w = room * CGFloat(Double(n) / total * intro)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(o.palette[0])
                        if w > 30 {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("\(n)").font(.timer(height > 28 ? 16 : 12.5, .bold))
                                if w > 70 { Text("\(safeInt((Double(n) / total * 100).rounded()))%").font(.timer(11, .medium)).opacity(0.75) }
                            }
                            .foregroundStyle(Color.black.opacity(0.8))
                            .padding(.leading, 9)
                        }
                    }
                    .frame(width: max(2, w))
                    .help("\(o.name): \(n)")
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .background(DashColor.track)
            .clipShape(RoundedRectangle(cornerRadius: height > 28 ? 8 : 6, style: .continuous))
        }
        .frame(height: height)
    }
}

/// Where the estimates miss: by kind of work, by model, by project, as small tables.
struct MissesWidget: View {
    let stats: DashStats
    let period: String
    let size: WidgetSize

    var body: some View {
        let rows = size.height >= 3 ? 9 : 5
        let all = stats.overall
        let pct = safeInt((all.share * 100).rounded()), ratio = decimal(all.ratio)
        WidgetChrome(role: .plate, title: L("Where the estimates miss", "Dove sbagliano le stime"),
                     subtitle: L("\(period), overall \(pct)% in range and actual/est. ×\(ratio): the worst ones in orange",
                                 "\(period), in tutto \(pct)% nella forchetta e reale/stima ×\(ratio): in arancione chi fa peggio")) {
            if size.width >= 3 {
                HStack(alignment: .top, spacing: 26) {
                    AccuracyTable(title: L("By kind of work", "Per tipo di lavoro"), rows: Array(stats.byKind.prefix(rows)), overall: all)
                        .help(L("The kind Claude writes in the ⏱ line: how many tools it expects to use",
                                "Il tipo scritto da Claude nel ⏱: quanti strumenti pensa di usare"))
                    AccuracyTable(title: L("By model", "Per modello"), rows: Array(stats.accuracyByModel.prefix(rows)), overall: all, marks: .model)
                    if size.width >= 4 {
                        AccuracyTable(title: L("By project", "Per progetto"), rows: Array(stats.accuracyByProject.prefix(rows)),
                                      overall: all, marks: .project)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    AccuracyTable(title: L("By kind of work", "Per tipo di lavoro"), rows: Array(stats.byKind.prefix(4)), overall: all)
                    if let worst = worst {
                        Text(worst).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
    }

    /// For the narrow form: the model and the project that miss the most.
    private var worst: String? {
        let floor = stats.overall.share - 0.1
        let pick = { (rows: [DashStats.Accuracy]) in rows.filter { $0.count >= 5 && $0.share < floor }.min { $0.share < $1.share } }
        let parts = [pick(stats.accuracyByModel).map { "\($0.name) \(safeInt(($0.share * 100).rounded()))%" },
                     pick(stats.accuracyByProject).map { "\($0.name) \(safeInt(($0.share * 100).rounded()))%" }].compactMap { $0 }
        let list = parts.joined(separator: ", ")
        return parts.isEmpty ? nil : L("Most often off: \(list)", "Più spesso fuori: " + list)
    }
}

struct AccuracyTable: View {
    let title: String
    let rows: [DashStats.Accuracy]
    /// All the estimates: a group 10 points under it, or 1,5 times its real/estimate, is in orange.
    var overall: DashStats.Accuracy?
    var marks = MarkKind.none
    @Environment(\.dashIntro) private var intro

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L("est.", "stime")).frame(width: 28, alignment: .trailing)
                Text(L("in range", "in forchetta")).frame(width: 70, alignment: .trailing)
                Text(L("actual/est.", "reale/stima")).frame(width: 56, alignment: .trailing)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5)
            if rows.isEmpty {
                Text(L("Not enough estimates yet.", "Ancora poche stime.")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(rows) { line($0) }
        }
    }

    private func line(_ r: DashStats.Accuracy) -> some View {
        let pct = safeInt((r.share * 100).rounded())
        let worse = r.share < (overall?.share ?? 0.5) - 0.1
        let slower = r.ratio >= max(1.5, (overall?.ratio ?? 1) * 1.5)
        return HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 5) {
                markView(marks, r.name, size: 12)
                Text(r.label).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(r.label)
            Text("\(r.count)").font(.timer(11, .regular)).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DashColor.track)
                        Capsule().fill(DashColor.good.opacity(0.85)).frame(width: max(3, geo.size.width * r.share * intro))
                    }
                }
                .frame(width: 28, height: 5)
                Text("\(pct)%").font(.timer(12, .semibold))
                    .foregroundStyle(worse ? DashColor.bad : Color.primary)
                    .frame(width: 36, alignment: .trailing)
            }
            .frame(width: 70, alignment: .trailing)
            Text("×\(decimal(r.ratio))").font(.timer(12, .medium))
                .foregroundStyle(slower ? DashColor.bad : Color.primary)
                .frame(width: 56, alignment: .trailing)
                .help(r.ratio >= 1 ? L("usually takes \(decimal(r.ratio)) times the estimate", "di solito dura \(decimal(r.ratio)) volte la stima")
                      : L("usually finishes before the estimate", "di solito finisce prima della stima"))
        }
    }
}

struct ScatterWidget: View {
    let stats: DashStats
    let size: WidgetSize
    @Environment(\.dashIntro) private var intro

    var body: some View {
        WidgetChrome(role: .plate, title: L("Estimate vs actual time", "Stima e tempo reale"),
                     subtitle: L("one dot per task: the estimate across, the actual time up",
                                 "un punto per task: in orizzontale la stima, in verticale il tempo reale")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ForEach(Outcome.dashOrder, id: \.self) { o in
                        HStack(spacing: 4) {
                            Circle().fill(o.palette[0]).frame(width: 7, height: 7)
                            Text(o.name).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                let lo = 5.0, hi = max(3600.0, (stats.points.map { max($0.real, $0.estimate) }.max() ?? 0) * 1.2)
                let estimate = L("Estimate", "Stima"), actual = L("Actual", "Reale")
                Chart {
                    ForEach([lo, hi], id: \.self) { v in
                        LineMark(x: .value(estimate, v), y: .value(actual, v),
                                 series: .value(L("Line", "Linea"), L("perfect estimate", "stima perfetta")))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    ForEach(stats.points) { p in
                        PointMark(x: .value(estimate, max(lo, p.estimate)), y: .value(actual, max(lo, p.real)))
                            .foregroundStyle(p.outcome.palette[0].opacity(intro))
                            .symbol(p.outcome.symbol)
                            .symbolSize(30)
                    }
                }
                .chartXScale(domain: lo...hi, type: .log)
                .chartYScale(domain: lo...hi, type: .log)
                .chartXAxis { logAxis }
                .chartYAxis { logAxis }
                .padding(.top, 10)
            }
        }
    }

    private var logAxis: some AxisContent {
        AxisMarks(values: [10.0, 60.0, 300.0, 1800.0, 10_800.0] as [Double]) { value in
            AxisGridLine()
            AxisValueLabel { if let v = value.as(Double.self) { Text(axisTime(v)) } }
        }
    }
}

// MARK: - when

struct HeatWidget: View {
    let stats: DashStats
    let size: WidgetSize
    @Environment(\.dashIntro) private var intro
    /// Monday first.
    private var shortDays: [String] {
        [L("Mon", "lun"), L("Tue", "mar"), L("Wed", "mer"), L("Thu", "gio"), L("Fri", "ven"), L("Sat", "sab"), L("Sun", "dom")]
    }

    var body: some View {
        let top = max(1, stats.heat.flatMap { $0 }.max() ?? 1)
        let days = shortDays
        if size == .s1x1 {
            let peak = (0..<7).flatMap { d in (0..<24).map { (d, $0) } }.max { stats.heat[$0.0][$0.1] < stats.heat[$1.0][$1.1] }
            let longDays = [L("Monday", "lunedì"), L("Tuesday", "martedì"), L("Wednesday", "mercoledì"), L("Thursday", "giovedì"),
                            L("Friday", "venerdì"), L("Saturday", "sabato"), L("Sunday", "domenica")]
            WidgetChrome(role: .figure, title: L("Peak hour", "Ora di punta")) {
                FigureView(value: peak.map { "\($0.1):00" } ?? "–",
                           caption: Text(peak.map { p -> String in
                               let day = longDays[p.0]
                               return L("on \(day)s, \(top) task\(top == 1 ? "" : "s") started in that hour",
                                        "il \(day), \(top) task avviati in quell'ora")
                           } ?? L("no tasks", "nessun task")))
            }
        } else {
            WidgetChrome(role: .plate, title: L("When you work", "Quando lavori"),
                         subtitle: L("tasks started by weekday and hour", "task avviati per giorno della settimana e ora")) {
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        Text("").frame(width: 28)
                        ForEach(0..<24, id: \.self) { h in
                            Text(h % (size.width >= 3 ? 3 : 6) == 0 ? "\(h)" : "").font(.system(size: 9.5)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(0..<7, id: \.self) { d in
                        HStack(spacing: size.width >= 3 ? 3 : 2) {
                            Text(days[d]).font(.system(size: 10.5)).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                            ForEach(0..<24, id: \.self) { h in
                                let n = stats.heat[d][h]
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(n == 0 ? Color.primary.opacity(0.05) : DashColor.data.opacity((0.2 + 0.8 * Double(n) / Double(top)) * intro))
                                    .frame(maxWidth: .infinity, maxHeight: 22)
                                    .help(L("\(days[d]) \(h):00, \(n) task\(n == 1 ? "" : "s")", "\(days[d]) ore \(h): \(n) task"))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - history

struct HistoryWidget: View {
    @ObservedObject var model: DashboardModel
    let size: WidgetSize

    var body: some View {
        let rows = model.history
        let wide = size.width >= 3
        let count = model.stats.count
        WidgetChrome(role: .plate, title: L("History", "Storico"),
                     subtitle: L("\(count) task\(count == 1 ? "" : "s"), \(model.periodText)", "\(count) task, \(model.periodText)")) {
            TextField(L("Search prompts and projects", "Cerca nei prompt o nei progetti"), text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(width: wide ? 260 : 170)
        } content: {
          VStack(alignment: .leading, spacing: 8) {
            if let f = model.mineFilter {
                // From the mine: only the tasks of one find; the ✕ shows them all again.
                HStack(spacing: 6) {
                    OreIcon(ore: f.ore, size: 16)
                    let ore = f.ore.name.lowercased(), n = rows.count
                    Text(L("Only \(ore)\(f.week == nil ? "" : ", that week"): \(n) prompt\(n == 1 ? "" : "s")",
                           "Solo \(ore)" + (f.week.map { _ in ", quella settimana" } ?? "") + ": \(n) prompt"))
                        .font(.system(size: 12, weight: .semibold))
                    Button { model.mineFilter = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Show all prompts", "Mostra tutti i prompt"))
                }
            }
            if rows.isEmpty {
                Text(model.mineFilter != nil ? L("No prompts with this ore.", "Nessun prompt con questo minerale.")
                     : L("No prompt contains this text. A typo, maybe?",
                         "Nessun prompt contiene questo testo. Magari l'avevi scritto con un refuso?"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else if DashDebug.snapshot {
                list(Array(rows.prefix(max(1, (size.height * 126 - 104) / 43))), wide: wide)
            } else {
                ScrollView {
                    list(rows, wide: wide).padding(.trailing, 8)
                    if rows.count == model.historyLimit {
                        Text(L("Showing the \(model.historyLimit) most recent: search to find the others.",
                               "Mostrati i \(model.historyLimit) più recenti: cerca per trovarne altri."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 6)
                    }
                }
            }
          }
        }
    }

    private func list(_ rows: [PastTask], wide: Bool) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { task in
                HistoryRow(task: task, link: task.session.flatMap(model.chatLink), wide: wide)
                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5)
            }
        }
    }
}

struct HistoryRow: View {
    let task: PastTask
    let link: URL?
    var wide = true

    var body: some View {
        HStack(spacing: 10) {
            Text(Date(timeIntervalSince1970: task.start).formatted(.dateTime.day().month(.twoDigits).hour().minute().locale(Loc.locale)))
                .font(.timer(11, .regular)).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.prompt.isEmpty ? "…" : task.prompt).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                    .help(task.prompt)
                HStack(spacing: 4) {
                    ProjectMark(project: task.project, size: 11)
                    Text(task.project)
                    ModelGlyph(model: task.model, size: 9).padding(.leading, 6)
                    Text(task.model)
                }
                .font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(task.estimate.map { est -> String in
                let real = clock(task.real), approx = approxEstimate(est)
                return L("\(real) vs \(approx)", "\(real) su \(approx)")
            } ?? clock(task.real))
                .font(.timer(11, .medium)).foregroundStyle(.secondary).fixedSize()
            HStack(spacing: 6) {
                if let o = task.outcome {
                    RoundedRectangle(cornerRadius: 2).fill(o.palette[0]).frame(width: 8, height: 8)
                    if wide { Text(o.name).font(.system(size: 11, weight: .medium)).lineLimit(1) }
                }
            }
            .frame(width: wide ? 138 : 10, alignment: .leading)
            .help(task.outcome?.name ?? L("no estimate", "senza stima"))
            if let link {
                Button { openChat(link) } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.borderless)
                    .help(L("Open the chat", "Apri la chat"))
            } else {
                Image(systemName: "arrow.up.forward.square").foregroundStyle(.quaternary)
                    .help(L("The chat isn't in the Claude app", "La chat non è nell'app Claude"))
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - the window

/// The dashboard window: one, made on first use, its history dropped when closed.
final class DashboardController: NSObject, NSWindowDelegate {
    static let shared = DashboardController()
    /// The live store: where the index is, and the app's sessions for the chat links.
    var store: TaskStore?
    private var window: NSWindow?
    private var model: DashboardModel?
    private var languageObserver: NSObjectProtocol?

    private static var title: String { L("Task analytics", "Analytics dei task") }

    func show() {
        guard let store else { return }
        if window == nil {
            let model = DashboardModel(indexURL: store.indexURL,
                                       chatLink: { [weak store] cli in store?.appSession(forCLI: cli)?.id.flatMap {
                                           URL(string: "claude://code/continue?session=\($0)") } })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 820),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = DashboardController.title
            // The title follows the language, like the content.
            languageObserver = NotificationCenter.default.addObserver(forName: Loc.changed, object: nil, queue: .main) { [weak self] _ in
                self?.window?.title = DashboardController.title
            }
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: DashboardView(model: model))
            window.setContentSize(NSSize(width: 980, height: 820))
            window.center()
            window.setFrameAutosaveName("TaskETADashboard")
            window.delegate = self
            self.window = window
            self.model = model
        }
        model?.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { model?.drop() }
}

// MARK: - settings

/// The settings in a window of their own: the same as behind the gear, reachable from the
/// TaskETA menu (⌘,) and from the dashboard.
struct SettingsView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var prefs: Prefs
    @ObservedObject var phone: PhoneServer
    /// The last script action's outcome, put in words when shown (a language switch reaches it).
    @State private var scriptDone: ScriptDone?

    private enum ScriptDone { case missing, copied, notWritten, saved, newCode }

    private var scriptNote: String? {
        switch scriptDone {
        case .missing: return L("Script not found in the app: build it again.", "Script non trovato nell'app: rifai la build.")
        case .copied: return L("Copied. On the iPhone: Scriptable > + > paste, and name it TaskETA.",
                               "Copiato. Sull'iPhone: Scriptable > + > incolla, e chiamalo TaskETA.")
        case .notWritten: return L("Couldn't write to iCloud Drive > Scriptable.", "Non riuscito a scrivere in iCloud Drive > Scriptable.")
        case .saved: return L("Saved to iCloud Drive > Scriptable > TaskETA: it'll be on the iPhone shortly.",
                              "Salvato in iCloud Drive > Scriptable > TaskETA: tra poco è anche sull'iPhone.")
        case .newCode: return L("New code: put the script on the iPhone again, the old one can't get in any more.",
                                "Codice nuovo: rimetti lo script sull'iPhone, quello vecchio non entra più.")
        case nil: return nil
        }
    }
    @AppStorage(HoleCheer.onKey) private var holeCheer = true
    @ObservedObject private var loc = Loc.shared

    var body: some View {
        Form {
            Section {
                // The same words in both languages, so anyone can find it.
                Picker(selection: Binding(get: { loc.choice }, set: { Loc.shared.set($0) })) {
                    ForEach(LangChoice.allCases) { Text($0.label).tag($0) }
                } label: {
                    Text(verbatim: "Language / Lingua")
                }
            }
            Section(L("Where to see it", "Dove vederli")) {
                Toggle(L("Panel on the desktop", "Pannello sul desktop"), isOn: $prefs.panelVisible)
                Toggle(L("Short panel, counts only", "Pannello corto, solo i conteggi"), isOn: $store.compact)
                Toggle(L("Open the list by hovering the icon", "Apri la lista passando sul simbolo"), isOn: $prefs.hoverOpen)
                Toggle(L("Button in the Touch Bar", "Pulsante nella Touch Bar"), isOn: $prefs.touchBarOn)
                Toggle(L("Click by hovering with the pointer", "Clic restando sopra con il puntatore"), isOn: $prefs.dwellClick)
                    .help(L("On “Read the analysis”, “Open the dashboard”, the folders and “More”: it opens as soon as you hover over it, no click needed.",
                            "Su «Leggi l'analisi», «Apri la dashboard», le cartelle e «Altri»: si apre appena ci passi sopra, senza cliccare."))
            }
            Section(L("Notifications", "Avvisi")) {
                Picker(L("When", "Quando"), selection: $prefs.notifyMode) {
                    ForEach(NotifyMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle(L("When a task finishes", "Quando un task finisce"), isOn: $prefs.notifyDone)
                    .disabled(prefs.notifyMode == .never)
                Toggle(L("When Claude needs you", "Quando Claude ti aspetta"), isOn: $prefs.notifyWaiting)
                    .disabled(prefs.notifyMode == .never)
            }
            Section(L("Privacy", "Privacy")) {
                Toggle(L("Hide prompts and titles (screen sharing)", "Nascondi prompt e titoli (condivisione schermo)"), isOn: $store.hidePrompts)
                Toggle(L("Show automated runs (claude -p)", "Mostra le run automatiche (claude -p)"), isOn: $store.showAutomated)
            }
            Section(L("iPhone", "iPhone")) {
                Toggle(L("Widget on the iPhone (same Wi-Fi as the Mac)", "Widget sull'iPhone (stessa Wi-Fi del Mac)"), isOn: $prefs.phoneOn)
                if prefs.phoneOn {
                    ForEach([phone.note, phone.scriptNote].compactMap { $0 }, id: \.self) { note in
                        Text(note).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    HStack {
                        Button(L("Copy the script", "Copia lo script")) { copyScript() }
                        Button(L("Put it in Scriptable", "Mettilo in Scriptable")) { saveScript() }
                            .disabled(!FileManager.default.fileExists(atPath: PhoneScript.iCloudFolder.path))
                        Button(L("New code", "Nuovo codice")) { newToken() }
                    }
                    Text(scriptNote ?? L("The script updates itself in iCloud Drive > Scriptable: on the iPhone it shows up in Scriptable as TaskETA. Without iCloud, “Copy the script” puts it on the clipboard, to paste into a new script.",
                                         "Lo script si aggiorna da solo in iCloud Drive > Scriptable: sull'iPhone compare in Scriptable come TaskETA. Senza iCloud, «Copia lo script» lo mette negli appunti per incollarlo in un nuovo script."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Section(L("Game", "Gioco")) {
                GameMoodPicker()
            }
            Section(L("System", "Sistema")) {
                Toggle(L("Open at login", "Apri al login"), isOn: Binding(get: { prefs.loginOn }, set: { prefs.setLogin($0) }))
                if let note = prefs.loginNote {
                    Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack {
                    Button(L("Open the dashboard", "Apri la dashboard")) { DashboardController.shared.show() }
                        .dwellClick { DashboardController.shared.show() }
                    Button(L("Show the live files folder", "Mostra la cartella dei file live")) { prefs.openLiveFolder(store.dir) }
                        .dwellClick { prefs.openLiveFolder(store.dir) }
                }
                Toggle(L("Cheer when you sink the ball", "Esultanza quando fai buca"), isOn: $holeCheer)
                HStack {
                    Button(L("Sounds folder", "Cartella dei suoni")) {
                        try? FileManager.default.createDirectory(at: HoleCheer.soundsDir, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([HoleCheer.soundsDir])
                    }
                    Button(L("Try the cheer", "Prova l'esultanza")) { HoleCheer.cheer(level: 3, always: true) }
                }
                Text(L("Put an audio file of yours named cheer in this folder (mp3, m4a, wav or aiff): you'll hear it when you sink the ball.",
                       "Metti in questa cartella un tuo audio chiamato cheer (mp3, m4a, wav o aiff): lo sentirai quando fai buca."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 470)
        .followsLanguage()
    }

    private func copyScript() {
        guard let text = PhoneScript.text(token: prefs.phoneToken) else {
            scriptDone = .missing
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        scriptDone = .copied
    }

    private func saveScript() {
        let url = PhoneScript.iCloudFolder.appendingPathComponent("TaskETA.js")
        guard let text = PhoneScript.text(token: prefs.phoneToken),
              (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else {
            scriptDone = .notWritten
            return
        }
        scriptDone = .saved
        phone.syncScript()
    }

    /// A new code locks out the scripts already on the iPhone: the one in iCloud is rewritten.
    private func newToken() {
        prefs.phoneToken = Prefs.newToken()
        let saved = PhoneScript.iCloudFolder.appendingPathComponent("TaskETA.js")
        if FileManager.default.fileExists(atPath: saved.path) {
            saveScript()
        } else {
            scriptDone = .newCode
        }
    }
}

final class SettingsController {
    static let shared = SettingsController()
    var store: TaskStore?
    var prefs: Prefs?
    var phone: PhoneServer?
    private var window: NSWindow?
    private var languageObserver: NSObjectProtocol?

    private static var title: String { L("TaskETA Settings", "Impostazioni di TaskETA") }

    func show() {
        guard let store, let prefs, let phone else { return }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 520),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = SettingsController.title
            // The title follows the language, like the content (switched from this very window).
            languageObserver = NotificationCenter.default.addObserver(forName: Loc.changed, object: nil, queue: .main) { [weak self] _ in
                self?.window?.title = SettingsController.title
            }
            window.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: SettingsView(store: store, prefs: prefs, phone: phone))
            host.sizingOptions = .preferredContentSize
            window.contentViewController = host
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
