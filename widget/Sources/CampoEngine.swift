import Foundation
import SwiftUI

// The game's engine in one place ("Il campo"): where the user is on the 9
// holes, which trials are done and why, which powers are on, which mini golf courses are open, and
// Claude's own score on its estimates. The rules are Campo.swift's (CampoCourse, CampoGame): this
// file reads them and adds the reasons, never
// a second copy of a rule. Worked out from task-eta's index (and, for Claude's score, the log of what
// the hook offered); nothing is saved, and it is read again only when those files change.

// MARK: - powers

/// The powers of the course, one per hole, numbered as the hole that lights it.
enum CampoPower: Int, CaseIterable {
    case fairway = 1, caddie, mulligan, strongClub, night, doubleHole, trophy, eagle, greenJacket

    var rule: CampoCourse.Rule { CampoCourse.rules[rawValue - 1] }
    var name: String { rule.power }

    /// Whether the app does it yet: the three widget styles (still won by their old rules in
    /// WidgetTheme, Gems.swift) and the strong club (GolfRules.swift). The others are won but to come.
    var built: Bool { [.fairway, .night, .trophy, .strongClub].contains(self) }
}

// MARK: - Claude's own score

/// What the hook offered for one prompt (suggestions.jsonl): per kind, the estimate and its likely
/// range in seconds, the range nil while the kind is not calibrated.
struct HookOffer {
    typealias Line = (est: Double, low: Double?, high: Double?)
    let ts: Double
    let kinds: [String: Line]
    /// The "with brief subagents" line, when the block had one.
    let brief: Line?
    /// The model the hook estimated for, when the log says.
    var model: String? = nil

    /// The hook's log, next to the index.
    static var logURL: URL { TaskStore.indexURL.deletingLastPathComponent().appendingPathComponent("suggestions.jsonl") }

    /// Bytes of the log read, as task_eta.py's SCORE_TAIL: the last ones of the log, then of the
    /// rotated .old file for what is left.
    static let tail = 256 * 1024

    /// The offers by session, oldest first, as hook_offers in task_eta.py. Bad lines are skipped.
    static func load(_ url: URL, tail: Int = HookOffer.tail) -> [String: [HookOffer]] {
        var budget = tail
        var chunks: [Data] = []
        for path in [url.path, url.path + ".old"] where budget > 0 {
            // Never through a link, and never a FIFO or a device: non-blocking, then only a plain file.
            let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
            guard fd >= 0 else { continue }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close() }
            var st = stat()
            guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG else { continue }
            let size = Int(st.st_size)
            guard (try? handle.seek(toOffset: UInt64(max(0, size - budget)))) != nil,
                  let data = try? handle.read(upToCount: budget) else { continue }
            if size > budget {
                // The first line is cut in two: dropped.
                guard let cut = data.firstIndex(of: UInt8(ascii: "\n")) else { budget -= data.count; continue }
                chunks.append(data[data.index(after: cut)...])
            } else {
                chunks.append(data)
            }
            budget -= data.count
        }
        var all = Data()
        for chunk in chunks.reversed() {   // the .old file's lines first
            all.append(chunk)
            all.append(UInt8(ascii: "\n"))
        }
        return parse(all)
    }

    static func parse(_ data: Data) -> [String: [HookOffer]] {
        var out: [String: [HookOffer]] = [:]
        for raw in data.split(separator: UInt8(ascii: "\n")) {
            guard let o = try? JSONSerialization.jsonObject(with: Data(raw)) as? [String: Any],
                  let session = o["session"] as? String, let ts = sane((o["ts"] as? NSNumber)?.doubleValue),
                  let kinds = o["kinds"] as? [String: Any] else { continue }
            var lines: [String: Line] = [:]
            for (k, v) in kinds { if let line = HookOffer.line(v) { lines[k] = line } }
            out[session, default: []].append(HookOffer(ts: ts, kinds: lines, brief: HookOffer.line(o["brief"]),
                                                       model: o["model"] as? String))
        }
        return out
    }

    /// [est, low, high] with low and high possibly null.
    private static func line(_ value: Any?) -> Line? {
        guard let a = value as? [Any], a.count == 3, let est = sane((a[0] as? NSNumber)?.doubleValue), est > 0 else { return nil }
        let low = sane((a[1] as? NSNumber)?.doubleValue), high = sane((a[2] as? NSNumber)?.doubleValue)
        guard let lo = low, let hi = high, hi > lo, lo >= 0 else { return (est, nil, nil) }
        return (est, lo, hi)
    }

    /// The offer for a task: same session, made within a minute of its prompt (the hook runs as the
    /// prompt is sent, so it is ~0.3 s off), the closest one. Nil when that one was made for another
    /// model than the task's (both known): never another offer in its place.
    static func of(_ task: PastTask, in offers: [String: [HookOffer]]) -> HookOffer? {
        guard let session = task.session, let list = offers[session],
              let offer = list.filter({ $0.ts - task.start >= -10 && $0.ts - task.start <= 60 })
                .min(by: { abs($0.ts - task.start) < abs($1.ts - task.start) }) else { return nil }
        // PastTask.model is "model effort"; a model name always has a digit, an effort never.
        let word = task.model.split(separator: " ").first.map(String.init) ?? ""
        let mine = bare(word.contains(where: \.isNumber) ? word : ""), theirs = bare(offer.model ?? "")
        return !mine.isEmpty && !theirs.isEmpty && mine != theirs ? nil : offer
    }

    /// "claude-opus-5-5" and "opus-5-5" are the same model.
    private static func bare(_ model: String) -> String {
        model.hasPrefix("claude-") ? String(model.dropFirst("claude-".count)) : model
    }
}

