import AppKit
import SwiftUI
import WebKit

// "Il campo": the estimates game as a park of mini golf, in the
// dashboard. The page is the published map's (campo/il-campo.html, copied into Resources by
// build.sh) in a web view made when the widget appears and freed when the dashboard closes; the
// app gives it its own numbers in window.CAMPO_DATA. The rules of the 9 holes are
// below. Nothing is saved.

// MARK: - the rules

/// A hole of the game as the course reads it: a finished task with Claude's estimate.
struct CampoHole {
    let end: Double
    let real: Double
    let estimate: Double
    let gem: Gem
    let kind: String?
    let segments: Int
    let tools: Int

    var toPar: Int { CampoHole.toPar(gem) }

    /// Strokes against par: a diamond is an eagle, a pebble a bogey.
    static func toPar(_ gem: Gem) -> Int {
        switch gem {
        case .diamond: return -2
        case .sapphire: return -1
        case .emerald: return 0
        case .pebble: return 1
        }
    }

    var isDisaster: Bool { real > CampoCourse.disaster * estimate }
    /// The clean shot: one turn only, and the task stayed its kind (quick up to 3 tools, medium 15).
    var isClean: Bool { segments == 1 && !(kind == "quick" && tools > 3) && !(kind == "medium" && tools > 15) }
}

enum CampoTrial {
    case firstRound
    case streak(Int)
    case kindStreak(String, Int)
    case roundChallenge
    case roundMaxBogeys(Int)
    case roundNoQuickBogey
    case roundNoDisaster
    case roundToPar(Int)
    case cleanRoundsInARow(Int)
    case daysAtGoal(Int)
    case daysAtGoalInMonth(Int)
}

/// The 9 holes: the levels of the gems, each with its trials and the power it lights.
enum CampoCourse {
    struct Rule {
        let number: Int
        let title: String
        let zone: String
        let green: Int
        let trials: [CampoTrial]
        /// The power: its name, what it changes, whether the app has it already, and in words.
        let power: String
        let powerKind: String
        let powerIsNew: Bool
        let powerText: String
    }

    static let goal = 0.7          // a day "al 70%": at least 70% gems
    static let workdayHoles = 10   // shorter days do not count, and do not break a run of days
    static let disaster = 5.0      // real past 5 times the estimate
    static let round = 18
    /// The holes played that open the mini golf's courses (the lawn is open from the start).
    static let ice = 200
    static let pool = 888

