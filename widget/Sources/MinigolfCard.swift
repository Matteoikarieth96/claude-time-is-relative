import SwiftUI

// The mini golf in the dashboard, in the map's style (CampoStyle.swift): the road of its three
// courses, the round of the day as a golf score card, four numbers each with its why next to the
// map of the shots on the list (GolfTrace.swift), the leaderboard (the games, the combos, and an
// online one still to come). The rest waits behind three chips that open under the pointer, as in
// GemsCard. Nothing moves at rest.

extension GolfStats {
    /// Every run of hole in ones (combo and bestCombo are in GolfStats.swift), the longest first
    /// (the latest first among equals), with when its last ace went in: the combos' leaderboard.
    var combos: [(count: Int, end: Double)] {
        var runs: [(count: Int, end: Double)] = []
        var run = 0, end = 0.0
        for g in games {
            if g.sunk && g.shots == 1 {
                run += 1
                end = g.end
            } else {
                if run > 0 { runs.append((run, end)) }
                run = 0
            }
        }
        if run > 0 { runs.append((run, end)) }
        return runs.sorted { ($0.count, $0.end) > ($1.count, $1.end) }
    }

    /// The hole that took the most shots, then the most cushions.
    var hardestHole: GolfRecord? {
        games.filter(\.sunk).max { ($0.shots, $0.totalCushions) < ($1.shots, $1.totalCushions) }
    }

    var fastestGame: GolfRecord? { games.filter(\.sunk).min { $0.seconds < $1.seconds } }
}

/// The whole widget: the lawn of the club with the challenge of the day in its corner.
struct MinigolfPlate: View {
    let store: TaskStore?
    let played: Int
    var stats = GolfStats.forDashboard()
    var scrolls = false

    var body: some View {
        let locked = MinigolfCard.isLocked(store, stats)
        let club = CampoNow.shared.engine().isOn(.strongClub)
        CampoPlate(title: L("Mini golf", "Minigolf"),
                   subtitle: locked ? L("The club's lawn, to unlock", "Il prato del circolo, da sbloccare")
                       : L("The club's lawn, par 3", "Il prato del circolo, par 3") + (club ? L(", with the power club", ", con la mazza forte") : "")) {
            if scrolls {
                ScrollView { MinigolfCard(store: store, played: played, stats: stats).padding(.trailing, 8) }
            } else {
                MinigolfCard(store: store, played: played, stats: stats)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !locked { MinigolfChallenge(stats: stats).padding(.top, 18).padding(.trailing, 18) }
        }
    }
}

/// The challenge of the day, in the plate's corner.
struct MinigolfChallenge: View {
    let stats: GolfStats
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        let done = stats.challengeDoneToday
        let days = stats.challengeStreak
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(L("Today's challenge", "Sfida di oggi")).font(CampoFont.text(12.5, .semibold)).foregroundStyle(s.muted)
                Text(GolfChallenge.of().text).font(CampoFont.display(15)).foregroundStyle(s.ink)
                CampoState(text: done ? L("won", "vinta") : L("to do", "da fare"), color: done ? s.done : s.muted)
            }
            if days > 0 {
                Text((done ? "" : L("won yesterday: ", "vinta ieri: "))
                     + L(days == 1 ? "1 day in a row" : "\(days) days in a row", "\(days) \(days == 1 ? "giorno" : "giorni") di fila"))
                    .font(CampoFont.text(11)).foregroundStyle(s.muted)
            }
        }
    }
}

struct MinigolfCard: View {
    let store: TaskStore?
    /// The holes played in the estimates game: they open the ice and the billiards.
    let played: Int
    var stats = GolfStats.forDashboard()
    @Environment(\.colorScheme) private var scheme
    /// The detail of the chip under the pointer, and the one a click keeps open.
    @State private var hovered: MinigolfDetail?
    @State private var pinned: MinigolfDetail? = MinigolfDetail.debugOpen

    /// Before the dot gives the game away, with no game played yet.
    static func isLocked(_ store: TaskStore?, _ stats: GolfStats) -> Bool {
        !(DashDebug.golf || (store?.golfUnlocked ?? UserDefaults.standard.bool(forKey: "golfUnlocked"))) && stats.games.isEmpty
    }

    var body: some View {
        let s = CampoStyle(scheme)
        let locked = MinigolfCard.isLocked(store, stats)
        VStack(alignment: .leading, spacing: 18) {
            MinigolfRoad(played: played)
            if locked {
                hint(s)
            } else {
                roundCard(s)
                HStack(alignment: .top, spacing: 26) {
                    figures(s).frame(maxWidth: .infinity, alignment: .leading)
                    MinigolfHeatMap(traces: GolfTraces.forDashboard()).frame(width: 440)
                }
                leaderboard(s)
            }
            details(s, locked: locked)
        }
    }

