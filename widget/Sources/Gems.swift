import Charts
import SwiftUI

// The estimates as a round of golf: every finished task with an estimate is a hole and Claude's
// estimate is its par. A hole in one (estimate hit) wins a diamond, a birdie (faster than the
// likely range) a sapphire, a par (inside it) an emerald, a bogey (past it) only a pebble. Points,
// levels, the streak, rounds of 18 holes and a challenge of the day on top, for the dashboard (the
// iPhone widget gets only the styles they win). Worked out from task-eta's index, nothing is saved. How the results are named
// and drawn follows the game's mood (GameMood.swift): a golf score card, or the gems.

enum Gem: String, CaseIterable, Codable {
    case diamond, sapphire, emerald, pebble

    init(_ outcome: Outcome) {
        switch outcome {
        case .exact: self = .diamond
        case .faster: self = .sapphire
        case .onTime: self = .emerald
        case .slower: self = .pebble
        }
    }

    /// The golf name of the hole.
    var hole: String {
        switch self {
        case .diamond: return "Hole in one"
        case .sapphire: return "Birdie"
        case .emerald: return "Par"
        case .pebble: return "Bogey"
        }
    }

    var name: String {
        switch self {
        case .diamond: return L("Diamond", "Diamante")
        case .sapphire: return L("Sapphire", "Zaffiro")
        case .emerald: return L("Emerald", "Smeraldo")
        case .pebble: return L("Pebble", "Sasso")
        }
    }

    /// What earns it, in words.
    var rule: String {
        switch self {
        case .diamond: return L("spot on", "stima centrata")
        case .sapphire: return L("faster than the range", "più veloce della forchetta")
        case .emerald: return L("within the range", "dentro la forchetta")
        case .pebble: return L("past the range", "oltre la forchetta")
        }
    }

    /// Like the mini golf: a hole in one is worth double.
    var points: Int {
        switch self {
        case .diamond: return 300
        case .sapphire: return 150
        case .emerald: return 100
        case .pebble: return 0
        }
    }

    var isGem: Bool { self != .pebble }

    /// Light, mid and deep tone of the cut.
    var tones: [Color] {
        switch self {
        case .diamond: return [Color(red: 0.89, green: 0.97, blue: 1.00), Color(red: 0.56, green: 0.85, blue: 0.96), Color(red: 0.31, green: 0.70, blue: 0.88)]
        case .sapphire: return [Color(red: 0.54, green: 0.71, blue: 1.00), Color(red: 0.30, green: 0.49, blue: 1.00), Color(red: 0.18, green: 0.33, blue: 0.83)]
        case .emerald: return [Color(red: 0.37, green: 0.88, blue: 0.77), Color(red: 0.18, green: 0.75, blue: 0.44), Color(red: 0.11, green: 0.56, blue: 0.32)]
        case .pebble: return [Color(white: 0.86), Color(white: 0.76), Color(white: 0.64)]
        }
    }
}

/// One hole: a finished task with an estimate.
struct GemHole: Equatable {
    var start: Double
    var end: Double
    var gem: Gem
    var points: Int
    /// Gems in a row before this one: each is worth 25 points more, as in the mini golf (up to 10).
    var streakBefore: Int
}

/// The levels, by points: a golfer's way up.
enum GemLevel {
    /// The 9 holes of Il campo (Campo.swift): each hole's title from its green on. Computed: the
    /// titles follow the language.
    static var steps: [(name: String, points: Int)] { CampoCourse.rules.map { ($0.title, $0.green) } }

    /// The level reached, its floor and the next one (nil at the top).
    static func of(_ points: Int) -> (name: String, floor: Int, next: (name: String, points: Int)?) {
        let steps = self.steps
        let i = steps.lastIndex { $0.points <= points } ?? 0
        return (steps[i].name, steps[i].points, i + 1 < steps.count ? steps[i + 1] : nil)
    }
}

/// The challenge of the day: one of these, the same all day.
enum GemChallenge: Int, CaseIterable {
    case twoDiamonds, threeInARow, birdie, cleanFive, fiveHundred

    var text: String {
        switch self {
        case .twoDiamonds: return L("hit 2 estimates", "centra 2 stime")
        case .threeInARow: return L("3 gems in a row", "3 gemme di fila")
        case .birdie: return L("a birdie", "un birdie")
        case .cleanFive: return L("5 holes without a bogey", "5 buche senza bogey")
        case .fiveHundred: return L("500 points", "500 punti")
        }
    }

    var goal: Int {
        switch self {
        case .twoDiamonds: return 2
        case .threeInARow: return 3
        case .birdie: return 1
        case .cleanFive: return 5
        case .fiveHundred: return 500
        }
    }

    static func of(_ date: Date = Date()) -> GemChallenge {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return allCases[(day + 2) % allCases.count] // not in step with the mini golf's challenge
    }

    /// How far today's holes (oldest first) go towards it.
    func progress(_ today: [GemHole]) -> Int {
        switch self {
        case .twoDiamonds: return today.filter { $0.gem == .diamond }.count
        case .threeInARow: return CampoGame.bestRun(today) { $0.gem.isGem }
        case .birdie: return today.filter { $0.gem == .sapphire }.count
        case .cleanFive: return today.reversed().prefix { $0.gem.isGem }.count
        case .fiveHundred: return today.reduce(0) { $0 + $1.points }
        }
    }
}

struct GemStats {
    static let roundHoles = CampoCourse.round
    static let maxStreakBonus = 10