    /// Computed: the titles and powers are display text and follow a language switch.
    static var rules: [Rule] {
        let gardens = L("The Gardens Lawn", "Il Pratone dei Gardens")
        let widget = "widget"
        let help = L("help", "aiuto")
        let estimates = L("estimates", "stime")
        return [
            Rule(number: 1, title: L("Beginner", "Principiante"), zone: gardens, green: 0, trials: [.firstRound],
                 power: "Fairway", powerKind: widget, powerIsNew: false,
                 powerText: L("The iPhone widget in lawn green. For now it's won at 10,000 points.",
                              "Il widget dell'iPhone in verde prato. Oggi si vince a 10.000 punti.")),
            Rule(number: 2, title: "Caddie", zone: gardens, green: 4_000, trials: [.streak(5)],
                 power: L("The caddie's tip", "Il consiglio del caddie"), powerKind: help, powerIsNew: true,
                 powerText: L("Every new round, a line of advice in the panel and the widget: “if it takes more than 3 tools, ask for medium”.",
                              "A ogni nuovo giro, una riga di consiglio nel pannello e nel widget: «se servono più di 3 strumenti, chiedi medium».")),
            Rule(number: 3, title: L("Amateur", "Dilettante"), zone: gardens, green: 10_000, trials: [.roundChallenge],
                 power: "Mulligan", powerKind: estimates, powerIsNew: true,
                 powerText: L("Once a day, the first bogey doesn't break the streak. It kicks in by itself if the streak is at least 3.",
                              "Una volta al giorno il primo bogey non rompe la serie. Si usa da solo, se la serie è almeno di 3.")),
            Rule(number: 4, title: "Handicap 18", zone: "Blue Lake", green: 20_000, trials: [.streak(10), .roundMaxBogeys(3)],
                 power: L("Power club", "Mazza forte"), powerKind: L("mini golf", "minigolf"), powerIsNew: true,
                 powerText: L("In the mini golf, longer shots and more cushions, on lawn, ice and billiards.",
                              "Nel minigolf tiri più lunghi e più sponde, su prato, ghiaccio e biliardo.")),
            Rule(number: 5, title: "Handicap 9", zone: "Blue Lake", green: 40_000, trials: [.daysAtGoal(3), .roundNoQuickBogey],
                 power: L("Night golf", "Golf di notte"), powerKind: widget, powerIsNew: false,
                 powerText: L("The night widget.", "Il widget notturno.")),
            Rule(number: 6, title: "Scratch", zone: "Blue Lake", green: 75_000, trials: [.streak(15), .roundNoDisaster],
                 power: L("Double hole", "Buca doppia"), powerKind: estimates, powerIsNew: true,
                 powerText: L("In every round one hole counts double, and you know which from the start.",
                              "In ogni giro una buca vale doppio, e sai quale dall'inizio.")),
            Rule(number: 7, title: "Pro", zone: "Monte Donato", green: 125_000,
                 trials: [.streak(20), .daysAtGoal(5), .roundMaxBogeys(1)],
                 power: L("Trophy", "Trofeo"), powerKind: widget, powerIsNew: false,
                 powerText: L("The gold widget.", "Il widget oro.")),
            Rule(number: 8, title: L("Champion", "Campione"), zone: "Monte Donato", green: 200_000,
                 trials: [.kindStreak("medium", 10), .roundToPar(-15), .cleanRoundsInARow(2)],
                 power: "Eagle", powerKind: estimates, powerIsNew: true,
                 powerText: L("A spot-on estimate on a medium or long task is worth 500 points instead of 300.",
                              "Una stima centrata su un task medium o long vale 500 punti invece di 300.")),
            Rule(number: 9, title: L("Legend of the green", "Leggenda del green"), zone: "Monte Donato", green: 300_000,
                 trials: [.streak(25), .roundMaxBogeys(0), .daysAtGoalInMonth(20)],
                 power: L("Green jacket", "Giacca verde"), powerKind: L("look", "aspetto"), powerIsNew: true,
                 powerText: L("The whole app in green and gold, the season's trophy board, and Season 2 opens.",
                              "Tutta l'app in verde e oro, la bacheca della stagione, e si apre la Stagione 2.")),
        ]
    }
}

/// Where the game is: the course worked out from the index in one pass.
struct CampoGame {
    struct Trial {
        let done: Bool
        let name: String
        let progress: String
        /// Some way done (a record, some days): the map shows it half full on the hole being played.
        let started: Bool
    }

    struct Hole {
        let rule: CampoCourse.Rule
        let closed: Bool
        let trials: [Trial]
    }

    /// A local day, numbered as Python's date.toordinal(): the challenge of a round is picked by it.
    struct Day {
        let ordinal: Int
        let day: Int
        let month: Int
        var holes: [CampoHole]
    }

    struct Round {
        let day: Day
        let number: Int
        let holes: [CampoHole]
    }

    let holes: [CampoHole]   // by start, oldest first
    let points: Int
    let days: [Day]
    /// Only the full rounds of 18, day by day.
    let rounds: [Round]
    let workdays: [(day: Day, share: Double)]
    let today: Int