/// Claude's own score on its ⏱ estimates, the same rules as task_eta.py's claude_score (the line in
/// the [task-eta] block): each estimate is scored against what the hook offered for the kind Claude
/// declared, never against the range Claude wrote, so it cannot widen it. Hit within 8% (or 10 s),
/// inside the range, too short (real past it) or too long (real under it): for Claude a finish
/// faster than the range is an error too, or declaring a bigger kind would always pay.
/// Tasks the user stopped, and estimates with no offer in the log, are not scored.
struct ClaudeScore: Equatable {
    enum Mark: String {
        case hit, inside, short, long
        var isInside: Bool { self == .hit || self == .inside }
    }

    static let window = 18
    var marks: [Mark] = []

    init(marks: [Mark] = []) { self.marks = marks }

    init(_ tasks: [PastTask], offers: [String: [HookOffer]]) {
        for t in tasks.sorted(by: { $0.start < $1.start }) {
            guard !t.interrupted, let claudeEst = t.estimate, let raw = t.kind,
                  let offer = HookOffer.of(t, in: offers) else { continue }
            let kind = legacyKinds[raw] ?? raw
            guard var line = offer.kinds[kind] else { continue }
            // Two lines for subagents: Claude's own number only says which of the two it copied.
            if kind == "agents", let brief = offer.brief, abs(claudeEst - brief.est) < abs(claudeEst - line.est) { line = brief }
            marks.append(ClaudeScore.mark(real: t.real, line))
        }
    }

    /// The app's one rule (outcomeOf) with the hook's 10 second floor: past the range Claude was short, under it long.
    static func mark(real: Double, _ line: HookOffer.Line) -> Mark {
        let range = line.low.flatMap { low in line.high.map { (low, $0) } }
        switch outcomeOf(real: real, estimate: line.est, range: range, floor: 10) {   // as task_eta.py scores it
        case .exact: return .hit
        case .onTime: return .inside
        case .slower: return .short
        case .faster: return .long
        }
    }

    var last: ArraySlice<Mark> { marks.suffix(ClaudeScore.window) }
    var inside: Int { last.filter(\.isInside).count }
    var hits: Int { last.filter { $0 == .hit }.count }
    var short: Int { last.filter { $0 == .short }.count }
    var long: Int { last.filter { $0 == .long }.count }
    var streak: Int { marks.reversed().prefix { $0.isInside }.count }
    /// The most estimates inside the range in any 18 in a row.
    var best: Int {
        guard marks.count > ClaudeScore.window else { return inside }
        var n = marks.prefix(ClaudeScore.window).filter(\.isInside).count, top = n
        for i in ClaudeScore.window..<marks.count {
            n += (marks[i].isInside ? 1 : 0) - (marks[i - ClaudeScore.window].isInside ? 1 : 0)
            top = max(top, n)
        }
        return top
    }

    /// «12 dentro la forchetta (8 centrate), 5 troppo corte, 1 troppo lunga».
    var counts: String {
        L("\(inside) inside the range (\(hits) spot on), \(short) too short, \(long) too long",
          "\(inside) dentro la forchetta (\(hits) \(hits == 1 ? "centrata" : "centrate")), "
            + "\(short) troppo \(short == 1 ? "corta" : "corte"), \(long) troppo \(long == 1 ? "lunga" : "lunghe")")
    }

    /// For the dashboard and the report: «Ultime 18 stime di Claude: 12 dentro ...».
    var line: String {
        guard !marks.isEmpty else {
            return L("Claude has no estimates with the hook's offer to count yet.", "Claude non ha ancora stime con l'offerta dell'hook da contare.")
        }
        let of = min(marks.count, ClaudeScore.window)
        return L("Claude's last \(last.count) estimates: \(counts); streak \(streak), record \(best) of \(of).",
                 "Ultime \(last.count) stime di Claude: \(counts); serie \(streak), record \(best) su \(of).")
    }

    /// Why it is scored this way: the rule that keeps it honest. Computed: it follows a language switch.
    static var why: String {
        L("""
          Claude's score counts against the range the hook offers for the declared kind, not the one Claude writes; \
          spot on only within 8%; for Claude, finishing before the range is an error (estimate too long). \
          It measures the estimate, never the work.
          """,
          "Il punteggio di Claude conta contro la forchetta che l'hook offre per il tipo dichiarato, non quella che Claude scrive; "
            + "centrata solo entro l'8%; finire prima della forchetta per Claude è un errore (stima troppo lunga). "
            + "Si misura la stima, mai il lavoro.")
    }
}

// MARK: - the engine

/// Where the game is, worked out once from the index: the course, its reasons, the powers on.
struct CampoEngine {
    let gems: GemStats
    let game: CampoGame
    let course: [CampoGame.Hole]
    let claude: ClaudeScore
    let now: Date
    /// How often a clean shot and any other hole end in a pebble; nil with fewer than 5 of either.
    let pebbles: (clean: Double, other: Double, cleanShare: Double)?