    // MARK: - locked

    private func hint(_ s: CampoStyle) -> some View {
        let clicks = dotClicks
        return HStack(spacing: 14) {
            CampoLock(size: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(MinigolfCard.secret).font(CampoFont.display(16)).foregroundStyle(s.ink)
                Text(L("Clicks so far: \(clicks) of \(TaskStore.golfClicks). At \(TaskStore.golfClicks) the mini golf opens.",
                       "Clic finora: \(clicks) di \(TaskStore.golfClicks). A \(TaskStore.golfClicks) si apre il minigolf."))
                    .font(CampoFont.text(11.5)).foregroundStyle(s.muted)
                Text(L("In one burst without stopping, there's a surprise at 8 and at 69 clicks: it comes back every time you start over.",
                       "In una raffica senza fermarti, a 8 e a 69 clic c'è una sorpresa: torna ogni volta che ricominci."))
                    .font(CampoFont.text(11.5)).foregroundStyle(s.muted)
                CampoBar(share: Double(clicks) / Double(TaskStore.golfClicks)).frame(maxWidth: 280)
            }
        }
    }

    // MARK: - the round of the day

    /// Today's round as a golf score card: the cushions each hole asks for, the obstacles from hole
    /// 6, the shots with the golf's marks (a dash for a ball left alone), the cushions of the shot
    /// that went in, the hole to play next lit, and the score against par of the holes made.
    private func roundCard(_ s: CampoStyle) -> some View {
        let card = stats.round()
        let next = card.nextHole
        return VStack(alignment: .leading, spacing: 7) {
            CampoScoreCard {
                HStack(spacing: 0) {
                    Text(L("TODAY'S ROUND", "GIRO DI OGGI")).frame(width: 92, alignment: .leading).padding(.leading, 10)
                    ForEach(1...GolfRound.holes, id: \.self) { Text("\($0)").frame(maxWidth: .infinity) }
                    Text(L("TO PAR", "SUL PAR")).frame(width: 76)
                }
            } rows: {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        row(L("Asked", "Chieste"), height: 24, next: next, s) { i in
                            // From hole 10 the cushions are exact: "=3".
                            Text(card.needs.indices.contains(i) ? (GolfRound.exact(hole: i + 1) ? "=" : "") + "\(card.needs[i])" : "–")
                                .font(CampoFont.display(13)).foregroundStyle(s.ink)
                        }
                        Rectangle().fill(s.line).frame(height: 1)
                        row(L("Obstacles", "Ostacoli"), height: 16, next: next, s) { i in
                            HStack(spacing: 2) {
                                ForEach(0..<GolfRound.obstacles(hole: i + 1), id: \.self) { _ in
                                    Circle().fill(s.ink.opacity(0.55)).frame(width: 4.5, height: 4.5)
                                }
                            }
                        }
                        Rectangle().fill(s.line).frame(height: 1)
                        row(L("Shots", "Tiri"), height: 34, next: next, s) { i in
                            if i < card.shots.count {
                                if card.shots[i] > 0 { CampoShots(shots: card.shots[i]) }
                                else { Text("–").font(CampoFont.display(14)).foregroundStyle(s.todo) }
                            }
                        }
                        Rectangle().fill(s.line).frame(height: 1)
                        row(L("Cushions", "Sponde"), height: 22, next: next, s) { i in
                            if i < card.shots.count, card.shots[i] > 0 {
                                // Off an exact hole's number: red, minus 50 points a cushion.
                                Text("\(card.cushions[i])").font(CampoFont.display(12, .semibold))
                                    .foregroundStyle(card.offBy(hole: i + 1) > 0 ? s.flag : s.muted)
                            }
                        }
                    }
                    Text(card.holesMade == 0 ? "–" : CampoData.signed(card.overPar, par: true))
                        .font(CampoFont.display(22)).foregroundStyle(card.overPar < 0 && card.holesMade > 0 ? s.done : s.ink)
                        .frame(width: 76).frame(maxHeight: .infinity)
                        .overlay(alignment: .leading) { Rectangle().fill(s.line).frame(width: 1) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            (Text(roundLine(card) + " ").font(CampoFont.text(12, .semibold)).foregroundStyle(s.ink)
             + Text(L("Circle: under par (two: ace). Square: over. Dash: ball left alone. From hole 6 the ball starts at random. From 10 the ball always drops, but the cushions must be exact (=): each cushion too many or too few is worth −\(GolfRound.pointsPerCushionOff) points, and the missed hole is in red.",
                      "Cerchio: sotto il par (due: ace). Quadrato: sopra. Trattino: pallina lasciata lì. Dalla buca 6 la palla parte a caso. Dalla 10 la palla entra sempre, ma le sponde vanno fatte esatte (=): ogni sponda in più o in meno vale −\(GolfRound.pointsPerCushionOff) punti, e la buca sbagliata è in rosso."))
                .font(CampoFont.text(12)).foregroundStyle(s.muted))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Where the round stands, in a sentence: the hole to play and what it asks, or the score at the end.
    private func roundLine(_ card: GolfRoundCard) -> String {
        let lost = card.pointsLost > 0 ? L(" Cushions off: −\(card.pointsLost) points.", " Sponde sbagliate: −\(card.pointsLost) punti.") : ""
        let made = card.holesMade
        guard let next = card.nextHole else {
            let line = quip(card.overPar, made)
            return L("Round over: \(golfToPar(card.overPar)), \(made) hole\(made == 1 ? "" : "s") made out of \(GolfRound.holes).\(lost) \(line) A new round tomorrow.",
                     "Giro finito: \(golfToPar(card.overPar)), \(made) buche fatte su \(GolfRound.holes).\(lost) \(line) Domani c'è un giro nuovo.")
        }
        let need = card.needs.indices.contains(next - 1) ? card.needs[next - 1] : 0, blocks = GolfRound.obstacles(hole: next)
        let exact = GolfRound.exact(hole: next)
        let asks = (need == 0 ? (exact ? L("straight in, no cushions", "va dritta, senza sponde") : L("no cushions asked", "nessuna sponda chiesta"))
                    : L("asks for \(Golf.cushions(need, exact: exact))", "chiede \(Golf.cushions(need, exact: exact))"))
            + (blocks == 0 ? "" : L(blocks == 1 ? ", 1 obstacle" : ", \(blocks) obstacles", ", \(blocks) \(blocks == 1 ? "ostacolo" : "ostacoli")"))
        if card.shots.isEmpty { return L("Today's round starts at hole 1: \(asks).", "Il giro di oggi parte dalla buca 1: \(asks).") }
        let score = made == 0 ? L("No holes made yet", "Ancora nessuna buca fatta")
            : L("\(golfToPar(card.overPar)) with \(made) hole\(made == 1 ? "" : "s") made", "\(golfToPar(card.overPar)) con \(made) buche fatte")
        let count = card.shots.count
        return L("\(score) out of \(count) played.\(lost) Now hole \(next): \(asks).",
                 "\(score) su \(count) \(count == 1 ? "giocata" : "giocate").\(lost) Ora la buca \(next): \(asks).")
    }

    private func row<Cell: View>(_ label: String, height: CGFloat, next: Int?, _ s: CampoStyle,
                                 @ViewBuilder cell: @escaping (Int) -> Cell) -> some View {
        HStack(spacing: 0) {
            Text(label).font(CampoFont.text(12, .semibold)).foregroundStyle(s.muted)
                .frame(width: 92, alignment: .leading).padding(.leading, 10)
            ForEach(0..<GolfRound.holes, id: \.self) { i in
                // Color.clear keeps the width of a hole not played yet, whose cell is empty.
                ZStack { Color.clear; cell(i) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(next == i + 1 ? s.flag.opacity(0.12) : .clear)
                    .overlay(alignment: .leading) { Rectangle().fill(s.line).frame(width: 1) }
            }
        }
        .frame(height: height)
    }

    /// A line on the score, light: Augusta's record when it is beaten.
    private func quip(_ toPar: Int, _ holes: Int) -> String {
        guard holes > 0 else { return "" }
        if toPar <= -18 { return L("Tiger at Augusta, in 1997, finished at −18 over four rounds.", "Tiger ad Augusta, nel 1997, chiuse a −18 in quattro giri.") }
        if toPar < 0 { return L("Under par: the lawn loves you.", "Sotto il par: il prato ti vuole bene.") }
        if toPar == 0 { return L("Even par, just as the card says.", "In par, come da cartellino.") }
        return L("Over par: the lawn is uphill today.", "Sopra il par: oggi il prato è in salita.")
    }

    // MARK: - numbers and the map of the shots

    private func figures(_ s: CampoStyle) -> some View {
        let holes = stats.holes
        let combo = stats.combo
        let cushions = holes == 0 ? 0 : Double(stats.games.filter(\.sunk).reduce(0) { $0 + $1.cushions }) / Double(holes)
        return Grid(alignment: .topLeading, horizontalSpacing: 22, verticalSpacing: 16) {
            GridRow {
                MinigolfFigure(value: grouped(holes), label: holes == 1 ? L("hole", "buca") : L("holes", "buche"),
                               why: L("in \(grouped(stats.games.count)) game\(stats.games.count == 1 ? "" : "s") and \(grouped(stats.shots)) shot\(stats.shots == 1 ? "" : "s")",
                                      "in \(grouped(stats.games.count)) partite e \(grouped(stats.shots)) tiri"))
                MinigolfFigure(value: holes == 0 ? "–" : "\(CampoData.percent(Double(stats.aces) / Double(holes)))%", label: "ace",
                               why: L("\(grouped(stats.aces)) hole\(stats.aces == 1 ? "" : "s") of \(grouped(holes)) on the first shot",
                                      "\(grouped(stats.aces)) \(stats.aces == 1 ? "buca" : "buche") su \(grouped(holes)) al primo tiro"))
            }
            GridRow {
                MinigolfFigure(value: "\(stats.bestCombo)", label: L(stats.bestCombo == 1 ? "ace in a row" : "aces in a row", "ace di fila"),
                               why: L("the record combo; ", "la combo record; ")
                                   + (combo > 0 ? L("now you're on \(combo)", "ora sei a \(combo)") : L("it starts again at the next ace", "riparte dal prossimo ace")),
                               accent: combo > 0 && combo == stats.bestCombo ? s.done : nil)
                MinigolfFigure(value: holes == 0 ? "–" : Loc.decimal(cushions), label: L("cushions per hole", "sponde a buca"),
                               why: L("on average, in the shot that drops; the record is \(stats.bestCushions)",
                                      "di media nel tiro che entra; il record è \(stats.bestCushions)"))
            }
        }
    }

    // MARK: - the leaderboard

    private func leaderboard(_ s: CampoStyle) -> some View {
        HStack(alignment: .top, spacing: 26) {
            board(L("Games", "Le partite"), L("by points", "per punti"), s) {
                let best = stats.bestGames.prefix(3)
                if best.isEmpty { empty(L("The first hole opens the leaderboard.", "La prima buca apre la classifica."), s) }
                ForEach(Array(best.enumerated()), id: \.offset) { i, g in
                    place(i) {
                        CampoShots(shots: g.shots)
                        Text(L(g.cushions == 1 ? "1 cushion" : "\(g.cushions) cushions", "\(g.cushions) \(g.cushions == 1 ? "sponda" : "sponde")"))
                            .font(CampoFont.display(14)).foregroundStyle(s.ink)
                        Text(day(g.end)).font(CampoFont.text(11)).foregroundStyle(s.muted)
                        Spacer(minLength: 4)
                        Text(grouped(g.points)).font(CampoFont.display(15)).foregroundStyle(s.ink)
                    }
                }
            }
            board(L("Combos", "Le combo"), L("aces in a row", "ace di fila"), s) {
                let best = stats.combos.filter { $0.count > 1 }.prefix(3)
                if best.isEmpty { empty(L("Two aces in a row open the leaderboard.", "Due ace di fila aprono la classifica."), s) }
                ForEach(Array(best.enumerated()), id: \.offset) { i, c in
                    place(i) {
                        Text(L("\(c.count) in a row", "\(c.count) di fila")).font(CampoFont.display(15)).foregroundStyle(s.ink)
                        Spacer(minLength: 4)
                        Text(L("until \(day(c.end))", "fino al " + day(c.end))).font(CampoFont.text(11)).foregroundStyle(s.muted)
                    }
                }
            }
            board("Online", L("with the other players", "con gli altri giocatori"), s) {
                place(0) {
                    Text(L("You", "Tu")).font(CampoFont.display(15)).foregroundStyle(s.ink)
                    Text(L("first for now: you're the only player", "per ora sei primo: giochi solo tu")).font(CampoFont.text(11)).foregroundStyle(s.muted).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(grouped(stats.bestPoints)).font(CampoFont.display(15)).foregroundStyle(s.ink)
                }
                VStack(spacing: 0) {
                    ForEach(1..<3, id: \.self) { i in
                        place(i) {
                            Capsule().fill(s.ink.opacity(0.12)).frame(width: i == 1 ? 92 : 70, height: 9)
                            Spacer(minLength: 4)
                            Text("???").font(CampoFont.display(15)).foregroundStyle(s.todo)
                        }
                    }
                }
                .overlay(alignment: .trailing) {
                    CampoPlaque(title: "Coming soon", how: L("the online leaderboard", "la classifica online"), earned: true)
                        .fixedSize()
                        .rotationEffect(.degrees(-4))
                        .padding(.trailing, 30)
                }
            }
        }
    }

    private func board<Rows: View>(_ title: String, _ what: String, _ s: CampoStyle, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(title).font(CampoFont.display(16)).foregroundStyle(s.ink)
                Text(what).font(CampoFont.text(11.5)).foregroundStyle(s.muted)
            }
            .padding(.bottom, 6)
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A place on a board: the badge, gold for the first, and a thin line above.
    private func place<Content: View>(_ i: Int, @ViewBuilder content: () -> Content) -> some View {
        let s = CampoStyle(scheme)
        return HStack(spacing: 8) {
            CampoBadge(number: i + 1, color: i == 0 ? s.flag : s.done)
            content()
        }
        .frame(height: 30)
        .overlay(alignment: .top) { Rectangle().fill(s.line).frame(height: 1) }
    }

    private func empty(_ text: String, _ s: CampoStyle) -> some View {
        Text(text).font(CampoFont.text(12)).foregroundStyle(s.muted)
            .frame(height: 30)
            .overlay(alignment: .top) { Rectangle().fill(s.line).frame(height: 1) }
    }

    // MARK: - the chips

    /// The chips and, under them, the detail open: instant, no animation.
    private func details(_ s: CampoStyle, locked: Bool) -> some View {
        let open = hovered ?? pinned
        let shown = MinigolfDetail.allCases.filter { !locked || $0 != .records }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(shown) { d in chip(d, open: open == d, s) }
                Spacer(minLength: 0)
            }
            if let d = open, shown.contains(d) {
                panel(d, s)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(s.lift))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(s.line, lineWidth: 1))
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in if !inside { hovered = nil } }
        .transaction { $0.animation = nil }
    }

    /// A chip that stands up from the lawn, with its edge under it; the open one is the lane's green.
    private func chip(_ d: MinigolfDetail, open: Bool, _ s: CampoStyle) -> some View {
        let label = label(d)
        return Button { pinned = pinned == d ? nil : d } label: {
            Text(label).font(CampoFont.text(12.5, .semibold)).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(open ? s.onLane : s.ink)
                .background {
                    ZStack {
                        Capsule().fill(open ? s.laneDeep : s.edge).offset(y: 2.5)
                        Capsule().fill(open ? s.lane : s.lift)
                    }
                }
                .overlay(Capsule().strokeBorder(pinned == d ? s.flag : open ? s.laneDeep : s.edge, lineWidth: pinned == d ? 1.5 : 1))
                .padding(.bottom, 2.5)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { hovered = d } }
        .help(pinned == d ? L("Click: close", "Clic: chiudi") : L("Click: keep it open", "Clic: tienilo aperto"))
        .accessibilityLabel(label)
        .accessibilityHint(L("Opens on hover; a click keeps it open", "Si apre passandoci sopra; un clic lo tiene aperto"))
    }

    private func label(_ d: MinigolfDetail) -> String {
        switch d {
        case .records: return L("Records", "Record")
        case .achievements:
            let all = achievements
            let earned = all.filter(\.earned).count
            return L("Achievements \(earned) of \(all.count)", "Traguardi \(earned) di \(all.count)")
        case .courses: return L("Courses", "I campi")
        }
    }

    @ViewBuilder
    private func panel(_ d: MinigolfDetail, _ s: CampoStyle) -> some View {
        switch d {
        case .records: records(s)
        case .achievements:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 10)], spacing: 10) {
                ForEach(achievements) { a in CampoPlaque(title: a.title, how: a.how, earned: a.earned) }
            }
        case .courses: courses(s)
        }
    }

    /// The records worth a laugh: the points, the hardest and the fastest hole, the streak, the near misses.
    private func records(_ s: CampoStyle) -> some View {
        let hard = stats.hardestHole, fast = stats.fastestGame
        return VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .top, spacing: 22) {
            MinigolfFigure(value: grouped(stats.points), label: L("points", "punti"),
                           why: L("best game \(grouped(stats.bestPoints)); 100 a hole, +50 a cushion, ×2 on the first shot",
                                  "la partita migliore \(grouped(stats.bestPoints)); 100 a buca, +50 a sponda, ×2 al primo tiro"))
            MinigolfFigure(value: hard.map { "\($0.shots)" } ?? "–", label: hard?.shots == 1 ? L("shot", "tiro") : L("shots", "tiri"),
                           why: hard.map { h in
                               L("the toughest hole: \(h.totalCushions) cushion\(h.totalCushions == 1 ? "" : "s") and \(seconds(h.seconds)), on \(day(h.end))",
                                 "la buca più sofferta: \(h.totalCushions) sponde e \(seconds(h.seconds)), il \(day(h.end))")
                           } ?? L("no holes yet", "nessuna buca ancora"))
            MinigolfFigure(value: fast.map { seconds($0.seconds, short: true) } ?? "–", label: L("the fastest", "la più veloce"),
                           why: fast.map { f in L("from the first shot to the hole, on \(day(f.end))", "dal primo tiro alla buca, il \(day(f.end))") }
                               ?? L("no holes yet", "nessuna buca ancora"))
            MinigolfFigure(value: "\(stats.bestStreak)", label: L("in a row", "di fila"),
                           why: L("the record streak of holes without leaving the ball; now \(stats.streak)",
                                  "la serie record di buche senza lasciare la pallina; ora \(stats.streak)"))
            MinigolfFigure(value: grouped(stats.nearMisses), label: L("near misses", "quasi buche"),
                           why: L("balls that went past the hole by a whisker", "palline passate a un soffio dalla buca"))
          }
          dotFigures(s)
        }
    }

    /// The dot's clicks: in all, in this sitting, and the longest run without stopping.
    private func dotFigures(_ s: CampoStyle) -> some View {
        HStack(alignment: .top, spacing: 22) {
            MinigolfFigure(value: grouped(dotClicks), label: L("clicks on the dot", "clic sul pallino"), why: L("all time", "in tutto, da sempre"))
            MinigolfFigure(value: grouped(store?.dotSession ?? 0), label: L("this session", "in questa sessione"),
                           why: L("since you opened TaskETA", "da quando hai aperto TaskETA"))
            MinigolfFigure(value: grouped(store?.dotBestRun ?? UserDefaults.standard.integer(forKey: "dotBestRun")), label: L("record burst", "raffica record"),
                           why: L("clicks without stopping more than \(Loc.decimal(TaskStore.runGap)) seconds: at 8, 69 and 101 in the same burst the surprises come back, every time",
                                  "clic senza fermarti più di \(Loc.decimal(TaskStore.runGap)) secondi: a 8, 69 e 101 nella stessa raffica tornano le sorprese, ogni volta"))
        }
    }

    private func courses(_ s: CampoStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(CampoMinigolf.allCases, id: \.self) { c in
                (Text(c.name + ": ").font(CampoFont.text(12, .semibold)).foregroundStyle(s.ink)
                 + Text(c.need == 0 ? c.what : L("\(c.what) Opens at \(grouped(c.need)) holes played.", "\(c.what) Si apre a \(grouped(c.need)) buche fatte."))
                    .font(CampoFont.text(12)).foregroundStyle(s.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L("Holes played: every task with Claude's estimate, even a bogey. The estimates game counts them, not the mini golf. The power club, hole 4's power, shoots longer on every course.",
                   "Buche fatte: ogni task con la stima di Claude, anche un bogey. Le conta il gioco delle stime, non il minigolf. La mazza forte, potere della buca 4, tira più lungo su tutti i campi."))
                .font(CampoFont.text(12)).foregroundStyle(s.muted).fixedSize(horizontal: false, vertical: true)
            Text(L("Coming up: the billiards becomes a game within the game, at the map's bar.",
                   "In arrivo: il biliardo diventa un gioco dentro il gioco, al bar della mappa."))
                .font(CampoFont.text(12, .semibold)).foregroundStyle(s.ink)
        }
    }

    // MARK: - helpers

    private var dotClicks: Int { store?.dotClicks ?? UserDefaults.standard.integer(forKey: "dotClicks") }

    private var achievements: [GolfAchievement] {
        // "scorrimento": the slide along "in corso" of v2.3, the shortcut before the keys.
        let byKeys = ["tasti", "scorrimento"].contains(UserDefaults.standard.string(forKey: "golfUnlockedBy") ?? "")
        return stats.achievements(dotClicks: dotClicks, unlocked: !MinigolfCard.isLocked(store, stats), unlockedByKeys: byKeys)
    }

    private func day(_ time: Double) -> String {
        Date(timeIntervalSince1970: time).formatted(.dateTime.day().month(.twoDigits).hour().minute().locale(Loc.locale))
    }

    /// "68 seconds", or "0.4 s" when short ("68 secondi", "0,4 s").
    private func seconds(_ t: Double, short: Bool = false) -> String {
        if short { return t < 10 ? "\(Loc.decimal(t)) s" : clock(t) }
        let n = safeInt(t.rounded())
        return n < 600 ? L(n == 1 ? "1 second" : "\(n) seconds", "\(n) \(n == 1 ? "secondo" : "secondi")") : clock(t)
    }

    private func grouped(_ n: Int) -> String { Loc.integer(n) }

    /// The locked card's riddle, also on the small widget.
    static var secret: String {
        L("Something is hiding in the green dot of “running”.", "Nel pallino verde di «in corso» si nasconde qualcosa.")
    }
}