    init(_ tasks: [PastTask], points: Int, now: Date = Date()) {
        self.points = points
        holes = tasks.sorted { $0.start < $1.start }.compactMap { t in
            guard let estimate = t.estimate, let outcome = t.outcome else { return nil }
            return CampoHole(end: t.start + t.real, real: t.real, estimate: estimate, gem: Gem(outcome), kind: t.kind,
                             segments: t.segments, tools: t.tools)
        }
        let calendar = Calendar.current
        func day(_ ts: Double) -> (ordinal: Int, day: Int, month: Int) {
            let c = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: ts))
            return (CampoGame.ordinal(c.year ?? 1970, c.month ?? 1, c.day ?? 1), c.day ?? 1, c.month ?? 1)
        }
        var days: [Day] = []
        var at: [Int: Int] = [:]
        for h in holes {
            let d = day(h.end)
            if let i = at[d.ordinal] {
                days[i].holes.append(h)
            } else {
                at[d.ordinal] = days.count
                days.append(Day(ordinal: d.ordinal, day: d.day, month: d.month, holes: [h]))
            }
        }
        self.days = days
        rounds = days.flatMap { d in
            stride(from: 0, to: d.holes.count, by: CampoCourse.round).compactMap { i -> Round? in
                let chunk = Array(d.holes[i..<min(i + CampoCourse.round, d.holes.count)])
                return chunk.count == CampoCourse.round ? Round(day: d, number: i / CampoCourse.round + 1, holes: chunk) : nil
            }
        }
        workdays = days.filter { $0.holes.count >= CampoCourse.workdayHoles }
            .map { ($0, Double($0.holes.filter(\.gem.isGem).count) / Double($0.holes.count)) }
        today = day(now.timeIntervalSince1970).ordinal
    }

    /// The holes in order: a hole closes with its green reached and all its trials, after the one before.
    func course() -> [Hole] {
        var out: [Hole] = []
        var open = true
        for rule in CampoCourse.rules {
            let trials = rule.trials.map(evaluate)
            let closed = open && points >= rule.green && trials.allSatisfy(\.done)
            out.append(Hole(rule: rule, closed: closed, trials: trials))
            open = closed
        }
        return out
    }

    private func evaluate(_ trial: CampoTrial) -> Trial {
        let full = rounds.map(\.holes)
        let none = L("no round finished", "nessun giro chiuso")
        let goods = GameMood.current.goods
        func bestHas(_ n: Int) -> String { L("the best one has \(n)", "il migliore ne ha \(n)") }
        func record(_ n: Int) -> String { L("the record is \(n)", "il record è \(n)") }
        switch trial {
        case .firstRound:
            return Trial(done: !full.isEmpty, name: L("finish your first round of 18 holes", "chiudi il primo giro da 18 buche"),
                         progress: L(full.count == 1 ? "1 round finished" : "\(full.count) rounds finished", "\(full.count) giri chiusi"),
                         started: false)
        case .streak(let n):
            let best = CampoGame.bestRun(holes) { $0.gem.isGem }
            return Trial(done: best >= n, name: L("\(n) \(goods) in a row", "\(n) \(goods) di fila"), progress: record(best), started: best > 0)
        case .kindStreak(let kind, let n):
            let best = CampoGame.bestRun(holes.filter { $0.kind == kind }) { $0.gem.isGem }
            return Trial(done: best >= n, name: L("\(n) \(goods) in a row on \(kind) tasks", "\(n) \(goods) di fila sui \(kind)"),
                         progress: record(best), started: best > 0)
        case .roundChallenge:
            let won = rounds.filter(challengeMet).count
            return Trial(done: won > 0, name: L("win a round challenge", "vinci una sfida del giro"),
                         progress: L("\(won) \(won == 1 ? "challenge" : "challenges") won in \(full.count) \(full.count == 1 ? "round" : "rounds")",
                                     "\(won) sfide vinte su \(full.count) giri"),
                         started: false)
        case .roundMaxBogeys(let n):
            let best = full.map(CampoGame.bogeys).min()
            return Trial(done: best.map { $0 <= n } ?? false,
                         name: n == 0 ? L("a round with no bogeys", "un giro senza bogey")
                             : L("a round with \(n) \(n == 1 ? "bogey" : "bogeys") or fewer", "un giro con \(n) bogey o meno"),
                         progress: best.map(bestHas) ?? none, started: false)
        case .roundNoQuickBogey:
            let best = full.map { $0.filter { $0.gem == .pebble && $0.kind == "quick" }.count }.min()
            return Trial(done: best == 0, name: L("a round with no bogeys on quick tasks", "un giro senza bogey sui quick"),
                         progress: best.map(bestHas) ?? none, started: false)
        case .roundNoDisaster:
            let best = full.map(CampoGame.disasters).min()
            return Trial(done: best == 0, name: L("a round with no disasters", "un giro senza disastri"),
                         progress: best.map(bestHas) ?? none, started: false)
        case .roundToPar(let n):
            let best = full.map { $0.reduce(0) { $0 + $1.toPar } }.min()
            return Trial(done: best.map { $0 <= n } ?? false,
                         name: L("a round at \(CampoData.signed(n)) or better", "un giro a \(CampoData.signed(n)) o meglio"),
                         progress: best.map { L("the best one is \(CampoData.signed($0))", "il migliore è \(CampoData.signed($0))") } ?? none,
                         started: false)
        case .cleanRoundsInARow(let n):
            let best = CampoGame.bestRun(full) { CampoGame.disasters($0) == 0 }
            return Trial(done: best >= n, name: L("\(n) rounds in a row with no disasters", "\(n) giri di fila senza disastri"),
                         progress: record(best), started: best > 0)
        case .daysAtGoal(let n):
            let best = CampoGame.bestRun(workdays) { $0.share >= CampoCourse.goal }
            let last = workdays.suffix(n).map { d in
                "\(d.day.ordinal == today ? L("today", "oggi") : CampoData.dayMonth(d.day.day, d.day.month)) \(CampoData.percent(d.share))%"
            }
            return Trial(done: best >= n, name: L("\(n) days in a row at 70%", "\(n) giorni di fila al 70%"),
                         progress: L("\(min(best, n)) of \(n)", "\(min(best, n)) di \(n)") + (last.isEmpty ? "" : ": " + last.joined(separator: ", ")),
                         started: best > 0)
        case .daysAtGoalInMonth(let n):
            var best = 0
            for d in workdays {
                best = max(best, workdays.filter { $0.share >= CampoCourse.goal && d.day.ordinal <= $0.day.ordinal && $0.day.ordinal < d.day.ordinal + 30 }.count)
            }
            return Trial(done: best >= n, name: L("\(n) days at 70% in a month", "\(n) giorni al 70% in un mese"),
                         progress: L("the most in 30 days is \(best)", "il massimo in 30 giorni è \(best)"), started: best > 0)
        }
    }

    /// The challenge of a full round: one of six, picked by the day and the round's number.
    private func challengeMet(_ r: Round) -> Bool {
        let h = r.holes
        switch (r.day.ordinal * 7 + r.number) % 6 {
        case 0: return h.filter { $0.gem == .diamond }.count >= 5
        case 1: return CampoGame.bestRun(h) { $0.gem.isGem } >= 8
        case 2: return CampoGame.bogeys(h) <= 3
        case 3: return CampoGame.disasters(h) == 0
        case 4: return h.contains { $0.gem == .sapphire && $0.kind == "medium" }
        default: return h.reduce(0) { $0 + $1.toPar } <= -6
        }
    }

    static func bogeys(_ r: [CampoHole]) -> Int { r.filter { $0.gem == .pebble }.count }
    static func disasters(_ r: [CampoHole]) -> Int { r.filter(\.isDisaster).count }

    static func bestRun<T>(_ seq: [T], _ ok: (T) -> Bool) -> Int {
        var best = 0, run = 0
        for x in seq {
            run = ok(x) ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    /// Days since 1 January of year 1, as Python's date.toordinal() (proleptic Gregorian).
    static func ordinal(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468 + 719_163
    }
}

// MARK: - the numbers for the page

/// window.CAMPO_DATA: the same shape as DATA at the top of the page's script.
struct CampoData: Encodable {
    struct Round: Encodable { let n: Int; let holes: Int; let toPar: String }
    struct Hole: Encodable { let n: Int; let t: String; let z: String; let g: Int; let s: String; let tr: [[String]]; let pw: [String] }
    struct Phone: Encodable { let synced: String?; let note: String }
    struct Claude: Encodable {
        /// n: the estimates scored in the last 18 (fewer at the start).
        let n, inside, hit, short, long, run, bestRun, best, share, shortAll, longAll: Int
        let trend: String
    }

    let at: String
    let atShort: String
    let points: Int
    let played: Int
    let title: String
    let streak: Int
    let best: Int
    let round: Round
    let nowHole: Int
    let prevGreen: Int
    let holes: [Hole]
    let ice = CampoCourse.ice
    let pool = CampoCourse.pool
    let clean: Int
    let doom: String
    let restart: Int
    let phone: Phone
    let ai: Claude
    let eta: String?
    let embed = true
    /// The game's mood: the page names and draws the results the same way (GameMood.swift).
    let mood = GameMood.current == .minigolf ? "minigolf" : "gemme"   // the map knows golf and gems
    /// The language of the texts above: the page writes its own words in it ("en" or "it").
    let lang = Loc.lang.rawValue
    /// The scooter at its place at once, with no ride (the snapshot).
    var still = false

    var json: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    static func make(_ tasks: [PastTask], golf: [GolfRecord], phone: Phone, offers: [String: [HookOffer]] = [:],
                     now: Date = Date()) -> CampoData {
        let gems = GemStats(tasks, now: now)
        let game = CampoGame(tasks, points: gems.points, now: now)
        let course = game.course()
        let closed = course.filter(\.closed)
        let nowIndex = course.firstIndex { !$0.closed }
        // The course finished: the 9th stays the hole shown, its way full from the 8th's green.
        let current = nowIndex ?? course.count - 1
        let prevGreen = current > 0 ? course[current - 1].rule.green : 0
        let holes = course.enumerated().map { i, h -> Hole in
            let state = h.closed ? "done" : i == nowIndex ? "now" : "todo"
            return Hole(n: h.rule.number, t: h.rule.title, z: h.rule.zone, g: h.rule.green, s: state,
                        tr: h.trials.map { [$0.done ? "ok" : state == "now" && $0.started ? "part" : "no", capitalized($0.name), $0.progress] },
                        pw: [h.rule.power, h.rule.powerKind, h.rule.powerIsNew ? "new" : "old", h.rule.powerText])
        }
        let played = game.holes.count
        let round = gems.round

        // The mini golf of the last 7 days: the minutes away from the phone.
        let week = golf.filter { $0.start >= now.timeIntervalSince1970 - 7 * 86400 }
        let minutes = safeInt((week.reduce(0) { $0 + $1.seconds } / 60).rounded())
        let doom = week.isEmpty ? L("no games this week", "nessuna partita questa settimana")
            : L("\(minutes < 1 ? "less than a minute" : minutes == 1 ? "1 minute" : "\(minutes) minutes") in \(week.count) \(week.count == 1 ? "game" : "games") this week",
                "\(minutes < 1 ? "meno di un minuto" : minutes == 1 ? "1 minuto" : "\(minutes) minuti") in \(week.count) \(week.count == 1 ? "partita" : "partite") questa settimana")

        let time = now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Loc.locale))
        let date = now.formatted(.dateTime.day().month(.wide).locale(Loc.locale))
        // atShort follows "Numbers " / "Numeri " on the page: "Numbers as of 16:44."
        return CampoData(at: L("\(date) at \(time)", "\(date) alle \(time)"), atShort: L("as of \(time)", "delle \(time)"),
                         points: gems.points, played: played, title: closed.last?.rule.title ?? L("No title", "Senza titolo"),
                         streak: gems.streak, best: gems.bestStreak,
                         round: Round(n: round.number, holes: round.holes.count,
                                      toPar: signed(round.holes.reduce(0) { $0 + CampoHole.toPar($1.gem) }, par: true)),
                         nowHole: current + 1, prevGreen: prevGreen, holes: holes,
                         clean: played == 0 ? 0 : percent(Double(game.holes.filter(\.isClean).count) / Double(played)),
                         doom: doom, restart: restartShare(tasks), phone: phone, ai: claude(ClaudeScore(tasks, offers: offers)),
                         eta: eta(gems, green: nowIndex.map { course[$0].rule } , now: now))
    }

    /// Claude's own score on its estimates, the same as the dashboard's card (ClaudeScore: against
    /// the range the hook offered): inside it (spot on included), too short, too long, the last 18 and in all.
    static func claude(_ score: ClaudeScore) -> Claude {
        let marks = score.marks
        let n = Double(max(marks.count, 1))
        let half = marks.count / 2
        let first = marks.prefix(half), second = marks.dropFirst(half)
        func share(_ s: ArraySlice<ClaudeScore.Mark>) -> Int { s.isEmpty ? 0 : percent(Double(s.filter(\.isInside).count) / Double(s.count)) }
        return Claude(n: score.last.count, inside: score.inside, hit: score.hits, short: score.short, long: score.long,
                      run: score.streak, bestRun: CampoGame.bestRun(marks) { $0.isInside }, best: score.best,
                      share: percent(Double(marks.filter(\.isInside).count) / n),
                      shortAll: percent(Double(marks.filter { $0 == .short }.count) / n),
                      longAll: percent(Double(marks.filter { $0 == .long }.count) / n),
                      trend: L("from \(share(first))% to \(share(second))%", "dal \(share(first))% al \(share(second))%"))
    }

    /// The next prompt in the same session within a minute of the end: you were there when Claude finished.
    static func restartShare(_ tasks: [PastTask]) -> Int {
        var bySession: [String: [PastTask]] = [:]
        for t in tasks { if let s = t.session { bySession[s, default: []].append(t) } }
        var gaps = 0, quick = 0
        for list in bySession.values {
            let sorted = list.sorted { $0.start < $1.start }
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                gaps += 1
                if b.start - (a.start + a.real) <= 60 { quick += 1 }
            }
        }
        return gaps == 0 ? 0 : percent(Double(quick) / Double(gaps))
    }

    /// When the green of the hole being played comes, at the pace of the last 7 days.
    static func eta(_ gems: GemStats, green rule: CampoCourse.Rule?, now: Date) -> String? {
        guard let rule else { return L("Course finished: you're a Legend of the green.", "Campo finito: sei Leggenda del green.") }
        let missing = rule.green - gems.points
        guard missing > 0 else {
            return L("Hole \(rule.number)'s green is reached: now the trials decide.", "Il green della \(rule.number) è raggiunto: ora decidono le prove.")
        }
        let week = gems.holes.filter { $0.end >= now.timeIntervalSince1970 - 7 * 86400 }.reduce(0) { $0 + $1.points }
        guard week > 0 else {
            return L("No points in the last 7 days: hole \(rule.number)'s green is waiting.",
                     "Negli ultimi 7 giorni nessun punto: il green della \(rule.number) aspetta.")
        }
        let perDay = Double(week) / 7
        let days = Double(missing) / perDay
        let when = days < 1 ? L("less than a day", "meno di un giorno") : days < 1.5 ? L("about a day", "circa un giorno")
            : L("about \(safeInt(days.rounded())) days", "circa \(safeInt(days.rounded())) giorni")
        let pace = grouped(safeInt(perDay.rounded()))
        return L("At the pace of the last 7 days, \(pace) points a day, hole \(rule.number)'s green comes in \(when); from there on, the trials decide.",
                 "Al ritmo degli ultimi 7 giorni, \(pace) punti al giorno, il green della \(rule.number) arriva in \(when); da lì in poi decidono le prove.")
    }

    /// −6, par, +2: with the minus of print, as on the map.
    static func signed(_ n: Int, par: Bool = false) -> String {
        n < 0 ? "−\(-n)" : n == 0 && par ? "par" : n == 0 ? "0" : "+\(n)"
    }

    /// Rounded as Python's round(): half to even.
    static func percent(_ share: Double) -> Int { safeInt((share * 100).rounded(.toNearestOrEven)) }

    /// "12,345" or "12.345".
    static func grouped(_ n: Int) -> String { Loc.integer(n) }

    /// A day of the year as the language writes it: "23/10" in Italian, "23/10" or "10/23" in English
    /// (the Mac's own English).
    static func dayMonth(_ day: Int, _ month: Int) -> String {
        guard Loc.lang != .it else { return "\(day)/\(month)" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Loc.locale
        guard let date = calendar.date(from: DateComponents(year: 2000, month: month, day: day)) else { return "\(day)/\(month)" }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Loc.locale
        f.setLocalizedDateFormatFromTemplate("dM")
        return f.string(from: date)
    }

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}