    init(_ tasks: [PastTask], offers: [String: [HookOffer]] = [:], now: Date = Date()) {
        self.now = now
        gems = GemStats(tasks, now: now)
        game = CampoGame(tasks, points: gems.points, now: now)
        course = game.course()
        claude = ClaudeScore(tasks, offers: offers)
        let clean = game.holes.filter(\.isClean), other = game.holes.filter { !$0.isClean }
        if clean.count >= 5, other.count >= 5 {
            pebbles = (Double(CampoGame.bogeys(clean)) / Double(clean.count), Double(CampoGame.bogeys(other)) / Double(other.count),
                       Double(clean.count) / Double(game.holes.count))
        } else {
            pebbles = nil
        }
    }

    var points: Int { gems.points }
    /// Holes played: every task with an estimate, the bogeys too.
    var played: Int { game.holes.count }
    var currentIndex: Int? { course.firstIndex { !$0.closed } }
    var current: CampoGame.Hole? { currentIndex.map { course[$0] } }
    var closed: [CampoGame.Hole] { course.filter(\.closed) }
    var title: String? { closed.last?.rule.title }

    func isOn(_ power: CampoPower) -> Bool { course[power.rawValue - 1].closed }
    var powersOn: [CampoPower] { CampoPower.allCases.filter(isOn) }

    /// "Fairway, Mazza forte; vinti, ancora da costruire: Mulligan".
    var powersText: String {
        let on = powersOn.filter(\.built).map(\.name), later = powersOn.filter { !$0.built }.map(\.name)
        guard !powersOn.isEmpty else { return L("none", "nessuno") }
        return (on.isEmpty ? L("none working yet", "nessuno in funzione") : on.joined(separator: ", "))
            + (later.isEmpty ? "" : L("; won, still to be built: ", "; vinti, ancora da costruire: ") + later.joined(separator: ", "))
    }

    /// The mini golf's courses open now (the lawn always), and the next one with the holes it needs.
    var fields: [CampoMinigolf] { CampoMinigolf.allCases.filter { played >= $0.need } }
    var nextField: CampoMinigolf? { CampoMinigolf.allCases.first { played < $0.need } }

    // MARK: reasons

    /// A hole in one sentence: closed and why, being played and what is missing, or still to play.
    func why(_ hole: CampoGame.Hole) -> String {
        let r = hole.rule
        let green = points >= r.green
            ? (r.green == 0 ? L("green from the start", "green da subito")
                : L("green at \(g(r.green)) reached (\(g(points)) points)", "green a \(g(r.green)) raggiunto (\(g(points)) punti)"))
            : L("green at \(g(r.green)), \(g(r.green - points)) to go", "green a \(g(r.green)), ne mancano \(g(r.green - points))")
        let trials = zip(r.trials, hole.trials).map { "\($1.name), \(evidence($0, $1))" }
        let reasons = ([green] + trials).joined(separator: "; ")
        if hole.closed {
            return L("Hole \(r.number) done: \(reasons). Power: \(r.power).", "Buca \(r.number) chiusa: " + reasons + ". Potere: \(r.power).")
        }
        if r.number - 1 == currentIndex {
            var out = L("Hole \(r.number) in play: \(reasons).", "Buca \(r.number) in corso: " + reasons + ".")
            if points < r.green, let eta = CampoData.eta(gems, green: r, now: now) { out += " " + eta }
            if let tip = tip(for: hole) { out += L(" What to do: ", " Cosa fare: ") + tip }
            return out
        }
        let done = zip(r.trials, hole.trials).filter { $0.1.done }.map { $0.1.name }
        let list = done.joined(separator: ", ")
        return L("Hole \(r.number) to play: it comes after hole \(r.number - 1).", "Buca \(r.number) da giocare: si gioca dopo la \(r.number - 1).")
            + (done.isEmpty ? "" : L(" Already done, and it stays done: \(list).", " Già fatta, e resta fatta: \(list)."))
    }