/// A number on the lawn: big, with its name beside it and its why under it. No paper behind.
struct MinigolfFigure: View {
    let value: String
    let label: String
    let why: String
    var accent: Color?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(CampoFont.display(28)).foregroundStyle(accent ?? s.ink).lineLimit(1)
                Text(label).font(CampoFont.display(15, .semibold)).foregroundStyle(s.ink).lineLimit(1)
            }
            Text(why).font(CampoFont.text(11.5)).foregroundStyle(s.muted).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// The three courses as a road, as on the map: the lawn, the ice, the billiards, joined by the
/// fairway. Each stretch counts the holes played from zero (out of 200 to the ice, out of 888 to
/// the billiards), so the ball never goes back to the start; "sei qui" over it.
struct MinigolfRoad: View {
    let played: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        let ice = CampoMinigolf.ghiaccio.need, pool = CampoMinigolf.biliardo.need
        let first = min(1, Double(played) / Double(ice))
        let second = min(1, Double(played) / Double(pool))
        let here = GolfRules.current().field
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                CampoCourseDrawing(course: .prato, open: true)
                lane(first, ball: played < ice, s)
                CampoCourseDrawing(course: .ghiaccio, open: played >= ice)
                lane(second, ball: played >= ice && played < pool, s)
                CampoCourseDrawing(course: .biliardo, open: played >= pool)
            }
            ZStack {
                stop(.prato, here: here, s).frame(maxWidth: .infinity, alignment: .leading)
                stop(.ghiaccio, here: here, s).frame(maxWidth: .infinity, alignment: .center)
                stop(.biliardo, here: here, s).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 8)
        }
    }

    private func stop(_ course: CampoMinigolf, here: CampoMinigolf, _ s: CampoStyle) -> some View {
        let open = played >= course.need
        let align: HorizontalAlignment = course == .prato ? .leading : course == .ghiaccio ? .center : .trailing
        return VStack(alignment: align, spacing: 1) {
            Text(course.name).font(CampoFont.display(16)).foregroundStyle(s.ink)
            if open {
                Text(course == here ? L("playing here", "si gioca qui") : L("open", "aperto")).font(CampoFont.text(11.5, .semibold)).foregroundStyle(s.done)
            } else {
                let left = course.need - played
                (Text(L(left == 1 ? "1 hole to go" : "\(Loc.integer(left)) holes to go", "tra \(Loc.integer(left)) buche fatte"))
                    .font(CampoFont.text(11.5, .semibold)).foregroundStyle(left <= 25 ? s.ink : s.muted)
                 + Text(L(" (\(Loc.integer(played)) of \(Loc.integer(course.need)))", " (\(Loc.integer(played)) di \(Loc.integer(course.need)))"))
                    .font(CampoFont.text(11)).foregroundStyle(s.muted))
            }
        }
        .multilineTextAlignment(course == .prato ? .leading : course == .ghiaccio ? .center : .trailing)
    }

    /// The fairway between two courses: green as far as the holes played, the ball at that point
    /// with "sei qui" and the holes over it.
    private func lane(_ share: Double, ball: Bool, _ s: CampoStyle) -> some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            let outer = CGRect(x: 0, y: mid - 8, width: size.width, height: 16)
            ctx.fill(Path(roundedRect: outer, cornerRadius: 8), with: .color(s.laneEdge))
            let inner = outer.insetBy(dx: 3, dy: 3)
            ctx.fill(Path(roundedRect: inner, cornerRadius: 5), with: .color(s.laneOff))
            if share > 0 {
                let w = max(10, inner.width * share)
                ctx.fill(Path(roundedRect: CGRect(x: inner.minX, y: inner.minY, width: w, height: inner.height), cornerRadius: 5), with: .color(s.lane))
            }
            if ball {
                let x = min(inner.maxX - 6, max(inner.minX + 6, inner.minX + inner.width * share))
                let r = CGRect(x: x - 5.5, y: mid - 5.5, width: 11, height: 11)
                ctx.fill(Path(ellipseIn: r), with: .color(s.ball))
                ctx.stroke(Path(ellipseIn: r), with: .color(s.ink), lineWidth: 1.2)
                let tag = ctx.resolve(Text(L("you're here, \(Loc.integer(played))", "sei qui, \(Loc.integer(played))")).font(CampoFont.display(12)).foregroundColor(s.flag))
                let half = tag.measure(in: size).width / 2
                ctx.draw(tag, at: CGPoint(x: min(size.width - half, max(half, x)), y: mid - 17))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .accessibilityHidden(true)
    }
}

