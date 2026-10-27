import AppKit
import SwiftUI

// The mini golf's shots as they went on the list, for the heat map in the dashboard: where each
// shot was pulled from, the ball's way (a point every few frames) and the hole. Positions are
// shares of the list, so lists of any size lie on the same map. Recorded inside the game's own
// timer, only while the ball rolls; kept for the last 60 games under their own key. The map is
// drawn only while Analytics is open, and nothing in it moves.

/// One game on the list.
struct GolfTrace: Codable, Equatable {
    var end: Double
    /// GolfRules.id of the course: prato, ghiaccio, biliardo.
    var field: String
    var sunk: Bool
    /// The list's size in points when the game started.
    var width: Double
    var height: Double
    /// Where the hole was (the dot's place), as shares of the list.
    var hole: [Double]
    /// Each shot as x, y pairs in shares of the list: the first pair is where it was pulled from,
    /// the last where the ball stopped or dropped.
    var shots: [[Double]]

    /// The length of the ball's way in points of the list, shot by shot.
    var lengths: [Double] {
        shots.map { s in
            stride(from: 2, to: s.count - 1, by: 2).reduce(0.0) { sum, i in
                sum + hypot((s[i] - s[i - 2]) * width, (s[i + 1] - s[i - 1]) * height)
            }
        }
    }
}

enum GolfTraces {
    static let key = "golfTraces"
    static let kept = 60

    static func load(_ defaults: UserDefaults = .standard) -> [GolfTrace] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([GolfTrace].self, from: data)) ?? []
    }

    static func append(_ trace: GolfTrace, _ defaults: UserDefaults = .standard) {
        let all = Array((load(defaults) + [trace]).suffix(kept))
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
    }

    /// What the dashboard draws: the games recorded, or made-up ones with TASKETA_DEBUG_GOLF.
    static func forDashboard() -> [GolfTrace] { DashDebug.golf ? sample() : load() }

    /// A dozen games played by the game's own physics on a list of the panel's size, for snapshots.
    static func sample() -> [GolfTrace] {
        var random = GolfSeeded(state: 2026)
        let size = CGSize(width: 340, height: 230)
        func r(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b, using: &random) }
        return (0..<12).map { n in
            let hole = CGPoint(x: r(40, 300), y: r(30, 200))
            var recorder = GolfTraceRecorder()
            recorder.begin(size: size, hole: hole, field: .prato)
            var ball = GolfBall(position: CGPoint(x: r(220, 320), y: r(150, 215)), velocity: .zero, leftHole: true)
            var sunk = false
            for _ in 0..<(n % 3 + 1) where !sunk {
                let angle = r(0, 2 * .pi), speed = r(500, 1400)
                ball.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
                ball.cushions = 0
                recorder.shot(from: ball.position)
                var steps = 0
                while ball.velocity != .zero, steps < 2000 {
                    steps += 1
                    if let p = Golf.advance(&ball, dt: 1.0 / 60, size: size, holes: [hole], rules: GolfRules()) {
                        recorder.sample(p, last: true)
                        sunk = true
                        break
                    }
                    recorder.sample(ball.position)
                }
                if !sunk { recorder.sample(ball.position, last: true) }
            }
            var trace = recorder.finished(sunk: sunk)!
            trace.end = Date().timeIntervalSince1970 - Double(12 - n) * 300
            return trace
        }
    }
}

/// Writes a game while it is played: begin when the dot becomes the ball, shot at each release,
/// sample at each step of the ball, finish when the game is written in the history. A point every
/// 3 frames; a shot that grows past 60 points keeps one point in two from there on.
struct GolfTraceRecorder {
    private(set) var trace: GolfTrace?
    private var size: CGSize = .zero
    private var frame = 0
    private var every = 3
    static let perShot = 60

    mutating func begin(size: CGSize, hole: CGPoint, field: CampoMinigolf) {
        guard size.width > 0, size.height > 0 else { trace = nil; return }
        self.size = size
        trace = GolfTrace(end: 0, field: GolfRules.id(field), sunk: false, width: Double(size.width.rounded()),
                          height: Double(size.height.rounded()), hole: share(hole), shots: [])
    }

    mutating func shot(from point: CGPoint) {
        guard trace != nil else { return }
        let start = share(point)
        trace?.shots.append(start)
        frame = 0
        every = 3
    }