    /// One trial's evidence: the number that decides it, when and where it happened.
    func evidence(_ trial: CampoTrial, _ t: CampoGame.Trial) -> String {
        let none = L("no round finished", "nessun giro chiuso")
        switch trial {
        case .firstRound:
            if let first = game.rounds.first {
                let n = game.rounds.count
                return L("done: the first round of 18 holes finished \(day(first.day)); \(n) \(n == 1 ? "round" : "rounds") in all",
                         "fatto: il primo giro da 18 buche si è chiuso \(day(first.day)); \(n) giri in tutto")
            }
            return L("today \(gems.today.count) holes of 18: the round finishes at the day's 18th estimate",
                     "oggi \(gems.today.count) buche su 18: il giro si chiude alla 18ª stima del giorno")
        case .streak(let n):
            return run(game.holes, n)
        case .kindStreak(let kind, let n):
            return run(game.holes.filter { $0.kind == kind }, n, kind: kind)
        case .roundChallenge:
            return t.progress
        case .roundMaxBogeys(let n):
            guard let r = bestRound(CampoGame.bogeys) else { return none }
            let b = CampoGame.bogeys(r.holes)
            return t.done ? L("done in round \(r.number) \(of(r.day)), with \(b) \(b == 1 ? "bogey" : "bogeys")",
                              "fatto nel giro \(r.number) \(of(r.day)), con \(b) bogey")
                : L("the best round (round \(r.number) \(of(r.day))) has \(b): it takes \(n == 0 ? "zero" : "\(n) or fewer") in 18 holes",
                    "il giro migliore (giro \(r.number) \(of(r.day))) ne ha \(b): ne servono \(n == 0 ? "zero" : "\(n) o meno") in 18 buche")
        case .roundNoQuickBogey:
            guard let r = bestRound(CampoEngine.quickBogeys) else { return none }
            let b = GameMood.current.bads(CampoEngine.quickBogeys(r.holes))
            return t.done ? L("done in round \(r.number) \(of(r.day))", "fatto nel giro \(r.number) \(of(r.day))")
                : L("the best round (round \(r.number) \(of(r.day))) has \(b) on quick tasks",
                    "il giro migliore (giro \(r.number) \(of(r.day))) ha \(b) sui quick")
        case .roundNoDisaster:
            guard let r = bestRound(CampoGame.disasters) else { return none }
            let d = CampoGame.disasters(r.holes)
            let worst = r.holes.filter(\.isDisaster).max { $0.real / $0.estimate < $1.real / $1.estimate }
            return t.done ? L("done in round \(r.number) \(of(r.day))", "fatto nel giro \(r.number) \(of(r.day))")
                : L("the best round (round \(r.number) \(of(r.day))) has \(d)", "il giro migliore (giro \(r.number) \(of(r.day))) ne ha \(d)")
                    + (worst.map { ": \(disaster($0))" } ?? "")
        case .roundToPar(let n):
            guard let r = bestRound(CampoEngine.toPar) else { return none }
            let p = CampoData.signed(CampoEngine.toPar(r.holes), par: true)
            return t.done ? L("done in round \(r.number) \(of(r.day)), at \(p)", "fatto nel giro \(r.number) \(of(r.day)), a \(p)")
                : L("the best round (round \(r.number) \(of(r.day))) is at \(p), it takes \(CampoData.signed(n)) or better",
                    "il giro migliore (giro \(r.number) \(of(r.day))) è a \(p), serve \(CampoData.signed(n)) o meglio")
        case .cleanRoundsInARow, .daysAtGoalInMonth:
            return t.progress
        case .daysAtGoal:
            return t.progress + L(" (only days with at least \(CampoCourse.workdayHoles) holes count)",
                                  " (contano i giorni con almeno \(CampoCourse.workdayHoles) buche)")
        }
    }

    /// The best run of gems, when it ended and how many of it were clean shots.
    private func run(_ holes: [CampoHole], _ n: Int, kind: String? = nil) -> String {
        var best = 0, bestEnd = -1, len = 0
        for (i, h) in holes.enumerated() {
            len = h.gem.isGem ? len + 1 : 0
            if len > best { best = len; bestEnd = i }
        }
        guard best > 0 else {
            let good = GameMood.current.good
            return kind.map { L("no \(good) on \($0) tasks yet", "ancora nessuna \(good) sui \($0)") } ?? L("no \(good) yet", "ancora nessuna \(good)")
        }
        let streak = holes[(bestEnd - best + 1)...bestEnd]
        let clean = streak.filter(\.isClean).count
        let when = day(streak[streak.endIndex - 1].end)
        if best >= n {
            return L("done: a record of \(best) in a row, ended \(when); \(clean) of \(best) were clean shots",
                     "fatto: record di \(best) di fila, finito \(when); \(clean) su \(best) erano colpi puliti")
        }
        return L("the record is \(best), ended \(when): \(n - best) more to reach \(n)",
                 "il record è \(best), finito \(when): ne mancano \(n - best) per arrivare a \(n)")
    }

    /// What to do for the trials still open: a sentence from the numbers, never generic.
    func tip(for hole: CampoGame.Hole) -> String? {
        let open = zip(hole.rule.trials, hole.trials).filter { !$0.1.done }.map { $0.0 }
        guard !open.isEmpty else { return nil }
        let p = pebbles
        let mood = GameMood.current
        func cleanLine(_ p: (clean: Double, other: Double, cleanShare: Double)) -> String {
            let clean = CampoData.percent(p.clean), other = CampoData.percent(p.other)
            return L("clean shots (a single turn, staying their kind) end as a \(mood.bad) \(clean)% of the time, the others \(other)%: one request, all written up front.",
                     "i colpi puliti (un turno solo, rimasti del loro tipo) finiscono in \(mood.bad) nel \(clean)% dei casi, gli altri nel \(other)%: una richiesta, scritta tutta all'inizio.")
        }
        for trial in open {
            switch trial {
            case .roundNoQuickBogey:
                let quick = game.holes.filter { $0.kind == "quick" }
                let many = quick.filter { $0.tools > 3 }
                if many.count >= 3 {
                    let share = CampoData.percent(Double(CampoGame.bogeys(many)) / Double(many.count))
                    return L("quick tasks with more than 3 tools end as a \(mood.bad) \(share)% of the time: if it takes more than 3 tools, it's a medium.",
                             "i quick con più di 3 strumenti finiscono in \(mood.bad) nel \(share)% dei casi: se servono più di 3 strumenti, è un medium.")
                }
            case .daysAtGoal, .daysAtGoalInMonth:
                if let p, p.other > p.clean {
                    return L("a day at 70% means 7 \(mood.goods) out of 10; ", "un giorno al 70% vuol dire 7 \(mood.goods) su 10; ") + cleanLine(p)
                }
                return L("a day at 70% means 7 \(mood.goods) out of 10, with at least \(CampoCourse.workdayHoles) holes.",
                         "un giorno al 70% vuol dire 7 \(mood.goods) su 10, con almeno \(CampoCourse.workdayHoles) buche.")
            case .roundNoDisaster, .cleanRoundsInARow:
                return L("a disaster is a task past 5 times the estimate: break big jobs into smaller steps.",
                         "un disastro è un task oltre 5 volte la stima: spezza i lavori grossi in passi più piccoli.")
            default:
                if let p, p.other - p.clean >= 0.15 { return cleanLine(p) }
            }
        }
        return nil
    }