    var holes: [GemHole] = []   // oldest first
    var today: [GemHole] = []
    var now = Date()
    /// Pebbles by project, the last 30 days: where the estimates fall short most.
    var pebblesByProject: [String: Int] = [:]

    init(_ tasks: [PastTask], now: Date = Date()) {
        self.now = now
        var streak = 0
        for t in tasks.sorted(by: { $0.start < $1.start }) {
            guard let outcome = t.outcome else { continue }
            let gem = Gem(outcome)
            let points = gem.isGem ? gem.points + 25 * min(streak, GemStats.maxStreakBonus) : 0
            holes.append(GemHole(start: t.start, end: t.start + t.real, gem: gem, points: points, streakBefore: streak))
            if gem == .pebble, t.start > now.timeIntervalSince1970 - 30 * 86400 { pebblesByProject[t.project, default: 0] += 1 }
            streak = gem.isGem ? streak + 1 : 0
        }
        let dayStart = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        today = holes.filter { $0.end >= dayStart }
    }

    init() {}

    var points: Int { holes.reduce(0) { $0 + $1.points } }
    var todayPoints: Int { today.reduce(0) { $0 + $1.points } }
    var streak: Int { holes.reversed().prefix { $0.gem.isGem }.count }
    var bestStreak: Int { CampoGame.bestRun(holes) { $0.gem.isGem } }
    var level: (name: String, floor: Int, next: (name: String, points: Int)?) { GemLevel.of(points) }

    func count(_ gem: Gem) -> Int { holes.filter { $0.gem == gem }.count }

    /// Today's holes in rounds of 18: the round being played and its holes so far.
    var round: (number: Int, holes: [GemHole]) {
        guard !today.isEmpty else { return (1, []) }
        let n = (today.count - 1) / GemStats.roundHoles
        return (n + 1, Array(today.dropFirst(n * GemStats.roundHoles)))
    }

    var challenge: GemChallenge { GemChallenge.of(now) }

    struct DayGems: Identifiable {
        let date: Date
        let gem: Gem
        let count: Int
        var id: String { "\(date.timeIntervalSince1970)-\(gem.rawValue)" }
    }

    /// Gems per day, the last `days` days (oldest first), for the dashboard's chart.
    func perDay(_ days: Int) -> [DayGems] {
        let calendar = Calendar.current
        let first = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        var counts: [Date: [Gem: Int]] = [:]
        for h in holes where h.end >= first.timeIntervalSince1970 {
            counts[calendar.startOfDay(for: Date(timeIntervalSince1970: h.end)), default: [:]][h.gem, default: 0] += 1
        }
        return counts.keys.sorted().flatMap { day in Gem.allCases.map { DayGems(date: day, gem: $0, count: counts[day]?[$0] ?? 0) } }
    }

    /// A day of tasks for the dashboard's preview and the snapshot.
    private static var cache: (key: String, stats: GemStats)?

    /// The gems of the index on disk, made again only when it changes or the day turns: one copy
    /// for the Touch Bar and the iPhone's server (main thread).
    static func current(_ index: URL = TaskStore.indexURL) -> GemStats {
        let key = "\(index.path)|\(fileStamp(index.path))|\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)"
        if let cache, cache.key == key { return cache.stats }
        let stats = GemStats(PastTask.loadShared(from: index))
        cache = (key, stats)
        return stats
    }

    static func sample(now: Date = Date()) -> GemStats {
        let t = now.timeIntervalSince1970
        let outcomes: [Outcome] = [.onTime, .exact, .onTime, .slower, .faster, .onTime, .exact, .onTime, .onTime, .slower, .exact]
        let tasks = outcomes.enumerated().map { i, o -> PastTask in
            let est = 300.0
            let real: Double = o == .exact ? 300 : o == .faster ? 120 : o == .onTime ? 360 : 700
            return PastTask(id: "s\(i)", start: t - Double(outcomes.count - i) * 900 - real, real: real, estimate: est,
                            range: (200, 450), model: "opus-5-5 xhigh", project: "demo", prompt: "", session: nil)
        }
        return GemStats(tasks, now: now)
    }
}

/// The iPhone widget's styles past light and dark: each one won with the gems, an easter egg.
/// The widget takes one when its name is written in the widget's Parameter field.
enum WidgetTheme: String, CaseIterable {
    case fairway, notte, oro

    var name: String {
        switch self {
        case .fairway: return "Fairway"
        case .notte: return L("Night golf", "Golf di notte")
        case .oro: return L("Trophy", "Trofeo")
        }
    }

    /// The name in the mood: the mine's Prato, Notte and Oro, or the golf names.
    func title(_ mood: GameMood) -> String {
        guard mood == .miniera else { return name }
        switch self {
        case .fairway: return L("Lawn", "Prato")
        case .notte: return L("Night", "Notte")
        case .oro: return L("Gold", "Oro")
        }
    }

    /// In the mine a style is won with blocks of diamond: 1, 5 and 10.
    var blocks: Int {
        switch self {
        case .fairway: return 1
        case .notte: return 5
        case .oro: return 10
        }
    }

    func how(_ mood: GameMood = .current) -> String {
        if mood == .miniera {
            return blocks == 1 ? L("make 1 Block of Diamond", "fai 1 blocco di diamante")
                : L("make \(blocks) Blocks of Diamond", "fai \(blocks) blocchi di diamante")
        }
        switch self {
        case .fairway: return L("reach Amateur (10,000 points)", "arriva a Dilettante (10.000 punti)")
        case .notte: return L("get 10 \(mood.goods) in a row", "fai 10 \(mood.goods) di fila")
        case .oro: return L("reach Handicap 9 (40,000 points)", "arriva a Handicap 9 (40.000 punti)")
        }
    }