extension CampoData.Phone {
    /// The iPhone widget: when the app last wrote its script to iCloud Drive, or that it is off.
    static func current(now: Date = Date()) -> CampoData.Phone {
        guard SettingsController.shared.prefs?.phoneOn ?? UserDefaults.standard.bool(forKey: "phoneOn") else {
            return .init(synced: nil, note: L("The widget is off: turn it on in TaskETA's Settings, under iPhone.",
                                              "Il widget è spento: si accende nelle impostazioni di TaskETA, alla voce iPhone."))
        }
        let script = PhoneScript.iCloudFolder.appendingPathComponent("TaskETA.js")
        guard let date = (try? FileManager.default.attributesOfItem(atPath: script.path))?[.modificationDate] as? Date else {
            return .init(synced: nil, note: L("The script isn't in iCloud Drive yet: put it there from Settings.",
                                              "Lo script non è ancora in iCloud Drive: mettilo dalle impostazioni."))
        }
        // synced follows "Updated " / "Aggiornato " on the page.
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Loc.locale))
        let day = date.formatted(.dateTime.day().month(.twoDigits).locale(Loc.locale))
        let synced = Calendar.current.isDate(date, inSameDayAs: now) ? L("at \(time)", "alle \(time)")
            : L("on \(day) at \(time)", "il \(day) alle \(time)")
        return .init(synced: synced, note: L("It updates by itself when there's a new build.", "Si aggiorna da solo quando c'è una build nuova."))
    }
}