    /// A power: on and which hole lit it, or which hole gives it.
    func why(_ power: CampoPower) -> String {
        let r = power.rule
        return isOn(power)
            ? L("\(r.power): lit by finishing hole \(r.number)\(power.built ? "" : ", still to be built in the app"). \(r.powerText)",
                "\(r.power): acceso dalla buca \(r.number) chiusa\(power.built ? "" : ", ancora da costruire nell'app"). \(r.powerText)")
            : L("\(r.power): lights up when you finish hole \(r.number) · \(r.title). \(r.powerText)",
                "\(r.power): si accende chiudendo la buca \(r.number) · \(r.title). \(r.powerText)")
    }

    /// A course of the mini golf: open, or how many holes played it still needs.
    func why(_ field: CampoMinigolf) -> String {
        if field.need == 0 { return L("\(field.name): open from the start.", "\(field.name): aperto da subito.") }
        return played >= field.need
            ? L("\(field.name): open, \(g(played)) of \(g(field.need)) holes played.", "\(field.name): aperto, \(g(played)) buche fatte su \(g(field.need)).")
            : L("\(field.name): \(g(played)) of \(g(field.need)) holes played, \(g(field.need - played)) to go. Every task with an estimate is a hole played, even a bogey.",
                "\(field.name): \(g(played)) buche fatte su \(g(field.need)), ne mancano \(g(field.need - played)). Ogni task con la stima è una buca fatta, anche un bogey.")
    }

    // MARK: helpers

    static func quickBogeys(_ r: [CampoHole]) -> Int { r.filter { $0.gem == .pebble && $0.kind == "quick" }.count }
    static func toPar(_ r: [CampoHole]) -> Int { r.reduce(0) { $0 + $1.toPar } }

    /// The first full round with the lowest score: the one the trial's "il migliore" speaks of.
    private func bestRound(_ score: ([CampoHole]) -> Int) -> CampoGame.Round? {
        var best: CampoGame.Round?
        for r in game.rounds where best == nil || score(r.holes) < score(best!.holes) { best = r }
        return best
    }

    private func disaster(_ h: CampoHole) -> String {
        let times = CampoData.grouped(safeInt((h.real / h.estimate).rounded()))
        return L("\(clock(h.real)) instead of \(clock(h.estimate)), \(times) times the estimate",
                 "\(clock(h.real)) invece di \(clock(h.estimate)), \(times) volte la stima")
    }

    private func clock(_ seconds: Double) -> String {
        seconds < 90 ? "\(safeInt(seconds.rounded())) s" : "\(safeInt((seconds / 60).rounded())) min"
    }

    /// "oggi" or "il 23/10"; of(): "di oggi" or "del 23/10". In English "today" or "on 23/10" for both.
    private func day(_ d: CampoGame.Day) -> String { on(d.ordinal, d.day, d.month) }
    private func of(_ d: CampoGame.Day) -> String {
        let dm = CampoData.dayMonth(d.day, d.month)
        return d.ordinal == game.today ? L("today", "di oggi") : L("on \(dm)", "del \(dm)")
    }

    private func day(_ ts: Double) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: ts))
        return on(CampoGame.ordinal(c.year ?? 1970, c.month ?? 1, c.day ?? 1), c.day ?? 1, c.month ?? 1)
    }

    private func on(_ ordinal: Int, _ day: Int, _ month: Int) -> String {
        let dm = CampoData.dayMonth(day, month)
        return ordinal == game.today ? L("today", "oggi") : L("on \(dm)", "il \(dm)")
    }

    private func g(_ n: Int) -> String { CampoData.grouped(n) }

    // MARK: the report

    /// `TaskETA --course-report`: where the user is, with every reason.
    var report: String {
        let mood = GameMood.current
        var out = [L("The Course, \(now.formatted(.dateTime.day().month(.twoDigits).hour().minute().locale(Loc.locale)))",
                     "Il campo, \(now.formatted(.dateTime.day().month(.twoDigits).hour().minute().locale(Loc.locale)))")]
        let gemShare = played == 0 ? 0 : CampoData.percent(Double(game.holes.filter(\.gem.isGem).count) / Double(played))
        out.append(L("- \(g(points)) points, \(g(played)) holes played, \(gemShare)% \(mood.goods), streak \(gems.streak) (record \(gems.bestStreak))",
                     "- \(g(points)) punti, \(g(played)) buche fatte, \(gemShare)% di \(mood.goods), serie \(gems.streak) (record \(gems.bestStreak))"))
        let closedList = closed.map { String($0.rule.number) }.joined(separator: ", ")
        out.append(L("- Title: ", "- Titolo: ") + (title ?? L("none", "nessuno")) + L("; holes done: ", "; buche chiuse: ")
                   + closedList.ifEmpty(L("none", "nessuna")))
        out.append(L("- Powers: ", "- Poteri: ") + powersText)
        for hole in course {
            out.append("- " + why(hole))
            if hole.rule.number - 1 == currentIndex {
                for (trial, t) in zip(hole.rule.trials, hole.trials) {
                    out.append("    \(t.done ? "✓" : "·") \(t.name): \(evidence(trial, t))")
                }
            }
        }
        if let next = current.flatMap({ CampoPower(rawValue: $0.rule.number) }) { out.append(L("- Next power: ", "- Prossimo potere: ") + why(next)) }
        out.append(L("- Mini golf: ", "- Minigolf: ") + CampoMinigolf.allCases.map { why($0) }.joined(separator: " "))
        if let p = pebbles {
            let share = CampoData.percent(p.cleanShare), clean = CampoData.percent(p.clean), other = CampoData.percent(p.other)
            out.append(L("- Clean shots: \(share)% of the holes; \(clean)% end as a \(mood.bad), against \(other)% of the others",
                         "- Colpi puliti: \(share)% delle buche; in \(mood.bad) \(clean)% contro \(other)% delle altre"))
        }
        out.append(L("- Claude plays: ", "- Claude gioca: ") + claude.line)
        out.append("  \(ClaudeScore.why)")
        return out.joined(separator: "\n")
    }
}

private extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}

// MARK: - one place to read it

/// The engine of the index on disk, made again only when the index or the hook's log changes (or
/// the day does): the mini golf reads its powers here when a game starts, the dashboard its card.
/// When only those change, the 1-2 MB index is parsed away from the main thread and the last engine
/// is returned meanwhile; `version` then tells the views to draw again. The first time, and on a
/// new language or mood (the engine's words), it is made at once. Called on the main thread.
final class CampoNow: ObservableObject, @unchecked Sendable {
    static let shared = CampoNow()
    private var words = ""
    private var stamps = ""
    private var cached: CampoEngine?
    /// The stamps of the engine being made in the background, if any.
    private var wanted = ""
    @Published private(set) var version = 0

    static var indexURL: URL { TaskStore.indexURL }

    func engine(_ index: URL = CampoNow.indexURL) -> CampoEngine {
        let offers = index.deletingLastPathComponent().appendingPathComponent("suggestions.jsonl")
        let w = "\(Loc.lang.rawValue)|\(GameMood.current.rawValue)"
        let s = "\(index.path)|\(fileStamp(index.path))|\(fileStamp(offers.path))|\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)"
        if let cached, w == words {
            if s != stamps, s != wanted {
                wanted = s
                DispatchQueue.global(qos: .userInitiated).async {
                    let engine = CampoEngine(PastTask.load(from: index), offers: HookOffer.load(offers))
                    DispatchQueue.main.async {
                        // A newer one on its way, or the words changed meanwhile: this one is dropped.
                        guard self.wanted == s, self.words == w else { return }
                        self.wanted = ""
                        self.stamps = s
                        self.cached = engine
                        self.version += 1
                    }
                }
            }
            return cached
        }
        let engine = CampoEngine(PastTask.load(from: index), offers: HookOffer.load(offers))
        words = w
        stamps = s
        wanted = ""
        cached = engine
        return engine
    }
}

// MARK: - in the dashboard

/// Il campo in the gems card: the hole being played, the mini golf and Claude's own score as three
/// numbers with their why, then the trials of the hole with their reasons. From CampoNow: two file
/// stamps per drawing, the index parsed again only when it changed.
struct CampoGameCard: View {
    @Environment(\.colorScheme) private var scheme
    /// Read so the card draws again when the mood changes: the engine's words follow it.
    @AppStorage(GameMood.key) private var moodRaw = GameMood.fallback.rawValue
    /// And when a new engine is ready.
    @ObservedObject private var campo = CampoNow.shared

    var body: some View {
        let _ = moodRaw
        let s = CampoStyle(scheme)
        VStack(alignment: .leading, spacing: 8) {
            Text(L("THE COURSE", "IL CAMPO")).campoEyebrow(s)
            content(CampoNow.shared.engine(), s)
        }
    }