    func isUnlocked(_ s: GemStats) -> Bool {
        switch self {
        case .fairway: return s.points >= 10_000
        case .notte: return s.bestStreak >= 10
        case .oro: return s.points >= 40_000
        }
    }

    /// The styles won: with blocks of diamond (the mine) or by the golf's rules (the minigolf),
    /// whichever mood is on, so moving to the mine takes nothing away.
    static func won(gems: GemStats, mine: MineStats) -> [WidgetTheme] {
        allCases.filter { mine.blocks >= $0.blocks || $0.isUnlocked(gems) }
    }
}


// MARK: - drawing

/// A cut gem seen from the side: table, crown and pavilion facets in three tones, a glint on top.
/// The pebble is a plain round stone.
struct GemView: View {
    let gem: Gem?   // nil: an empty slot of the round
    var size: CGFloat = 18

    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            guard let gem else {
                ctx.stroke(Path(ellipseIn: CGRect(x: w * 0.2, y: h * 0.2, width: w * 0.6, height: h * 0.6)),
                           with: .color(.primary.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                return
            }
            let t = gem.tones
            if gem == .pebble {
                let r = CGRect(x: w * 0.12, y: h * 0.3, width: w * 0.76, height: h * 0.55)
                ctx.fill(Path(ellipseIn: r), with: .linearGradient(Gradient(colors: [t[0], t[2]]),
                         startPoint: CGPoint(x: w / 2, y: r.minY), endPoint: CGPoint(x: w / 2, y: r.maxY)))
                return
            }
            let crown = h * 0.34
            func poly(_ points: [CGPoint], _ color: Color) {
                var p = Path()
                p.addLines(points)
                p.closeSubpath()
                ctx.fill(p, with: .color(color))
            }
            let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * w, y: y * h) }
            let c = crown / h
            poly([p(0.26, 0.08), p(0.74, 0.08), p(0.62, c), p(0.38, c)], t[0])           // table
            poly([p(0.26, 0.08), p(0.38, c), p(0.04, c)], t[1])                           // crown, left
            poly([p(0.74, 0.08), p(0.96, c), p(0.62, c)], t[1].opacity(0.85))             // crown, right
            poly([p(0.04, c), p(0.38, c), p(0.5, 0.95)], t[1])                            // pavilion, left
            poly([p(0.38, c), p(0.62, c), p(0.5, 0.95)], t[0].opacity(0.9))               // pavilion, middle
            poly([p(0.62, c), p(0.96, c), p(0.5, 0.95)], t[2])                            // pavilion, right
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.34, y: h * 0.12, width: w * 0.1, height: h * 0.08)),
                     with: .color(.white.opacity(0.9)))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(gem.map { "\($0.name), \($0.hole)" } ?? L("hole to play", "buca da giocare"))
    }
}

// MARK: - dashboard

/// The results in the dashboard, in the map's style, short at rest: where you are (the hole and the
/// way to its green), today's round as a golf score card with its score on par, and the next power.
/// The rest waits behind its chip: it opens as soon as the pointer is on the chip, stays while the
/// pointer is on the chips or on it, and goes when the pointer leaves; a click keeps it open. Names
/// and marks follow the mood. Every number says what it counts.
struct GemsCard: View {
    let stats: GemStats
    @Environment(\.colorScheme) private var scheme
    @AppStorage(GameMood.key) private var moodRaw = GameMood.fallback.rawValue
    /// The detail of the chip under the pointer, and the one a click keeps open.
    @State private var hovered: GemsDetail?
    @State private var pinned: GemsDetail? = GemsDetail.debugOpen
    private var mood: GameMood { GameMood(rawValue: moodRaw) ?? .fallback }

    var body: some View {
        let s = CampoStyle(scheme)
        let e = CampoNow.shared.engine()
        VStack(alignment: .leading, spacing: 14) {
            whereYouAre(e, s)
            roundCard(s)
            nextPower(e, s)
            details(e, s)
        }
    }