    /// A step of the ball; `last` keeps the point whatever the frame (where it stopped or dropped).
    mutating func sample(_ point: CGPoint, last: Bool = false) {
        guard var t = trace, !t.shots.isEmpty else { return }
        frame += 1
        guard last || frame % every == 0 else { return }
        t.shots[t.shots.count - 1] += share(point)
        var s = t.shots[t.shots.count - 1]
        if s.count > 2 * GolfTraceRecorder.perShot {
            // One point in two, the first kept: the way stays whole, the points halve.
            s = stride(from: 0, to: s.count, by: 4).flatMap { [s[$0], s[$0 + 1]] }
            t.shots[t.shots.count - 1] = s
            every *= 2
        }
        trace = t
    }

    /// The game as recorded, nil when nothing was shot.
    func finished(sunk: Bool) -> GolfTrace? {
        guard var t = trace, !t.shots.isEmpty else { return nil }
        t.sunk = sunk
        t.end = Date().timeIntervalSince1970
        return t
    }

    /// Writes the game with the others and starts empty.
    mutating func finish(sunk: Bool) {
        if let t = finished(sunk: sunk) { GolfTraces.append(t) }
        trace = nil
    }

    private func share(_ p: CGPoint) -> [Double] {
        [(Double(p.x / size.width) * 1000).rounded() / 1000, (Double(p.y / size.height) * 1000).rounded() / 1000]
    }
}

// MARK: - the heat map