// MARK: - the page in a web view

enum CampoPage {
    /// The map in the app's Resources, with its fonts next to it.
    static var url: URL? {
        Bundle.main.resourceURL.map { $0.appendingPathComponent("campo/il-campo.html") }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }
}

/// The map's web view. The dashboard scrolls under it: the page itself never does.
final class CampoWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }

    /// A web view with nothing kept on disk, the numbers set before the page's own script runs.
    static func make(json: String) -> CampoWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = CampoWebView(frame: .zero, configuration: config)
        web.setNumbers(json)
        return web
    }

    func setNumbers(_ json: String) {
        let scripts = configuration.userContentController
        scripts.removeAllUserScripts()
        scripts.addUserScript(WKUserScript(source: "window.CAMPO_DATA = \(json);", injectionTime: .atDocumentStart,
                                           forMainFrameOnly: true))
    }

    func open(_ page: URL) {
        loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }
}

/// The map in SwiftUI: made with the widget, freed with it (the dashboard drops its grid on close).
struct CampoMapView: NSViewRepresentable {
    let page: URL
    let json: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CampoWebView {
        let web = CampoWebView.make(json: json)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        // Hidden until the page is drawn: no white flash in the dark.
        web.isHidden = true
        context.coordinator.json = json
        web.open(page)
        return web
    }