/// The mini golf as a widget: the whole card (scrolling inside), or a line with the next course
/// and the challenge of the day.
struct MinigolfWidget: View {
    let store: TaskStore?
    let played: Int
    let size: WidgetSize

    var body: some View {
        let stats = GolfStats.forDashboard()
        if size.height >= 2 {
            MinigolfPlate(store: store, played: played, stats: stats, scrolls: !DashDebug.snapshot)
        } else {
            let locked = MinigolfCard.isLocked(store, stats)
            let clicks = store?.dotClicks ?? UserDefaults.standard.integer(forKey: "dotClicks")
            let next = CampoMinigolf.allCases.first { played < $0.need }
            CampoPlate(title: L("Mini golf", "Minigolf"),
                       subtitle: locked ? L("to unlock: clicks so far \(clicks) of \(TaskStore.golfClicks)", "da sbloccare: clic finora \(clicks) di \(TaskStore.golfClicks)")
                           : L("\(Loc.integer(stats.holes)) hole\(stats.holes == 1 ? "" : "s"), \(Loc.integer(stats.points)) points, record combo \(stats.bestCombo)",
                               "\(Loc.integer(stats.holes)) buche, \(Loc.integer(stats.points)) punti, combo record \(stats.bestCombo)"),
                       compact: true) {
                MinigolfLine(text: locked ? MinigolfCard.secret
                             : roundText(stats.round()) + (next.map { c -> String in
                                 let left = c.need - played
                                 return L(left == 1 ? " \(c.name): 1 hole to go." : " \(c.name): \(Loc.integer(left)) holes to go.",
                                          " \(c.name) tra \(Loc.integer(left)) buche fatte.")
                             } ?? ""))
            }
        }
    }
}