/// The list seen from above, as a shot tracer: a fine grid, where the shots start glowing hotter
/// the more often, every way the ball went (the older, the fainter; the last game in the flag's
/// colour), where it dropped, and a scale in real centimetres of this screen.
struct MinigolfHeatMap: View {
    let traces: [GolfTrace]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("The shot map", "La mappa dei colpi")).font(CampoFont.display(16)).foregroundStyle(s.ink)
                Text(traces.isEmpty ? L("where you shoot and where the ball goes", "dove tiri e dove va la pallina")
                     : L("last \(traces.count) game\(traces.count == 1 ? "" : "s"), \(shotCount) shot\(shotCount == 1 ? "" : "s")",
                         "ultime \(traces.count) \(traces.count == 1 ? "partita" : "partite"), \(shotCount) tiri"))
                    .font(CampoFont.text(11.5)).foregroundStyle(s.muted)
            }
            Canvas { ctx, size in draw(&ctx, size: size, s) }
                .frame(height: 210)
                .accessibilityLabel(caption)
            Text(caption).font(CampoFont.text(11.5)).foregroundStyle(s.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shotCount: Int { traces.reduce(0) { $0 + $1.shots.count } }

    /// The list's shape: the median of the games', the panel's when there are none.
    private var aspect: Double {
        let all = traces.map { $0.width / max(1, $0.height) }.sorted()
        return all.isEmpty ? 1.5 : min(2.4, max(0.8, all[all.count / 2]))
    }

    private var listWidth: Double {
        let all = traces.map(\.width).sorted()
        return all.isEmpty ? 340 : all[all.count / 2]
    }

    /// Millimetres per point on the main screen, from its physical size.
    private var mmPerPoint: Double {
        let id = CGMainDisplayID()
        let mm = CGDisplayScreenSize(id).width, points = CGDisplayBounds(id).width
        return mm > 0 && points > 0 ? Double(mm / points) : 0.2
    }

    private var caption: String {
        guard !traces.isEmpty else {
            return L("It lights up with your next game: every shot leaves its trail, and the spots you shoot from heat up.",
                     "Si accende alla prossima partita: ogni tiro lascia la sua scia e i punti da cui tiri si scaldano.")
        }
        let lengths = traces.flatMap(\.lengths)
        let total = lengths.reduce(0, +) * mmPerPoint / 1000
        let longest = (lengths.max() ?? 0) * mmPerPoint / 10
        return L("You mostly shoot from \(corner). The ball has rolled \(Loc.decimal(total)) m on your screen, the longest shot \(safeInt(longest.rounded())) cm.",
                 "Tiri quasi sempre da \(corner). La pallina ha corso \(Loc.decimal(total)) m sul tuo schermo, il tiro più lungo \(safeInt(longest.rounded())) cm.")
    }

    /// The third of the list most shots start from, in words.
    private var corner: String {
        let starts = traces.flatMap { $0.shots.compactMap { $0.count >= 2 ? ($0[0], $0[1]) : nil } }
        var counts = [Int](repeating: 0, count: 9)
        for (x, y) in starts { counts[min(2, Int(y * 3)) * 3 + min(2, Int(x * 3))] += 1 }
        let i = counts.indices.max { counts[$0] < counts[$1] } ?? 4
        let rows = [L("top", "in alto"), L("middle", "a metà"), L("bottom", "in basso")]
        let cols = [L("left", "a sinistra"), L("centre", "al centro"), L("right", "a destra")]
        return i == 4 ? L("the middle of the list", "il centro della lista") : L("the \(rows[i / 3]) \(cols[i % 3])", "\(rows[i / 3]) \(cols[i % 3])")
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, _ s: CampoStyle) {
        // The field: the list's shape, fitted and centred.
        var w = size.width, h = w / aspect
        if h > size.height { h = size.height; w = h * aspect }
        let field = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        let screen = Path(roundedRect: field, cornerRadius: 8)
        let deep = s.dark ? Color(red: 0.05, green: 0.11, blue: 0.08) : Color(red: 0.11, green: 0.24, blue: 0.16)
        ctx.fill(screen, with: .color(deep))
        var grid = Path()
        for i in 1..<10 {
            let x = field.minX + field.width * Double(i) / 10, y = field.minY + field.height * Double(i) / 10
            grid.move(to: CGPoint(x: x, y: field.minY)); grid.addLine(to: CGPoint(x: x, y: field.maxY))
            grid.move(to: CGPoint(x: field.minX, y: y)); grid.addLine(to: CGPoint(x: field.maxX, y: y))
        }
        ctx.stroke(grid, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
        ctx.stroke(screen, with: .color(s.lane.opacity(0.8)), lineWidth: 1.5)
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: field.minX + x * field.width, y: field.minY + y * field.height) }

        guard !traces.isEmpty else {
            ctx.draw(Text(L("no shots yet", "nessun tiro ancora")).font(CampoFont.display(13, .semibold)).foregroundColor(.white.opacity(0.5)),
                     at: CGPoint(x: field.midX, y: field.midY))
            return
        }
        ctx.clip(to: screen)

        // Heat: every start adds a soft glow; where they pile up it turns from green to white hot.
        var heat = ctx
        heat.blendMode = .plusLighter
        let radius = max(10, field.width * 0.07)
        for t in traces {
            for shot in t.shots where shot.count >= 2 {
                let c = at(shot[0], shot[1])
                heat.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius)),
                          with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.62, blue: 0.2).opacity(0.38), .clear]),
                                                center: c, startRadius: 0, endRadius: radius))
            }
        }

        // The ways: thin and faint for the old games, brighter for the new ones.
        let last = traces.count - 1
        for (n, t) in traces.enumerated() {
            let fresh = Double(n + 1) / Double(traces.count)
            for shot in t.shots where shot.count >= 4 {
                var way = Path()
                way.move(to: at(shot[0], shot[1]))
                for i in stride(from: 2, to: shot.count - 1, by: 2) { way.addLine(to: at(shot[i], shot[i + 1])) }
                if n == last {
                    ctx.stroke(way, with: .color(s.flag.opacity(0.35)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    ctx.stroke(way, with: .color(s.flag), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                } else {
                    ctx.stroke(way, with: .color(.white.opacity(0.07 + 0.25 * fresh)),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                }
            }
            // Where it ended: a ring where it dropped, a small dot where it was left.
            if let shot = t.shots.last, shot.count >= 2 {
                let e = at(shot[shot.count - 2], shot[shot.count - 1])
                if t.sunk {
                    ctx.stroke(Path(ellipseIn: CGRect(x: e.x - 3.5, y: e.y - 3.5, width: 7, height: 7)),
                               with: .color(s.done.opacity(0.9)), lineWidth: 1.4)
                } else {
                    ctx.fill(Path(ellipseIn: CGRect(x: e.x - 1.5, y: e.y - 1.5, width: 3, height: 3)), with: .color(.white.opacity(0.5)))
                }
            }
        }

        // The last game's hole with its flag.
        if traces[last].hole.count == 2 {
            let cup = at(traces[last].hole[0], traces[last].hole[1])
            ctx.fill(Path(ellipseIn: CGRect(x: cup.x - 4, y: cup.y - 3, width: 8, height: 6)), with: .color(.black))
            var pole = Path()
            pole.move(to: cup); pole.addLine(to: CGPoint(x: cup.x, y: cup.y - 16))
            ctx.stroke(pole, with: .color(.white.opacity(0.9)), lineWidth: 1.2)
            var pennant = Path()
            pennant.move(to: CGPoint(x: cup.x, y: cup.y - 16))
            pennant.addLine(to: CGPoint(x: cup.x + 10, y: cup.y - 13))
            pennant.addLine(to: CGPoint(x: cup.x, y: cup.y - 10))
            pennant.closeSubpath()
            ctx.fill(pennant, with: .color(s.flag))
        }

        // The scale: real centimetres of this screen, as long as it fits a quarter of the field.
        let pointsPerCm = 10 / mmPerPoint
        let scale = Double(field.width) / listWidth
        let cm = [5.0, 2, 1].first { $0 * pointsPerCm * scale <= Double(field.width) * 0.25 } ?? 1
        let bar = CGFloat(cm * pointsPerCm * scale)
        let y = field.maxY - 10, x1 = field.maxX - 12, x0 = x1 - bar
        var ruler = Path()
        ruler.move(to: CGPoint(x: x0, y: y - 3)); ruler.addLine(to: CGPoint(x: x0, y: y))
        ruler.addLine(to: CGPoint(x: x1, y: y)); ruler.addLine(to: CGPoint(x: x1, y: y - 3))
        ctx.stroke(ruler, with: .color(.white.opacity(0.7)), lineWidth: 1)
        ctx.draw(Text("\(safeInt(cm)) cm").font(CampoFont.display(10.5, .semibold)).foregroundColor(.white.opacity(0.75)),
                 at: CGPoint(x: (x0 + x1) / 2, y: y - 9))
    }
}

// MARK: - selftest

enum GolfTraceTest {
    /// The recorder, for `--selftest` (through GolfRulesTest): the failures, empty when all pass.
    static func failures() -> [String] {
        var out: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { out.append(what) } }
        var r = GolfTraceRecorder()
        check(r.finished(sunk: false) == nil, "trace: nothing before begin")
        r.begin(size: CGSize(width: 200, height: 100), hole: CGPoint(x: 50, y: 25), field: .ghiaccio)
        check(r.finished(sunk: false) == nil, "trace: nothing before a shot")
        r.shot(from: CGPoint(x: 100, y: 50))
        for i in 1...9 { r.sample(CGPoint(x: 100 + Double(i), y: 50)) }
        r.sample(CGPoint(x: 150, y: 75), last: true)
        let t = r.finished(sunk: true)
        check(t?.hole == [0.25, 0.25] && t?.field == "ghiaccio" && t?.sunk == true, "trace: hole and course \(String(describing: t))")
        // The start, one point every 3 frames (3, 6, 9) and the last: five pairs.
        check(t?.shots.first == [0.5, 0.5, 0.515, 0.5, 0.53, 0.5, 0.545, 0.5, 0.75, 0.75], "trace: points \(String(describing: t?.shots))")
        r.shot(from: .zero)
        for i in 1...400 { r.sample(CGPoint(x: Double(i % 200), y: 10)) }
        let long = r.finished(sunk: false)?.shots.last ?? []
        check(long.count <= 2 * GolfTraceRecorder.perShot && long.count >= 40 && long[0] == 0, "trace: a long shot halves its points (\(long.count / 2))")
        // The mini golf's words in both languages (the Italian unchanged since v2).
        let it = Loc.testing(.it) { [Golf.cushions(3, exact: true), Golf.cushions(1), Golf.cushions(0, exact: true), Golf.points(-100), GolfPar.label(shots: 5)] }
        check(it == ["3 sponde esatte", "1 sponda", "nessuna sponda, dritta", "−100 punti", "Doppio bogey"], "golf words, Italian: \(it)")
        let en = Loc.testing(.en) { [Golf.cushions(3, exact: true), Golf.cushions(1), Golf.points(200), GolfPar.label(shots: 5), GolfPar.label(shots: 1)] }
        check(en == ["exactly 3 cushions", "1 cushion", "+200 points", "Double bogey", "Ace"], "golf words, English: \(en)")
        return out
    }
}