    @ViewBuilder
    private func content(_ e: CampoEngine, _ s: CampoStyle) -> some View {
        let c = e.claude
        HStack(alignment: .top, spacing: 10) {
            CampoFigure(label: L("Hole in play", "Buca in corso"),
                        value: e.current.map { "\($0.rule.number) · \($0.rule.title)" } ?? L("course finished", "campo finito"),
                        why: (e.title.map { L("Title \($0), \(e.closed.count) of 9 holes done. ", "Titolo \($0), buche chiuse \(e.closed.count) di 9. ") }
                                ?? L("No holes done yet. ", "Nessuna buca chiusa. "))
                            + L("Powers: \(e.powersText).", "Poteri: \(e.powersText)."))
            CampoFigure(label: L("Mini golf", "Minigolf"),
                        value: e.nextField.map { L("\(CampoData.grouped(e.played)) of \(CampoData.grouped($0.need))",
                                                   "\(CampoData.grouped(e.played)) di \(CampoData.grouped($0.need))") } ?? L("all open", "tutti aperti"),
                        why: (e.nextField.map { L("holes played toward the \($0.name); ", "buche fatte verso il \($0.name); ") } ?? "")
                            + L("you play on: \(e.fields.map(\.name).joined(separator: ", "))", "si gioca su: \(e.fields.map(\.name).joined(separator: ", "))")
                            + (e.isOn(.strongClub) ? L(", with the power club (hole 4).", ", con la mazza forte (buca 4).") : "."))
            CampoFigure(label: L("Claude plays too", "Anche Claude gioca"),
                        value: c.marks.isEmpty ? "–" : L("\(c.inside) of \(c.last.count)", "\(c.inside) su \(c.last.count)"),
                        why: c.marks.isEmpty ? L("no estimates to count yet", "ancora nessuna stima da contare")
                            : L("last \(c.last.count) estimates: \(c.counts), against the hook's range; streak \(c.streak), record \(c.best)",
                                "stime nelle ultime \(c.last.count): \(c.counts), contro la forchetta dell'hook; serie \(c.streak), record \(c.best)"),
                        accent: !c.marks.isEmpty && Double(c.inside) >= 0.7 * Double(c.last.count) ? s.done : nil)
        }
        .fixedSize(horizontal: false, vertical: true)
        if let hole = e.current {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("Hole \(hole.rule.number) · \(hole.rule.title), \(hole.rule.zone)", "Buca \(hole.rule.number) · \(hole.rule.title), \(hole.rule.zone)"))
                    .font(CampoFont.display(15)).foregroundStyle(s.ink)
                if hole.rule.green > e.points {
                    Text(L("Green at \(CampoData.grouped(hole.rule.green)) points: \(CampoData.grouped(hole.rule.green - e.points)) to go.",
                           "Green a \(CampoData.grouped(hole.rule.green)) punti: ne mancano \(CampoData.grouped(hole.rule.green - e.points))."))
                        .font(CampoFont.text(11.5)).foregroundStyle(s.ink)
                }
                ForEach(Array(zip(hole.rule.trials, hole.trials).enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(pair.1.done ? L("done", "fatta") : L("to do", "da fare")).font(CampoFont.display(11, .semibold))
                            .foregroundStyle(pair.1.done ? s.done : s.muted).frame(width: 46, alignment: .leading)
                        Text(verbatim: "\(pair.1.name): \(e.evidence(pair.0, pair.1))")
                            .font(CampoFont.text(11.5)).foregroundStyle(s.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let tip = e.tip(for: hole) {
                    Text(L("What to do: ", "Cosa fare: ") + tip).font(CampoFont.text(11)).foregroundStyle(s.muted).fixedSize(horizontal: false, vertical: true)
                }
                if let next = CampoPower(rawValue: hole.rule.number) {
                    Text(L("Finish the hole and \(next.name) lights up. \(next.rule.powerText)",
                           "Chiusa la buca si accende \(next.name). \(next.rule.powerText)"))
                        .font(CampoFont.text(11)).foregroundStyle(s.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(11).frame(maxWidth: .infinity, alignment: .leading).campoPaper(s)
        }
        Text(ClaudeScore.why).font(CampoFont.text(11)).foregroundStyle(s.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - selftest

enum CampoEngineTest {
    /// The engine's checks, for `--selftest`: the failures, empty when all pass.
    static func failures() -> [String] {
        var out: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { out.append(what) } }

        // The powers line up with the holes of Campo.swift.
        Loc.testing(.it) {
            check(CampoPower.allCases.count == CampoCourse.rules.count && CampoPower.strongClub.name == "Mazza forte"
                  && CampoPower.doubleHole.name == "Buca doppia" && CampoPower.greenJacket.name == "Giacca verde", "campo powers")
        }
        Loc.testing(.en) {
            check(CampoPower.strongClub.name == "Power club" && CampoCourse.rules[0].title == "Beginner"
                  && CampoCourse.rules[0].zone == "The Gardens Lawn", "campo powers (en)")
        }

        // A morning of 18 holes, each estimate 300 s: 12 gems in a row, then pebbles.
        let cal = Calendar.current
        let morning = cal.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 8))?.timeIntervalSince1970 ?? 0
        func task(_ i: Int, real: Double, kind: String = "quick", tools: Int = 2, segments: Int = 1, session: String = "s",
                  interrupted: Bool = false, day: Double = 0) -> PastTask {
            PastTask(id: "e\(i)-\(day)", start: morning + day * 86400 + Double(i) * 600, real: real, estimate: 300, range: (200, 450),
                     model: "opus-5-5", project: "demo", prompt: "", session: session, kind: kind,
                     interrupted: interrupted, segments: segments, tools: tools)
        }
        let round = (0..<18).map { i in task(i, real: i < 12 ? 300 : 2000, tools: i < 12 ? 2 : 9) }
        // The engine keeps its trials' words: made in the language of the checks.
        let e = Loc.testing(.it) { CampoEngine(round, now: Date(timeIntervalSince1970: morning + 86400)) }
        check(e.played == 18 && e.closed.map(\.rule.number) == [1, 2] && e.currentIndex == 2 && e.title == "Caddie",
              "campo engine holes: \(e.closed.map(\.rule.number))")
        check(e.fields == [.prato] && e.nextField == .ghiaccio, "campo engine fields")
        Loc.testing(.it) {
            check(e.powersOn == [.fairway, .caddie] && !e.isOn(.strongClub)
                  && e.powersText == "Fairway; vinti, ancora da costruire: Il consiglio del caddie", "campo engine powers: \(e.powersText)")
            let one = e.why(e.course[0]), two = e.why(e.course[1]), three = e.why(e.course[2])
            check(one.hasPrefix("Buca 1 chiusa:") && one.contains("20/10") && one.hasSuffix("Potere: Fairway."), "why hole 1: \(one)")
            check(two.contains("record di 12 di fila") && two.contains("12 su 12 erano colpi puliti"), "why hole 2: \(two)")
            check(three.hasPrefix("Buca 3 in corso:") && three.contains("ne mancano"), "why hole 3: \(three)")
            // The evidence speaks of the same round as Campo.swift's progress.
            let four = e.course[3]
            if case .roundMaxBogeys = four.rule.trials[1] {
                let ev = e.evidence(four.rule.trials[1], four.trials[1])
                check(ev.contains("ne ha 6") && four.trials[1].progress == "il migliore ne ha 6", "why bogeys: \(ev) / \(four.trials[1].progress)")
            } else {
                out.append("hole 4's second trial moved")
            }
        }
        Loc.testing(.en) {
            let en = CampoEngine(round, now: Date(timeIntervalSince1970: morning + 86400))
            check(en.powersText == "Fairway; won, still to be built: The caddie's tip", "campo engine powers (en): \(en.powersText)")
            let two = en.why(en.course[1]), three = en.why(en.course[2])
            check(two.hasPrefix("Hole 2 done:") && two.contains("a record of 12 in a row") && two.contains("12 of 12 were clean shots"),
                  "why hole 2 (en): \(two)")
            check(three.hasPrefix("Hole 3 in play:") && three.contains("to go"), "why hole 3 (en): \(three)")
            check(en.course[3].trials[1].progress == "the best one has 6", "why bogeys (en): \(en.course[3].trials[1].progress)")
        }
        // Clean shots against the rest: 0 of 12 pebbles against 6 of 6.
        check(e.pebbles.map { $0.clean == 0 && $0.other == 1 } ?? false, "campo clean shots")

        // The courses of the mini golf open at 200 and 888 holes played.
        let many = (0..<200).map { i in task(i % 100, real: 300, day: Double(i / 100) + 2) }
        check(CampoEngine(Array(many.prefix(199))).fields == [.prato], "199 holes: lawn only")
        check(CampoEngine(many).fields == [.prato, .ghiaccio] && CampoEngine(many).nextField == .biliardo, "200 holes: ice")

        // Claude's score: against the hook's own offer, never the range Claude wrote.
        let t0 = morning
        let offers: [String: [HookOffer]] = ["c": (0..<6).map { i -> HookOffer in
            let kinds: [String: HookOffer.Line] = ["quick": (300, 200, 450), "agents": (2000, nil, nil)]
            let brief: HookOffer.Line? = i == 5 ? (600, 400, 900) : nil
            return HookOffer(ts: t0 + Double(i) * 600 + 0.3, kinds: kinds, brief: brief)
        }]
        func ct(_ i: Int, real: Double, kind: String = "quick", interrupted: Bool = false, est: Double = 300) -> PastTask {
            PastTask(id: "c\(i)", start: t0 + Double(i) * 600, real: real, estimate: est, range: (0, 99_999), model: "m",
                     project: "p", prompt: "", session: "c", kind: kind, interrupted: interrupted)
        }
        let cs = ClaudeScore([ct(0, real: 310), ct(1, real: 420), ct(2, real: 1000), ct(3, real: 100),
                              ct(4, real: 60, interrupted: true), ct(5, real: 650, kind: "agents", est: 600)], offers: offers)
        // 310: hit; 420: inside; 1000: too short though Claude wrote 0 to 99999; 100: too long;
        // the stopped one is not scored; the brief subagents line is the one Claude copied.
        check(cs.marks == [.hit, .inside, .short, .long, .inside], "claude marks: \(cs.marks)")
        check(cs.inside == 3 && cs.hits == 1 && cs.short == 1 && cs.long == 1 && cs.streak == 1, "claude counts")
        check(ClaudeScore(marks: Array(repeating: .inside, count: 15) + Array(repeating: .short, count: 10)).best == 15
              && ClaudeScore(marks: Array(repeating: .inside, count: 15) + Array(repeating: .short, count: 10)).streak == 0, "claude best")
        check(ClaudeScore.mark(real: 330, (300, nil, nil)) == .inside && ClaudeScore.mark(real: 451, (300, nil, nil)) == .short
              && ClaudeScore.mark(real: 323, (300, 200, 450)) == .hit && ClaudeScore.mark(real: 15, (10, 5, 12)) == .hit, "claude mark")
        let line = Data("""
        {"ts": 1.5, "session": "a", "kinds": {"quick": [29, 19, 45], "agents": [2041, null, null]}, "brief": null, "model": "claude-opus-5-5"}
        not json
        {"ts": 2, "session": "a", "kinds": {"medium": [120, 60, "x"]}}
        """.utf8)
        let parsed = HookOffer.parse(line)["a"] ?? []
        check(parsed.count == 2 && parsed[0].kinds["quick"]?.low == 19 && parsed[0].kinds["agents"]?.low == nil
              && parsed[1].kinds["medium"]?.est == 120 && parsed[1].kinds["medium"]?.high == nil
              && parsed[0].model == "claude-opus-5-5" && parsed[1].model == nil, "hook offers parse")
        // An offer made for another model is not the task's, and no other offer takes its place;
        // "claude-" in front does not make it another model.
        func offer(_ ts: Double, _ model: String?) -> HookOffer { HookOffer(ts: t0 + ts, kinds: ["quick": (300, 200, 450)], brief: nil, model: model) }
        let opus = PastTask(id: "m0", start: t0, real: 310, estimate: 300, range: nil, model: "opus-5-5 high",
                            project: "p", prompt: "", session: "m", kind: "quick")
        check(ClaudeScore([opus], offers: ["m": [offer(0.3, "claude-sonnet-5"), offer(5, "claude-opus-5-5")]]).marks.isEmpty
              && ClaudeScore([opus], offers: ["m": [offer(0.3, "claude-opus-5-5")]]).marks == [.hit]
              && ClaudeScore([opus], offers: ["m": [offer(0.3, nil)]]).marks == [.hit], "claude offer of another model")
        return out
    }
}