    func updateNSView(_ web: CampoWebView, context: Context) {
        guard context.coordinator.json != json else { return }
        context.coordinator.json = json
        web.setNumbers(json)
        web.reload()
    }

    static func dismantleNSView(_ web: CampoWebView, coordinator: Coordinator) {
        web.stopLoading()
        web.navigationDelegate = nil
        web.uiDelegate = nil
        web.configuration.userContentController.removeAllUserScripts()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var json = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { webView.isHidden = false }
        // A page that failed is shown too: never a map hidden for good.
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { webView.isHidden = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            webView.isHidden = false
        }

        /// Only the page itself opens here; a link opens in the browser.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, !url.isFileURL else { return decisionHandler(.allow) }
            if url.scheme == "https" || url.scheme == "http" { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }

        /// target="_blank": the browser, never a window of ours.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, url.scheme == "https" || url.scheme == "http" { NSWorkspace.shared.open(url) }
            return nil
        }
    }
}

/// The numbers of the page, worked out again only when what they come from changes: the index read,
/// the day ("today" on the page), the mini golf's games, the iPhone line and the hook's log.
final class CampoCache {
    private var key = ""
    private var json = ""

    func json(for tasks: [PastTask]) -> String {
        let phone = CampoData.Phone.current()
        let day = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let k = "\(Loc.lang.rawValue)|\(GameMood.current.rawValue)|\(tasks.count)|\(tasks.first?.id ?? "")|\(tasks.first?.real ?? 0)"
            + "|\(day)|\(GolfStats.stamp())|\(phone.synced ?? "")|\(phone.note)|\(fileStamp(HookOffer.logURL.path))"
        if k != key {
            key = k
            json = CampoData.make(tasks, golf: GolfStats.load().games, phone: phone, offers: HookOffer.load(HookOffer.logURL)).json
        }
        return json
    }
}