    /// The hole being played and the fairway to its green, from the last green closed.
    @ViewBuilder
    private func whereYouAre(_ e: CampoEngine, _ s: CampoStyle) -> some View {
        if let i = e.currentIndex {
            let hole = e.course[i]
            let prev = i > 0 ? e.course[i - 1].rule.green : 0
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L("Hole \(hole.rule.number) · \(hole.rule.title)", "Buca \(hole.rule.number) · \(hole.rule.title)")).font(CampoFont.display(20)).foregroundStyle(s.ink)
                    Text(hole.rule.zone).font(CampoFont.text(12)).foregroundStyle(s.muted)
                    Spacer(minLength: 8)
                    Text(e.points >= hole.rule.green ? L("green reached: now the trials count", "green raggiunto: ora contano le prove")
                         : L("\(grouped(hole.rule.green - e.points)) points to the green", "ne mancano \(grouped(hole.rule.green - e.points)) punti al green"))
                        .font(CampoFont.text(11.5, .semibold)).foregroundStyle(s.ink)
                }
                CampoFairway(share: Double(e.points - prev) / Double(max(1, hole.rule.green - prev)))
                HStack {
                    Text(e.title.map { L("Title \($0)", "Titolo \($0)") } ?? L("No title yet", "Nessun titolo ancora"))
                        + Text(L(" · \(grouped(e.points)) points", " · \(grouped(e.points)) punti"))
                    Spacer()
                    Text(L("green at \(grouped(hole.rule.green))", "green a \(grouped(hole.rule.green))"))
                }
                .font(CampoFont.text(11)).foregroundStyle(s.muted)
            }
        } else {
            Text(L("Course done: you're a Legend of the green.", "Campo finito: sei Leggenda del green.")).font(CampoFont.display(20)).foregroundStyle(s.ink)
        }
    }

    @ViewBuilder
    private func nextPower(_ e: CampoEngine, _ s: CampoStyle) -> some View {
        if let hole = e.current, let next = CampoPower(rawValue: hole.rule.number) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("NEXT POWER", "PROSSIMO POTERE")).campoEyebrow(s)
                Text(next.name).font(CampoFont.display(15)).foregroundStyle(s.ink)
                Text(next.rule.powerText).font(CampoFont.text(11.5)).foregroundStyle(s.muted).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }

    /// The chips and, under them, the detail open: instant, no animation.
    private func details(_ e: CampoEngine, _ s: CampoStyle) -> some View {
        let open = hovered ?? pinned
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(GemsDetail.allCases) { d in chip(d, label: label(d, e), open: open == d, s) }
                Spacer(minLength: 0)
            }
            if let d = open {
                panel(d, e, s)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .campoPaper(s)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in if !inside { hovered = nil } }
        .transaction { $0.animation = nil }
    }

    private func chip(_ d: GemsDetail, label: String, open: Bool, _ s: CampoStyle) -> some View {
        Button { pinned = pinned == d ? nil : d } label: {
            Text(label).font(CampoFont.text(12, .semibold)).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(open ? s.onLane : s.ink)
                .background(Capsule().fill(open ? s.lane : s.plate))
                .overlay(Capsule().strokeBorder(pinned == d ? s.flag : s.line, lineWidth: pinned == d ? 1.5 : 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { hovered = d } }
        .help(pinned == d ? L("Click: close", "Clic: chiudi") : L("Click: keep it open", "Clic: tienilo aperto"))
        .accessibilityLabel(label)
        .accessibilityHint(L("Opens on hover; a click keeps it open", "Si apre passandoci sopra; un clic lo tiene aperto"))
    }

    private func label(_ d: GemsDetail, _ e: CampoEngine) -> String {
        switch d {
        case .trials:
            guard let hole = e.current else { return L("Trials", "Prove") }
            return L("Trials \(hole.trials.filter(\.done).count) of \(hole.trials.count)",
                     "Prove \(hole.trials.filter(\.done).count) di \(hole.trials.count)")
        case .today: return L("Today +\(grouped(stats.todayPoints))", "Oggi +\(grouped(stats.todayPoints))")
        case .collection: return L("Collection", "Collezione")
        case .minigolf: return L("Mini golf", "Minigolf")
        case .claude: return e.claude.marks.isEmpty ? "Claude"
            : L("Claude \(e.claude.inside) of \(e.claude.last.count)", "Claude \(e.claude.inside) su \(e.claude.last.count)")
        case .guide: return L("What it's for", "A cosa serve")
        case .styles: return L("iPhone styles", "Stili iPhone")
        case .mood: return "Mood: \(mood.title)"
        }
    }

    @ViewBuilder
    private func panel(_ d: GemsDetail, _ e: CampoEngine, _ s: CampoStyle) -> some View {
        switch d {
        case .trials: trials(e, s)
        case .today: today(s)
        case .collection:
            HStack(alignment: .top, spacing: 14) {
                collection(s).frame(maxWidth: .infinity)
                perDay(s).frame(maxWidth: .infinity)
            }
        case .minigolf: minigolf(e)
        case .claude: claude(e, s)
        case .guide:
            VStack(alignment: .leading, spacing: 8) {
                GemsGuide(stats: stats)
                Text(L("How they count: every task with Claude's estimate is a hole and the estimate is its par. A \(mood.good) is worth its points plus 25 for each \(mood.good) in a row before it, up to +250.",
                       "Come si contano: ogni task con la stima di Claude è una buca e la stima è il suo par. Una \(mood.good) vale i suoi punti più 25 per ogni \(mood.good) di fila prima, fino a +250."))
                    .font(CampoFont.text(11)).foregroundStyle(s.muted).fixedSize(horizontal: false, vertical: true)
            }
        case .styles: PhoneThemeTiles(won: WidgetTheme.won(gems: stats, mine: MineStats.current()).map(\.rawValue), mood: mood)
        case .mood:
            VStack(alignment: .leading, spacing: 6) {
                GameMoodPicker().frame(maxWidth: 420, alignment: .leading)
                Text(L("The Mine counts diamonds, blocks and beacons; the mini golf, the extra, counts points and holes.",
                       "La miniera conta diamanti, blocchi e fari; il minigolf, l'extra, i punti e le buche.")).font(CampoFont.text(11)).foregroundStyle(s.muted)
            }
        }
    }

    /// The trials of the hole with their reasons, what to do, the powers on.
    @ViewBuilder
    private func trials(_ e: CampoEngine, _ s: CampoStyle) -> some View {
        if let hole = e.current {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("Hole \(hole.rule.number) · \(hole.rule.title): the trials", "Buca \(hole.rule.number) · \(hole.rule.title): le prove")).font(CampoFont.display(15)).foregroundStyle(s.ink)
                ForEach(Array(zip(hole.rule.trials, hole.trials).enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(pair.1.done ? L("done", "fatta") : L("to do", "da fare")).font(CampoFont.display(11, .semibold))
                            .foregroundStyle(pair.1.done ? s.done : s.muted).frame(width: 46, alignment: .leading)
                        Text("\(pair.1.name): \(e.evidence(pair.0, pair.1))")
                            .font(CampoFont.text(11.5)).foregroundStyle(s.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let tip = e.tip(for: hole) {
                    Text(L("What to do: ", "Cosa fare: ") + tip).font(CampoFont.text(11)).foregroundStyle(s.muted).fixedSize(horizontal: false, vertical: true)
                }
                Text(L("Powers: \(e.powersText).", "Poteri: \(e.powersText).")).font(CampoFont.text(11)).foregroundStyle(s.muted).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(L("All the holes are closed.", "Tutte le buche sono chiuse.")).font(CampoFont.text(12)).foregroundStyle(s.muted)
        }
    }

    /// Level, today, streak and the challenge of the day, each with its why.
    private func today(_ s: CampoStyle) -> some View {
        let level = stats.level
        let c = stats.challenge
        let progress = c.progress(stats.today)
        return HStack(alignment: .top, spacing: 10) {
            CampoFigure(label: L("Level", "Livello"), value: level.name,
                        why: level.next.map { L("\(grouped(stats.points)) points: \($0.name) is at \(grouped($0.points))",
                                                "\(grouped(stats.points)) punti: \($0.name) è a \(grouped($0.points))") }
                            ?? L("\(grouped(stats.points)) points: you're at the top", "\(grouped(stats.points)) punti: sei in cima"))
            CampoFigure(label: L("Today", "Oggi"), value: "+\(grouped(stats.todayPoints))",
                        why: L("\(mood.goods(stats.today.filter(\.gem.isGem).count)) of today's \(stats.today.count) hole\(stats.today.count == 1 ? "" : "s")",
                               "\(mood.goods(stats.today.filter(\.gem.isGem).count)) su \(stats.today.count) buche di oggi"))
            CampoFigure(label: L("Streak", "Serie"), value: L("\(stats.streak) in a row", "\(stats.streak) di fila"),
                        why: L("each \(mood.good) in a row is worth 25 more points, up to +250; the record is \(stats.bestStreak)",
                               "ogni \(mood.good) di fila vale 25 punti in più, fino a +250; il record è \(stats.bestStreak)"))
            CampoFigure(label: L("Today's challenge", "Sfida di oggi"),
                        value: progress >= c.goal ? L("won", "vinta") : L("\(min(progress, c.goal)) of \(c.goal)", "\(min(progress, c.goal)) di \(c.goal)"),
                        why: L("\(c.text); it changes every day", "\(c.text); cambia ogni giorno"), accent: progress >= c.goal ? s.done : nil)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func minigolf(_ e: CampoEngine) -> some View {
        CampoFigure(label: L("Mini golf", "Minigolf"),
                    value: e.nextField.map { L("\(grouped(e.played)) of \(grouped($0.need))", "\(grouped(e.played)) di \(grouped($0.need))") }
                        ?? L("all open", "tutti aperti"),
                    why: (e.nextField.map { L("holes played toward the \($0.name); ", "buche fatte verso il \($0.name); ") } ?? "")
                        + L("playing on: \(e.fields.map(\.name).joined(separator: ", "))", "si gioca su: \(e.fields.map(\.name).joined(separator: ", "))")
                        + (e.isOn(.strongClub) ? L(", with the power club (hole 4).", ", con la mazza forte (buca 4).") : "."))
            .frame(maxWidth: 520, alignment: .leading)
    }

    private func claude(_ e: CampoEngine, _ s: CampoStyle) -> some View {
        let c = e.claude
        return VStack(alignment: .leading, spacing: 6) {
            CampoFigure(label: L("Claude plays too", "Anche Claude gioca"),
                        value: c.marks.isEmpty ? "–" : L("\(c.inside) of \(c.last.count)", "\(c.inside) su \(c.last.count)"),
                        why: c.marks.isEmpty ? L("no estimates to count yet", "ancora nessuna stima da contare")
                            : L("estimates in the last \(c.last.count): \(c.counts), against the hook's range; streak \(c.streak), record \(c.best)",
                                "stime nelle ultime \(c.last.count): \(c.counts), contro la forchetta dell'hook; serie \(c.streak), record \(c.best)"),
                        accent: !c.marks.isEmpty && Double(c.inside) >= 0.7 * Double(c.last.count) ? s.done : nil)
            Text(ClaudeScore.why).font(CampoFont.text(11)).foregroundStyle(s.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Today's round as a score card: the holes on top, the result under each, the score against par.
    private func roundCard(_ s: CampoStyle) -> some View {
        let round = stats.round
        let toPar = round.holes.reduce(0) { $0 + CampoHole.toPar($1.gem) }
        return VStack(alignment: .leading, spacing: 7) {
            Text(L("TODAY'S ROUND \(round.number)", "GIRO \(round.number) DI OGGI")).campoEyebrow(s)
            CampoScoreCard {
                HStack(spacing: 0) {
                    Text(L("HOLE", "BUCA")).frame(width: 62, alignment: .leading).padding(.leading, 10)
                    ForEach(1...GemStats.roundHoles, id: \.self) { Text("\($0)").frame(maxWidth: .infinity) }
                    Text(L("TO PAR", "SUL PAR")).frame(width: 70)
                }
            } rows: {
                HStack(spacing: 0) {
                    Text(mood.rowLabel).font(CampoFont.text(12, .semibold)).foregroundStyle(s.muted)
                        .frame(width: 62, alignment: .leading).padding(.leading, 10)
                    ForEach(0..<GemStats.roundHoles, id: \.self) { i in
                        ResultMark(gem: i < round.holes.count ? round.holes[i].gem : nil, size: 18, mood: mood)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .leading) { Rectangle().fill(s.line).frame(width: 1) }
                    }
                    Text(round.holes.isEmpty ? "–" : CampoData.signed(toPar, par: true))
                        .font(CampoFont.display(17)).foregroundStyle(toPar < 0 ? s.done : s.ink)
                        .frame(minWidth: 70, maxWidth: 70, maxHeight: .infinity)
                        .overlay(alignment: .leading) { Rectangle().fill(s.line).frame(width: 1) }
                }
                .frame(height: 34)
            }
            Text(round.holes.isEmpty ? L("No holes today: Claude's first estimate opens the round.", "Nessuna buca oggi: la prima stima di Claude apre il giro.")
                 : L("\(round.holes.count) hole\(round.holes.count == 1 ? "" : "s") of \(GemStats.roundHoles). To par: \(mood.parLine).",
                     "\(round.holes.count) buche su \(GemStats.roundHoles). Sul par: \(mood.parLine)."))
                .font(CampoFont.text(11)).foregroundStyle(s.muted)
        }
    }

    private func collection(_ s: CampoStyle) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L("COLLECTION", "COLLEZIONE")).campoEyebrow(s)
            VStack(spacing: 0) {
                ForEach(Array(Gem.allCases.enumerated()), id: \.offset) { i, gem in
                    HStack(spacing: 10) {
                        ResultMark(gem: gem, size: 20, mood: mood)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(mood.name(gem)).font(CampoFont.display(14)).foregroundStyle(s.ink)
                            Text(L("\(mood.detail(gem)): \(gem.points) points", "\(mood.detail(gem)): \(gem.points) punti"))
                                .font(CampoFont.text(11)).foregroundStyle(s.muted).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(grouped(stats.count(gem))).font(CampoFont.display(17)).foregroundStyle(s.ink)
                    }
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(s.line).frame(height: 1) } }
                }
            }
            .campoPaper(s, radius: 8)
        }
    }

    private func perDay(_ s: CampoStyle) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(mood.perDayTitle).campoEyebrow(s)
            Chart(stats.perDay(14)) { row in
                BarMark(x: .value(L("Day", "Giorno"), row.date, unit: .day), y: .value(L("Holes", "Buche"), row.count))
                    .foregroundStyle(by: .value(L("Result", "Esito"), mood.name(row.gem)))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: Gem.allCases.map { mood.name($0) }, range: Gem.allCases.map { mood.color($0, s) })
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine().foregroundStyle(s.line)
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                        .font(CampoFont.text(9.5)).foregroundStyle(s.muted)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(s.line)
                    AxisValueLabel().font(CampoFont.text(10)).foregroundStyle(s.muted)
                }
            }
            .frame(height: 168)
            .padding(10)
            .campoPaper(s, radius: 8)
        }
    }

    private func grouped(_ n: Int) -> String { CampoData.grouped(n) }
}