/// "Today's round: hole 7 of 18, −3 to par." ("Giro di oggi: buca 7 di 18, −3 sul par.")
private func roundText(_ card: GolfRoundCard) -> String {
    guard let next = card.nextHole else { return L("Today's round done: \(golfToPar(card.overPar)).", "Giro di oggi finito: \(golfToPar(card.overPar)).") }
    return L("Today's round: hole \(next) of \(GolfRound.holes)", "Giro di oggi: buca \(next) di \(GolfRound.holes)")
        + (card.holesMade == 0 ? "." : ", \(golfToPar(card.overPar)).")
}

/// The score against par: "−3 to par", "even par" ("−3 sul par", "par sul par").
private func golfToPar(_ n: Int) -> String {
    L(n == 0 ? "even par" : "\(CampoData.signed(n, par: true)) to par", "\(CampoData.signed(n, par: true)) sul par")
}

/// The line of a small game widget, in the map's face.
struct MinigolfLine: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text).font(CampoFont.text(12)).foregroundStyle(CampoStyle(scheme).muted).lineLimit(2)
    }
}

/// What the card keeps behind a chip.
enum MinigolfDetail: String, CaseIterable, Identifiable {
    case records, achievements, courses
    var id: String { rawValue }

    /// For a snapshot: TASKETA_DEBUG_DASH with "golf-" and a detail's name opens it (golf-records…).
    static var debugOpen: MinigolfDetail? {
        DashDebug.flags.lazy.compactMap { $0.hasPrefix("golf-") ? MinigolfDetail(rawValue: String($0.dropFirst(5))) : nil }.first
    }
}

private extension CampoStyle {
    /// A surface raised from the lawn: the open detail and the chips. At night lighter than the
    /// lawn, not darker, so it does not read as a hole.
    var lift: Color { dark ? Color(red: 0x26 / 255, green: 0x42 / 255, blue: 0x2f / 255) : plate }
    /// The edge under a chip.
    var edge: Color { dark ? Color(red: 0x12 / 255, green: 0x22 / 255, blue: 0x18 / 255) : Color(red: 0xa9 / 255, green: 0xc2 / 255, blue: 0x99 / 255) }
    var laneDeep: Color { Color(red: 0x2a / 255, green: 0x63 / 255, blue: 0x37 / 255) }
}