/// The map as a widget, the whole width of the dashboard.
struct CampoWidget: View {
    @ObservedObject var model: DashboardModel
    let size: WidgetSize
    @State private var cache = CampoCache()
    /// Read so the map draws again (new numbers, new words) when the mood changes.
    @AppStorage(GameMood.key) private var moodRaw = GameMood.fallback.rawValue
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let _ = moodRaw
        let style = CampoStyle(scheme)
        ZStack {
            style.bg
            if DashDebug.snapshot {
                if let image = CampoSnapshot.image {
                    Image(nsImage: image).resizable()
                } else {
                    note(L("The map didn't make it into the snapshot.", "La mappa non è entrata nello snapshot."), style)
                }
            } else if let page = CampoPage.url {
                CampoMapView(page: page, json: cache.json(for: model.all))
            } else {
                note(L("The map isn't in this build: rebuild it with widget/build.sh.", "La mappa non c'è in questa build: rifalla con widget/build.sh."), style)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DashMetrics.radius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("The Course, the map of the estimates game", "Il campo, la mappa del gioco delle stime"))
    }

    private func note(_ text: String, _ style: CampoStyle) -> some View {
        Text(text).font(CampoFont.text(13)).foregroundStyle(style.muted)
    }
}

/// The map for `--dashboard-snapshot`: ImageRenderer draws no web view, so the page is drawn first,
/// off screen at the widget's size, and the widget shows that picture.
enum CampoSnapshot {
    @MainActor static var image: NSImage?