/// What the card keeps behind a chip.
enum GemsDetail: String, CaseIterable, Identifiable {
    case trials, today, collection, minigolf, claude, guide, styles, mood
    var id: String { rawValue }

    /// For a snapshot: TASKETA_DEBUG_DASH with a detail's name opens it (styles, trials…).
    static var debugOpen: GemsDetail? { DashDebug.flags.lazy.compactMap { GemsDetail(rawValue: $0) }.first }
}

/// The style the iPhone widget uses, picked on the Mac with «Usa sull'iPhone»: sent in /status as
/// "theme", and the widget takes it when its Parameter field is empty (the Parameter still wins).
enum PhoneTheme {
    static let key = "phoneTheme"
    static let auto = "auto"

    /// The pick, sent only once it is won: anything else is light or dark like the iPhone.
    static func current(won: [String]) -> String {
        let pick = UserDefaults.standard.string(forKey: key) ?? auto
        return won.contains(pick) ? pick : auto
    }
}

extension WidgetTheme {
    /// What it looks like on the iPhone, in a line.
    var about: String {
        switch self {
        case .fairway: return L("Green lawn, light text, “running” in yellow.", "Prato verde, testo chiaro, «in corso» in giallo.")
        case .notte: return L("Midnight blue, almost black, “running” in aqua.", "Blu notte, quasi nero, «in corso» in verde acqua.")
        case .oro: return L("Gold, dark brown text, “running” in green.", "Oro, testo marrone scuro, «in corso» in verde.")
        }
    }

    /// The widget's own colours (THEMES in TaskETA.js): background top and bottom, text, secondary text, «in corso».
    var preview: (top: Color, bottom: Color, text: Color, muted: Color, running: Color) {
        func c(_ hex: UInt32) -> Color {
            Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
        }
        switch self {
        case .fairway: return (c(0x1A5E41), c(0x092A1E), c(0xF3F7EF), c(0xA9C7B5), c(0xFFD66B))
        case .notte: return (c(0x18204A), c(0x04060E), c(0xEAF0FF), c(0x8C96BF), c(0x7CF7D4))
        case .oro: return (c(0xFFF7D6), c(0xDDB24C), c(0x3A2A05), c(0x77591A), c(0x1C8F52))
        }
    }
}

/// The iPhone widget's styles as tiles: a small preview of each, a line on what it looks like, and
/// «Usa sull'iPhone», or the padlock with how to win it. No more names to type in the Parameter.
struct PhoneThemeTiles: View {
    /// The styles won, by name.
    let won: [String]
    let mood: GameMood
    @AppStorage(PhoneTheme.key) private var pick = PhoneTheme.auto
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        let inUse = won.contains(pick) ? pick : PhoneTheme.auto
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                tile(id: PhoneTheme.auto, name: L("Automatic", "Automatico"), about: L("Light or dark, like the iPhone.", "Chiaro o scuro, come l'iPhone."),
                     won: true, how: nil, inUse: inUse, s) {
                    AutoPreview()
                }
                ForEach(WidgetTheme.allCases, id: \.self) { t in
                    tile(id: t.rawValue, name: t.title(mood), about: t.about, won: won.contains(t.rawValue), how: t.how(mood), inUse: inUse, s) {
                        ThemePreview(theme: t)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(L("The widget changes by itself at its next refresh, usually within a few minutes. If a style is written in the widget's Parameter, that one wins.",
                   "Il widget cambia da solo al prossimo aggiornamento, di solito entro pochi minuti. Se nel Parameter del widget è scritto uno stile, vince quello."))
                .font(CampoFont.text(11)).foregroundStyle(s.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tile<Preview: View>(id: String, name: String, about: String, won: Bool, how: String?, inUse: String,
                                     _ s: CampoStyle, @ViewBuilder preview: () -> Preview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                preview()
                if !won { CampoLock(size: 12, onDrawing: true) }
            }
            .frame(height: 56)
            .opacity(won ? 1 : 0.7)
            Text(name).font(CampoFont.display(14)).foregroundStyle(won ? s.ink : s.muted)
            Text(about).font(CampoFont.text(11)).foregroundStyle(s.muted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !won {
                Text(L("To win: \(how ?? "")", "Da vincere: \(how ?? "")")).font(CampoFont.text(11, .semibold)).foregroundStyle(s.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if inUse == id {
                Text(L("In use on iPhone", "In uso sull'iPhone")).font(CampoFont.text(11.5, .semibold)).foregroundStyle(s.done)
            } else {
                Button(L("Use on iPhone", "Usa sull'iPhone")) { pick = id }.controlSize(.small)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .campoPaper(s)
    }
}

/// A small Home widget in a style: its background, a task's name, a bar and «in corso».
struct ThemePreview: View {
    let theme: WidgetTheme

    var body: some View {
        let p = theme.preview
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [p.top, p.bottom], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("my-app").font(.system(size: 10, weight: .semibold)).foregroundStyle(p.text)
                    Capsule().fill(p.muted.opacity(0.35)).frame(height: 6)
                        .overlay(alignment: .leading) { Capsule().fill(p.running).frame(width: 44, height: 6) }
                    Text(L("running · 4:12", "in corso · 4:12")).font(.system(size: 9, weight: .semibold)).foregroundStyle(p.running)
                }
                .padding(8)
            }
            .accessibilityHidden(true)
    }
}

/// "Automatico": the widget light by day, dark by night, like the iPhone.
struct AutoPreview: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 0) {
            half(bg: .white, text: Color(white: 0.11), label: L("light", "chiaro"))
            half(bg: Color(white: 0.11), text: Color(white: 0.96), label: L("dark", "scuro"))
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private func half(bg: Color, text: Color, label: String) -> some View {
        ZStack(alignment: .topLeading) {
            bg
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(text)
                Capsule().fill(Color(red: 0.20, green: 0.78, blue: 0.35)).frame(width: 28, height: 6)
            }
            .padding(8)
        }
    }
}

/// The results as a widget: the level and the way to the next one, or the whole card (scrolling inside).
struct GemsWidget: View {
    let stats: GemStats
    let mine: MineStats
    let size: WidgetSize
    /// The mine's find clicked: the History on its tasks.
    var onFind: ((Ore, Date?) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @AppStorage(GameMood.key) private var moodRaw = GameMood.fallback.rawValue

    var body: some View {
        let mood = GameMood(rawValue: moodRaw) ?? .fallback
        if mood == .miniera {
            if size.height < 2 {
                MinieraStrip(stats: mine)
            } else if DashDebug.snapshot {
                MinieraCard(stats: mine, gems: stats, onFind: onFind, wide: size.width >= 3)
            } else {
                ScrollView { MinieraCard(stats: mine, gems: stats, onFind: onFind, wide: size.width >= 3) }
            }
        } else if size.height >= 2 {
            CampoPlate(title: mood.cardTitle, subtitle: mood.cardSubtitle) {
                if DashDebug.snapshot {
                    GemsCard(stats: stats)
                } else {
                    ScrollView { GemsCard(stats: stats).padding(.trailing, 8) }
                }
            }
        } else {
            let level = stats.level
            CampoPlate(title: mood.cardTitle,
                       subtitle: L("\(level.name), \(CampoData.grouped(stats.points)) points, today +\(CampoData.grouped(stats.todayPoints))",
                                   "\(level.name), \(CampoData.grouped(stats.points)) punti, oggi +\(CampoData.grouped(stats.todayPoints))"),
                       compact: true) {
                VStack(alignment: .leading, spacing: 5) {
                    if let next = level.next {
                        CampoBar(share: Double(stats.points - level.floor) / Double(max(1, next.points - level.floor)))
                        Text(L("\(CampoData.grouped(next.points - stats.points)) points to \(next.name)",
                               "\(CampoData.grouped(next.points - stats.points)) punti a \(next.name)"))
                            .font(CampoFont.text(11.5)).foregroundStyle(CampoStyle(scheme).muted)
                    }
                }
            }
        }
    }
}

/// What the results are for: what they measure, what yours say now (with something to do about
/// it) and a goal to keep.
struct GemsGuide: View {
    let stats: GemStats
    /// Results at par or better in the last 18 holes: from here on the estimates are good enough to plan with.
    static let goal = CampoCourse.goal
    @Environment(\.colorScheme) private var scheme
    @AppStorage(GameMood.key) private var moodRaw = GameMood.fallback.rawValue
    private var mood: GameMood { GameMood(rawValue: moodRaw) ?? .fallback }

    var body: some View {
        let s = CampoStyle(scheme)
        let recent = Array(stats.holes.suffix(GemStats.roundHoles))
        let gems = recent.filter(\.gem.isGem).count
        let share = recent.isEmpty ? 0 : Double(gems) / Double(recent.count)
        HStack(alignment: .top, spacing: 10) {
            block(L("What they're for", "A cosa servono"),
                  L("They measure how far you can trust the time estimate Claude writes at the start of each reply. They don't grade you or Claude: they tell you whether that “~10 min” is a time you can plan around.",
                    "Misurano quanto puoi fidarti della stima di tempo che Claude scrive all'inizio di ogni risposta. Non danno un voto a te né a Claude: dicono se quel «~10 min» è un tempo su cui puoi organizzarti."), s)
            block(L("What they say now", "Cosa ti dicono adesso"), reading(recent) + worstProject, s)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("The goal", "Il fine")).font(CampoFont.display(15)).foregroundStyle(s.ink)
                Text(L("Keep at least \(safeInt(GemsGuide.goal * 100))% \(mood.goods) over the last \(GemStats.roundHoles) holes: it means estimates you can plan your day on.",
                       "Tenere almeno il \(safeInt(GemsGuide.goal * 100))% di \(mood.goods) nelle ultime \(GemStats.roundHoles) buche: vuol dire stime su cui puoi pianificare la giornata."))
                    .font(CampoFont.text(11)).foregroundStyle(s.muted).fixedSize(horizontal: false, vertical: true)
                CampoBar(share: share, color: share >= GemsGuide.goal ? s.done : s.wood, mark: GemsGuide.goal)
                    .padding(.vertical, 2)
                Text(recent.isEmpty ? L("No holes yet.", "Ancora nessuna buca.")
                     : L("You're at \(safeInt(share * 100))%: \(mood.goods(gems)) of \(recent.count) hole\(recent.count == 1 ? "" : "s")\(share >= GemsGuide.goal ? ", goal reached" : "").",
                         "Sei al \(safeInt(share * 100))%: \(mood.goods(gems)) su \(recent.count) buche\(share >= GemsGuide.goal ? ", obiettivo raggiunto" : "")."))
                    .font(CampoFont.text(11.5, .semibold)).foregroundStyle(share >= GemsGuide.goal ? s.done : s.ink)
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .campoPaper(s)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The reading of the last holes, with a piece of advice.
    private func reading(_ recent: [GemHole]) -> String {
        let n = Double(recent.count)
        guard recent.count >= 5 else {
            return L("Only a few holes so far (\(recent.count)): after 5 estimates you'll see here what they say.",
                     "Ancora poche buche (\(recent.count)): dopo 5 stime qui trovi cosa dicono.")
        }
        let pebbles = Double(recent.filter { $0.gem == .pebble }.count) / n
        let sapphires = Double(recent.filter { $0.gem == .sapphire }.count) / n
        let gems = Double(recent.filter(\.gem.isGem).count) / n
        if pebbles >= 0.4 {
            return L("Lots of \(mood.bads): tasks turn out bigger than the way you ask for them. Break them into smaller steps or give more context in the prompt, and the estimates will be reliable again.",
                     "Tanti \(mood.bads): i task si rivelano più grossi di come li chiedi. Spezzali in passi più piccoli o dai più contesto nel prompt, e le stime torneranno affidabili.")
        }
        if sapphires >= 0.35 {
            return L("Lots of \(mood == .minigolf ? "birdies" : "sapphires"): Claude plays it safe and finishes early. You can ask for more in one go.",
                     "Tanti \(mood == .minigolf ? "birdie" : "zaffiri"): Claude si tiene largo e finisce prima del previsto. Puoi chiedergli di più in una volta sola.")
        }
        if gems >= GemsGuide.goal {
            return L("Reliable estimates: use them to plan. A “~10 min” is a coffee, a “~30 min” a call.",
                     "Stime affidabili: usale per organizzarti. Un «~10 min» è un caffè, un «~30 min» una call.")
        }
        return L("So-so estimates: take them as a ballpark, not as an exact time.",
                 "Stime a metà: prendile come ordine di grandezza, non come orario preciso.")
    }

    private var worstProject: String {
        guard let worst = stats.pebblesByProject.max(by: { $0.value < $1.value }), worst.value >= 2 else { return "" }
        return L(" Most overruns in \(worst.key): \(mood.bads(worst.value)) in the last 30 days.",
                 " Sfora di più in \(worst.key): \(mood.bads(worst.value)) negli ultimi 30 giorni.")
    }

    private func block(_ title: String, _ text: String, _ s: CampoStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(CampoFont.display(15)).foregroundStyle(s.ink)
            Text(text).font(CampoFont.text(11)).foregroundStyle(s.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .campoPaper(s)
    }
}