    @MainActor static func prepare(_ tasks: [PastTask], dark: Bool, width: CGFloat) {
        guard let page = CampoPage.url,
              let entry = DashGridModel().visible.first(where: { $0.widget == .campo }) else { return }
        let rows = CGFloat(entry.size.height)
        let size = NSSize(width: width, height: rows * DashMetrics.row + (rows - 1) * DashMetrics.gap)
        var data = CampoData.make(tasks, golf: GolfStats.load().games, phone: .current(), offers: HookOffer.load(HookOffer.logURL))
        data.still = true
        let web = CampoWebView.make(json: data.json)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        web.frame = NSRect(origin: .zero, size: size)
        window.contentView = web
        window.orderFrontRegardless()
        let loader = Loader()
        web.navigationDelegate = loader
        web.open(page)
        func wait(_ seconds: Double, until done: () -> Bool) {
            let end = Date().addingTimeInterval(seconds)
            while !done() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        wait(10) { loader.done }
        wait(0.8) { false } // the fonts
        var shot: NSImage?
        var taken = false
        web.takeSnapshot(with: nil) { image, _ in
            shot = image
            taken = true
        }
        wait(5) { taken }
        image = shot
        window.orderOut(nil)
    }

    private final class Loader: NSObject, WKNavigationDelegate {
        var done = false
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done = true }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { done = true }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { done = true }
    }
}
