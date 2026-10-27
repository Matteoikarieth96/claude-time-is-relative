import Foundation
import SwiftUI

// The mini golf's powers as plain numbers (docs/gioco-progressione.md, "Il minigolf: mazza, ghiaccio
// e biliardo"): the course it is played on (the lawn from the start, the ice at 200 holes played,
// the billiards at 888) and the strong club (hole 4 of Il campo closed). Picked once, when a game
// starts, from CampoNow's engine (read again only when the index changes) and kept until the game
// ends: nothing runs while the game is closed, and the 60-a-second timer still runs only while the
// ball rolls (on the ice it rolls longer, that is all). The course can also have obstacles, placed
// when the game starts and drawn still: walls and mushrooms, from hole 6 of the round of the day
// (GolfRound) or, in a free game, from 5 holes in one in a row (the combo).

struct GolfRules: Equatable {
    var field: CampoMinigolf = .prato
    var strongClub = false
    /// This game's obstacles (GolfObstacle): from hole 6 of the round of the day, or, in a free
    /// game, from the combo (none under 5 holes in one in a row).
    var obstacles: [GolfObstacle] = []
    /// The cushions the hole of the round of the day asks for (GolfRound), and whether exactly
    /// (the back nine: the ball drops anyway, the cushions off cost points).
    var holeCushions = 0
    var exactHole = false
    /// The day's twist (GolfDay), and on a windy day its wind: a direction and its strength, a
    /// share of the ball's speed added each second, so it curves the shot and still lets it stop.
    var day: GolfDay = .classico
    var wind: CGVector = .zero
    /// The portals' day: two of them, placed when the game starts; in one, out of the other.
    var portals: [CGPoint] = []
    static let portalRadius: CGFloat = 12
    /// The Pac-Man day: the left and right sides are open, out of one and back in from the other.
    var wrapSides: Bool { day == .pacman }

    /// The fastest launch: the strong club shoots longer.
    var maxSpeed: CGFloat { strongClub ? 2100 : 1500 }

    /// The pull (points) that gives the full speed, on any club.
    static let fullPull: CGFloat = 240
    /// Shorter than this a pull is only a press, not a shot.
    static let minPull: CGFloat = 6

    /// The launch speed of a pull this long: it grows with the square of the pull, so the first
    /// points give soft shots and the full speed comes only at the end. Never under a soft putt.
    func launchSpeed(pull: CGFloat) -> CGFloat {
        let x = min(1, pull / GolfRules.fullPull)
        return max(45, maxSpeed * x * x)
    }

    /// The launch of a pull (`dx, dy`: from the pointer to the ball): away from the pointer, towards
    /// it on the upside-down day; nil for a press without a pull.
    func launch(dx: CGFloat, dy: CGFloat) -> CGVector? {
        let pull = hypot(dx, dy)
        guard pull > GolfRules.minPull else { return nil }
        let speed = launchSpeed(pull: pull) * (day == .contrario ? -1 : 1)
        return CGVector(dx: dx / pull * speed, dy: dy / pull * speed)
    }

    /// A ball still rolling slowly, under a fifth of its shot's speed and under 80 points a second,
    /// can be caught and pulled again from where it is.
    static func catchable(speed: CGFloat, shot: CGFloat) -> Bool { speed <= min(shot * 0.2, 80) }

    /// Share of the speed kept after one second of rolling, and at each bounce.
    var friction: CGFloat {
        switch field {
        case .prato: return 0.55
        case .ghiaccio: return 0.85
        case .biliardo: return 0.6
        }
    }

    /// The rainbow day's ball is bouncier.
    var restitution: CGFloat {
        let course: CGFloat
        switch field {
        case .prato: course = 0.8
        case .ghiaccio: course = 0.9
        case .biliardo: course = 0.92
        }
        return day == .arcobaleno ? min(0.97, course + 0.12) : course
    }

    /// Under this speed (points a second) the ball stops.
    var stopSpeed: CGFloat { field == .ghiaccio ? 5 : 12 }
    var holeRadius: CGFloat { (field == .biliardo ? 11 : 14) * (day == .bucaXXL ? 1.6 : 1) }
    /// The magnet day: a hole pulls in the ball that has left it and rolls within this reach.
    var magnetReach: CGFloat { day == .calamita ? 64 : 0 }
    /// On the ice a ball faster than this jumps over the hole.
    var captureSpeed: CGFloat? { field == .ghiaccio ? 900 : nil }
    /// What the course asks for: the hole's cushions, at least 1 on the billiards.
    var cushionsAsked: Int { max(field == .biliardo ? 1 : 0, holeCushions) }
    /// Off fewer cushions the ball does not drop: on the billiards 1; on the round's front nine the
    /// hole's cushions; on its back nine no more than the course's own (the ball drops anyway there).
    var cushionsNeeded: Int { exactHole ? (field == .biliardo ? 1 : 0) : cushionsAsked }
    /// The billiards has six pockets; the other courses one hole, where the dot was.
    var pockets: Bool { field == .biliardo }

    /// The six pockets of a list of this size: the four corners and the middle of the long sides.
    func pocketCenters(_ size: CGSize) -> [CGPoint] {
        let i = holeRadius, w = size.width, h = size.height
        let corners = [CGPoint(x: i, y: i), CGPoint(x: w - i, y: i), CGPoint(x: i, y: h - i), CGPoint(x: w - i, y: h - i)]
        let middles = w >= h ? [CGPoint(x: w / 2, y: i), CGPoint(x: w / 2, y: h - i)]
                             : [CGPoint(x: i, y: h / 2), CGPoint(x: w - i, y: h / 2)]
        return corners + middles
    }

    /// What the board says while playing: the course in a word, and the club.
    var label: String { strongClub ? "\(GolfRules.short(field)) · " + L("power club", "mazza forte") : GolfRules.short(field) }

    static func short(_ field: CampoMinigolf) -> String {
        switch field {
        case .prato: return L("Lawn", "Prato")
        case .ghiaccio: return L("Ice", "Ghiaccio")
        case .biliardo: return L("Billiards", "Biliardo")
        }
    }

    // MARK: - the course chosen

    private static let key = "golfField"

    /// The name kept in the preferences.
    static func id(_ field: CampoMinigolf) -> String {
        switch field {
        case .prato: return "prato"
        case .ghiaccio: return "ghiaccio"
        case .biliardo: return "biliardo"
        }
    }

    /// The course of the next game: the one clicked last if it is open, else the newest open one
    /// (a course just won plays by itself).
    static func pick(open: [CampoMinigolf], chosen: String?) -> CampoMinigolf {
        open.first { id($0) == chosen } ?? open.last ?? .prato
    }

    /// The rules of a game starting now, from the index (holes played, hole 4 closed).
    /// TASKETA_DEBUG_FIELD=ghiaccio or biliardo plays that course before it opens, to try it.
    static func current(_ defaults: UserDefaults = .standard) -> GolfRules {
        let engine = CampoNow.shared.engine()
        let debug = ProcessInfo.processInfo.environment["TASKETA_DEBUG_FIELD"].flatMap { name in
            CampoMinigolf.allCases.first { id($0) == name }
        }
        var rules = GolfRules(field: debug ?? pick(open: engine.fields, chosen: defaults.string(forKey: key)), strongClub: engine.isOn(.strongClub))
        rules.day = GolfDay.debug ?? GolfDay.of()
        if rules.day == .vento { rules.wind = GolfDay.wind().vector }
        return rules
    }

    /// TASKETA_DEBUG_COMBO=N plays as if the combo were N (6: two obstacles), to try them.
    static let debugCombo = ProcessInfo.processInfo.environment["TASKETA_DEBUG_COMBO"].flatMap { Int($0) }
    /// TASKETA_DEBUG_HOLE=N plays hole N of today's round every game, without writing it on the card.
    static let debugHole = ProcessInfo.processInfo.environment["TASKETA_DEBUG_HOLE"].flatMap { Int($0) }
        .map { min(max($0, 1), GolfRound.holes) }

    /// These rules with `count` obstacles for a game starting now on a list of this size, away from
    /// the hole (where the ball starts) and from the billiards' pockets.
    func withObstacles(_ count: Int, size: CGSize, hole: CGPoint) -> GolfRules {
        var rules = self
        var clear = [(at: hole, radius: CGFloat(44))]
        if pockets { clear += pocketCenters(size).map { (at: $0, radius: CGFloat(24)) } }
        var random = SystemRandomNumberGenerator()
        rules.obstacles = GolfObstacle.place(count, in: size, clear: clear, using: &random)
        return rules
    }

    /// These rules with the portals' day's two portals: inside the list, well apart, away from the
    /// hole, the pockets and the obstacles. None when they do not fit.
    func withPortals(size: CGSize, hole: CGPoint, using random: inout some RandomNumberGenerator) -> GolfRules {
        var rules = self
        rules.portals = []
        let room = CGRect(origin: .zero, size: size).insetBy(dx: 36, dy: 30)
        guard room.width > 0, room.height > 0 else { return rules }
        let away = [(hole, CGFloat(70))] + (pockets ? pocketCenters(size).map { ($0, CGFloat(40)) } : [])
        var found: [CGPoint] = []
        for _ in 0..<120 where found.count < 2 {
            let p = CGPoint(x: .random(in: room.minX...room.maxX, using: &random), y: .random(in: room.minY...room.maxY, using: &random))
            if away.allSatisfy({ hypot(p.x - $0.0.x, p.y - $0.0.y) > $0.1 }),
               obstacles.allSatisfy({ $0.contact(p, radius: GolfRules.portalRadius + 14) == nil }),
               found.allSatisfy({ hypot(p.x - $0.x, p.y - $0.y) > 110 }) { found.append(p) }
        }
        if found.count == 2 { rules.portals = found }
        return rules
    }

    /// The shy hole's step when the ball comes near: 40 points aside, off the ball's line on the
    /// side the hole already leans to (else the other side, else straight away), kept inside the
    /// list and off the obstacles; or it stays.
    func shyStep(hole: CGPoint, ball: CGPoint, velocity: CGVector, size: CGSize) -> CGPoint {
        let speed = max(1, hypot(velocity.dx, velocity.dy))
        let ux = velocity.dx / speed, uy = velocity.dy / speed
        let side: CGFloat = (hole.x - ball.x) * uy - (hole.y - ball.y) * ux > 0 ? -1 : 1
        let room = CGRect(origin: .zero, size: size).insetBy(dx: 20, dy: 20)
        for (dx, dy) in [(-uy * side, ux * side), (uy * side, -ux * side), (ux, uy)] {
            let p = CGPoint(x: min(max(hole.x + dx * 40, room.minX), room.maxX), y: min(max(hole.y + dy * 40, room.minY), room.maxY))
            if hypot(p.x - hole.x, p.y - hole.y) > 20, obstacles.allSatisfy({ $0.contact(p, radius: holeRadius + 6) == nil }) { return p }
        }
        return hole
    }

    /// Somewhere at random for the ball to start from (from hole 6 of the round): inside the list,
    /// well away from the hole, the pockets and the obstacles. Nil when there is no such place.
    func ballStart(size: CGSize, hole: CGPoint, using random: inout some RandomNumberGenerator) -> CGPoint? {
        let room = CGRect(origin: .zero, size: size).insetBy(dx: GolfObstacle.gap, dy: GolfObstacle.gap)
        guard room.width > 0, room.height > 0 else { return nil }
        let away = [(hole, CGFloat(90))] + (pockets ? pocketCenters(size).map { ($0, CGFloat(40)) } : [])
        for _ in 0..<80 {
            let p = CGPoint(x: .random(in: room.minX...room.maxX, using: &random), y: .random(in: room.minY...room.maxY, using: &random))
            if away.allSatisfy({ hypot(p.x - $0.0.x, p.y - $0.0.y) > $0.1 }),
               obstacles.allSatisfy({ $0.contact(p, radius: Golf.radius + 12) == nil }),
               portals.allSatisfy({ hypot(p.x - $0.x, p.y - $0.y) > GolfRules.portalRadius + 24 }) { return p }
        }
        return nil
    }

    /// A click on the course's name: the next open course, from the next game on.
    static func choose(after field: CampoMinigolf, _ defaults: UserDefaults = .standard) -> CampoMinigolf {
        let open = CampoNow.shared.engine().fields
        let next = open.isEmpty ? .prato : open[((open.firstIndex(of: field) ?? -1) + 1) % open.count]
        defaults.set(id(next), forKey: key)
        return next
    }

    /// The colours of the ball and of the course under the list while playing.
    func ball(_ s: CampoStyle) -> [Color] {
        switch field {
        case .prato: return [Color(red: 0.55, green: 0.95, blue: 0.7), Pace.green.color]
        case .ghiaccio: return [.white, Color(red: 0.62, green: 0.82, blue: 0.95)]
        case .biliardo: return [.white, Color(white: 0.82)]
        }
    }

    func ground(_ s: CampoStyle) -> Color? {
        switch field {
        case .prato: return nil
        case .ghiaccio: return s.ice[1].opacity(0.22)
        case .biliardo: return s.felt.opacity(0.2)
        }
    }
}

extension Golf {
    /// One step of the ball under these rules: moves, bounces off the edges of the list and the
    /// obstacles, slows down. The hole it dropped in on the way, if any: only once it has been away
    /// from them, on the ice only if slow enough, on the billiards only off a cushion.
    static func advance(_ ball: inout GolfBall, dt: CGFloat, size: CGSize, holes: [CGPoint], rules: GolfRules) -> CGPoint? {
        // The obstacles are thin: with them the step is cut in pieces no longer than the ball's
        // radius, so a fast ball never goes through one.
        let length = hypot(ball.velocity.dx, ball.velocity.dy) * dt
        let pieces = rules.obstacles.isEmpty ? 1 : max(1, Int((length / radius).rounded(.up)))
        for _ in 0..<pieces {
            if let sunk = step(&ball, dt: dt / CGFloat(pieces), size: size, holes: holes, rules: rules) { return sunk }
            if ball.velocity == .zero { break }
        }
        return nil
    }

    private static func step(_ ball: inout GolfBall, dt: CGFloat, size: CGSize, holes: [CGPoint], rules: GolfRules) -> CGPoint? {
        let from = ball.position
        let speed = hypot(ball.velocity.dx, ball.velocity.dy)
        // Away from the holes before this step: a hard shot from the hole used to cross it on the
        // first step and drop back in at once, a hole in one without leaving it.
        let wasAway = ball.leftHole
        var p = CGPoint(x: from.x + ball.velocity.dx * dt, y: from.y + ball.velocity.dy * dt)
        var v = ball.velocity
        let r = radius, e = rules.restitution
        let maxX = max(r, size.width - r), maxY = max(r, size.height - r)
        // Through an open side or a portal the ball jumps: no segment across the list for the hole.
        var jumped = false
        if rules.wrapSides {
            if p.x < 0 { p.x += size.width; jumped = true }
            if p.x > size.width { p.x -= size.width; jumped = true }
        } else {
            if p.x < r { p.x = min(maxX, 2 * r - p.x); v.dx = -v.dx * e; ball.cushions += 1 }
            if p.x > maxX { p.x = max(r, 2 * maxX - p.x); v.dx = -v.dx * e; ball.cushions += 1 }
        }
        if p.y < r { p.y = min(maxY, 2 * r - p.y); v.dy = -v.dy * e; ball.cushions += 1 }
        if p.y > maxY { p.y = max(r, 2 * maxY - p.y); v.dy = -v.dy * e; ball.cushions += 1 }
        // An obstacle pushes the ball back out and bounces it like an edge: a cushion too.
        for o in rules.obstacles {
            guard let hit = o.contact(p, radius: r) else { continue }
            p = hit.point
            let along = v.dx * hit.normal.dx + v.dy * hit.normal.dy
            if along < 0 {
                v = CGVector(dx: v.dx - (1 + e) * along * hit.normal.dx, dy: v.dy - (1 + e) * along * hit.normal.dy)
                ball.cushions += 1
            }
        }
        // The portals: in one, out of the other with the same speed; in again only once away from both.
        if rules.portals.count == 2 {
            let near = rules.portals.firstIndex { hypot(p.x - $0.x, p.y - $0.y) < GolfRules.portalRadius }
            if let i = near, !ball.inPortal {
                p = rules.portals[1 - i]
                ball.inPortal = true
                jumped = true
            } else if near == nil, rules.portals.allSatisfy({ hypot(p.x - $0.x, p.y - $0.y) > GolfRules.portalRadius + 4 }) {
                ball.inPortal = false
            }
        }
        // The day's wind curves the shot, more the faster the ball, so it still stops.
        if rules.wind != .zero {
            v = CGVector(dx: v.dx + rules.wind.dx * speed * dt, dy: v.dy + rules.wind.dy * speed * dt)
        }
        // The magnet day: a hole pulls in a ball that has left it, harder the closer.
        if rules.magnetReach > 0, wasAway {
            for h in holes {
                let dx = h.x - p.x, dy = h.y - p.y, d = hypot(dx, dy)
                guard d > 1, d < rules.magnetReach else { continue }
                let pull = 900 * (1 - d / rules.magnetReach) * dt
                v = CGVector(dx: v.dx + dx / d * pull, dy: v.dy + dy / d * pull)
            }
        }
        let keep = pow(rules.friction, dt)
        v = CGVector(dx: v.dx * keep, dy: v.dy * keep)
        if hypot(v.dx, v.dy) < rules.stopSpeed { v = .zero }
        ball.position = p
        ball.velocity = v
        if !ball.leftHole && holes.allSatisfy({ hypot(p.x - $0.x, p.y - $0.y) > 28 }) { ball.leftHole = true }
        guard wasAway, ball.cushions >= rules.cushionsNeeded, speed <= (rules.captureSpeed ?? .infinity) else { return nil }
        return holes.first { distance(from: $0, toSegment: jumped ? p : from, p) < rules.holeRadius }
    }
}

extension Golf {
    /// The way a shot would go under these rules, as far as its `bounces`-th bounce and a little
    /// past it, its stop or the hole: the aim's line with its bounces. The same physics, run only
    /// while aiming.
    static func path(_ ball: GolfBall, size: CGSize, holes: [CGPoint], rules: GolfRules,
                     bounces: Int = 2) -> (points: [CGPoint], bounces: [CGPoint], sunk: Bool) {
        var b = ball
        b.cushions = 0
        var points = [b.position], hits: [CGPoint] = []
        var past = 0
        for _ in 0..<720 {
            let before = b.cushions
            if let hole = advance(&b, dt: 1.0 / 120, size: size, holes: holes, rules: rules) {
                points.append(hole)
                return (points, hits, true)
            }
            points.append(b.position)
            if b.cushions > before { hits.append(b.position) }
            if hits.count >= bounces { past += 1 }
            if past > 12 || b.velocity == .zero { break }
        }
        return (points, hits, false)
    }
}

// MARK: - the day

/// The day's twist on the mini golf: one a day, the same all day, drawn from the day itself (not
/// the challenge's draw). Read when a game starts, like the course, so nothing runs at rest.
/// TASKETA_DEBUG_DAY=vento (or another name) plays that day.
enum GolfDay: String, CaseIterable {
    case classico, arcobaleno, vento, calamita, bucaXXL = "buca-xxl", contrario, caddie, portali, pacman, timida

    var emoji: String {
        switch self {
        case .classico: return "⛳"
        case .arcobaleno: return "🌈"
        case .vento: return "🌬️"
        case .calamita: return "🧲"
        case .bucaXXL: return "🕳️"
        case .contrario: return "🔄"
        case .caddie: return "📐"
        case .portali: return "🌀"
        case .pacman: return "🕹️"
        case .timida: return "🙈"
        }
    }

    var title: String {
        switch self {
        case .classico: return L("Classic day", "Giorno classico")
        case .arcobaleno: return L("Rainbow ball", "Pallina arcobaleno")
        case .vento: return L("Windy day", "Giorno di vento")
        case .calamita: return L("Magnet hole", "Buca calamita")
        case .bucaXXL: return L("XXL hole", "Buca XXL")
        case .contrario: return L("Reverse slingshot", "Fionda al contrario")
        case .caddie: return L("Caddie's aim", "Mira del caddie")
        case .portali: return L("Portals day", "Giorno dei portali")
        case .pacman: return L("Pac-Man day", "Giorno Pac-Man")
        case .timida: return L("Shy hole", "Buca timida")
        }
    }

    /// The title in the middle of a sentence ("Today: windy day, …"): lowercased, except the English
    /// Pac-Man and XXL, which keep their capitals.
    var titleInSentence: String {
        switch (Loc.lang, self) {
        case (.en, .pacman), (.en, .bucaXXL): return title
        default: return title.lowercased()
        }
    }

    /// What it does, in a few words (the wind with its arrow).
    func how(_ date: Date = Date()) -> String {
        switch self {
        case .classico: return L("good old mini golf, no surprises", "il minigolf di sempre, niente sorprese")
        case .arcobaleno: return L("the ball turns rainbow, hops, leaves a trail and bounces more",
                                   "la pallina cambia colore, saltella, lascia la scia e rimbalza di più")
        case .vento:
            let arrow = GolfDay.wind(date).arrow
            return L("the wind blows towards \(arrow) and curves your shots", "il vento soffia verso \(arrow) e curva i tiri")
        case .calamita: return L("the hole pulls in the ball when it rolls close", "la buca attira la pallina che le passa vicino")
        case .bucaXXL: return L("the hole is bigger than usual", "la buca è più grande del solito")
        case .contrario: return L("the ball goes the way you pull, not the opposite way",
                                  "la pallina parte verso dove tiri, non dalla parte opposta")
        case .caddie: return L("while you aim you see where the ball goes, up to the second bounce",
                               "mentre tiri vedi dove va la pallina, fino al secondo rimbalzo")
        case .portali: return L("two portals: the ball goes into one and out of the other, just as fast",
                                "due portali: la pallina entra in uno ed esce dall'altro, con la stessa spinta")
        case .pacman: return L("the sides are open: the ball goes out one side and comes back in the other",
                               "i lati sono aperti: la pallina esce da una parte e rientra dall'altra")
        case .timida: return L("when the ball comes near, the hole takes a step back (once a shot)",
                               "quando la pallina si avvicina, la buca fa un passo indietro (una volta per tiro)")
        }
    }

    /// The strip's mark: the emoji, with the wind's arrow on a windy day.
    func mark(_ date: Date = Date()) -> String { self == .vento ? "\(emoji) \(GolfDay.wind(date).arrow)" : emoji }

    private static func draw(_ date: Date) -> GolfSeeded {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return GolfSeeded(state: UInt64(day) &* 0xA24B_AED4_963E_E407 &+ 77)
    }

    static func of(_ date: Date = Date()) -> GolfDay {
        var random = draw(date)
        return allCases[Int(random.next() % UInt64(allCases.count))]
    }

    /// A windy day's wind: one of the 8 directions, the same all day, a share of the speed a second.
    static func wind(_ date: Date = Date()) -> (vector: CGVector, arrow: String) {
        var random = draw(date)
        _ = random.next()
        let i = Int(random.next() % 8), angle = CGFloat(i) * .pi / 4, strength: CGFloat = 0.4
        return (CGVector(dx: cos(angle) * strength, dy: sin(angle) * strength), ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"][i])
    }

    static let debug = ProcessInfo.processInfo.environment["TASKETA_DEBUG_DAY"].flatMap { GolfDay(rawValue: $0) }
}

// MARK: - the obstacles

/// An obstacle on the course, as in a real mini golf: a wooden wall or a round mushroom. One comes
/// at 5 holes in one in a row, one more at each hole in one after, at most 4; they stay while the
/// combo holds, in new places every game, on every course. A bounce off one is a cushion.
struct GolfObstacle: Equatable {
    enum Kind { case wall, mushroom }
    var kind: Kind
    /// The wall's board, or the square around the mushroom.
    var frame: CGRect

    static let wallLength: CGFloat = 60, wallThickness: CGFloat = 8, mushroomRadius: CGFloat = 10
    /// Room kept free for the ball, between two obstacles and from the edges.
    static let gap: CGFloat = 20

    static func count(combo: Int) -> Int { combo < 5 ? 0 : min(4, combo - 4) }

    /// Where a ball of this radius touching it goes back out to, and in which direction; nil when
    /// it does not touch it.
    func contact(_ p: CGPoint, radius r: CGFloat) -> (point: CGPoint, normal: CGVector)? {
        let center: CGPoint, reach: CGFloat
        switch kind {
        case .mushroom:
            center = CGPoint(x: frame.midX, y: frame.midY)
            reach = frame.width / 2 + r
        case .wall:
            // The nearest point of the board: a side, or a corner, which bounces like a round one.
            center = CGPoint(x: min(max(p.x, frame.minX), frame.maxX), y: min(max(p.y, frame.minY), frame.maxY))
            reach = r
            if center == p { // the centre inside the board: out by the nearest side
                let sides = [(p.x - frame.minX, CGVector(dx: -1, dy: 0)), (frame.maxX - p.x, CGVector(dx: 1, dy: 0)),
                             (p.y - frame.minY, CGVector(dx: 0, dy: -1)), (frame.maxY - p.y, CGVector(dx: 0, dy: 1))]
                let (depth, n) = sides.min { $0.0 < $1.0 }!
                return (CGPoint(x: p.x + n.dx * (depth + r), y: p.y + n.dy * (depth + r)), n)
            }
        }
        let dx = p.x - center.x, dy = p.y - center.y, d = hypot(dx, dy)
        guard d < reach else { return nil }
        let n = d > 0 ? CGVector(dx: dx / d, dy: dy / d) : CGVector(dx: 0, dy: -1)
        return (CGPoint(x: center.x + n.dx * reach, y: center.y + n.dy * reach), n)
    }

    /// `count` obstacles at random on a list of this size, a wall first and then a mushroom in turn,
    /// away from the edges, from each other and from the given spots. Fewer when they do not fit.
    static func place(_ count: Int, in size: CGSize, clear: [(at: CGPoint, radius: CGFloat)],
                      using random: inout some RandomNumberGenerator) -> [GolfObstacle] {
        let room = CGRect(origin: .zero, size: size).insetBy(dx: gap, dy: gap)
        var out: [GolfObstacle] = []
        for i in 0..<count {
            for _ in 0..<60 {
                let kind: Kind = i % 2 == 0 ? .wall : .mushroom
                let w: CGFloat, h: CGFloat
                switch kind {
                case .mushroom: (w, h) = (mushroomRadius * 2, mushroomRadius * 2)
                case .wall: (w, h) = Bool.random(using: &random) ? (wallLength, wallThickness) : (wallThickness, wallLength)
                }
                guard room.width > w, room.height > h else { continue }
                let o = GolfObstacle(kind: kind, frame: CGRect(x: .random(in: room.minX...(room.maxX - w), using: &random),
                                                               y: .random(in: room.minY...(room.maxY - h), using: &random),
                                                               width: w, height: h))
                guard clear.allSatisfy({ o.contact($0.at, radius: $0.radius) == nil }),
                      out.allSatisfy({ !$0.frame.insetBy(dx: -gap, dy: -gap).intersects(o.frame) }) else { continue }
                out.append(o)
                break
            }
        }
        return out
    }
}

// MARK: - selftest

enum GolfRulesTest {
    /// The physics of each course, for `--selftest`: the failures, empty when all pass.
    static func failures() -> [String] {
        var out: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { out.append(what) } }
        let lawn = GolfRules(), ice = GolfRules(field: .ghiaccio), pool = GolfRules(field: .biliardo)
        let club = GolfRules(strongClub: true)

        // The lawn is today's game, number for number; the strong club shoots longer on any course.
        check(lawn.maxSpeed == 1500 && lawn.friction == 0.55 && lawn.restitution == 0.8
              && lawn.stopSpeed == 12 && lawn.holeRadius == 14 && lawn.captureSpeed == nil && !lawn.pockets, "lawn numbers")
        check(club.maxSpeed == 2100 && GolfRules(field: .biliardo, strongClub: true).maxSpeed == 2100, "strong club")

        // Soft shots: the speed grows with the square of the pull, full only at the end of it.
        check(lawn.launchSpeed(pull: 240) == 1500 && lawn.launchSpeed(pull: 400) == 1500 && club.launchSpeed(pull: 240) == 2100
              && lawn.launchSpeed(pull: 120) == 375 && lawn.launchSpeed(pull: 216) < 1500 * 0.82 && lawn.launchSpeed(pull: 8) == 45,
              "soft shots: \(lawn.launchSpeed(pull: 120)), \(lawn.launchSpeed(pull: 216))")
        // A ball rolling slowly can be caught, a fast one cannot.
        check(GolfRules.catchable(speed: 60, shot: 1500) && !GolfRules.catchable(speed: 200, shot: 1500)
              && GolfRules.catchable(speed: 15, shot: 100) && !GolfRules.catchable(speed: 30, shot: 100), "catching a rolling ball")

        // The days: one a day, the same all day, every kind within a few months, the wind one of 8.
        let today = Date(timeIntervalSince1970: 1_793_000_000)
        let kinds = Set((0..<120).map { GolfDay.of(today.addingTimeInterval(Double($0) * 86400)) })
        check(GolfDay.of(today) == GolfDay.of(today.addingTimeInterval(60)) && kinds.count == GolfDay.allCases.count, "days: \(kinds.count)")
        check(["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"].contains(GolfDay.wind(today).arrow)
              && abs(hypot(GolfDay.wind(today).vector.dx, GolfDay.wind(today).vector.dy) - 0.4) < 0.001, "the day's wind")
        // The rainbow ball bounces more, the XXL hole is bigger, the upside-down sling shoots towards the pull.
        check(GolfRules(day: .arcobaleno).restitution > lawn.restitution && GolfRules(day: .bucaXXL).holeRadius > 22
              && GolfRules(day: .contrario).launch(dx: 100, dy: 0).map { $0.dx < 0 } == true
              && lawn.launch(dx: 100, dy: 0).map { $0.dx > 0 } == true && lawn.launch(dx: 3, dy: 0) == nil, "the days' numbers")
        // The wind curves a shot and still lets it stop.
        var blown = GolfBall(position: CGPoint(x: 10, y: 500), velocity: CGVector(dx: 600, dy: 0), leftHole: true)
        var steps = 0
        while blown.velocity != .zero && steps < 20_000 {
            _ = Golf.advance(&blown, dt: 1.0 / 60, size: CGSize(width: 100_000, height: 1000), holes: [], rules: GolfRules(wind: CGVector(dx: 0, dy: 0.4)))
            steps += 1
        }
        check(blown.velocity == .zero && blown.position.y > 540, "the wind curves the shot: \(blown.position), \(steps) steps")
        // The magnet hole pulls in a ball passing 30 points from it; on a plain day it rolls on.
        func passBy(_ rules: GolfRules) -> Bool {
            var ball = GolfBall(position: CGPoint(x: 20, y: 50), velocity: CGVector(dx: 150, dy: 0), leftHole: true)
            for _ in 0..<600 {
                if Golf.advance(&ball, dt: 1.0 / 60, size: CGSize(width: 3000, height: 200), holes: [CGPoint(x: 120, y: 80)], rules: rules) != nil { return true }
                if ball.velocity == .zero { return false }
            }
            return false
        }
        check(passBy(GolfRules(day: .calamita)) && !passBy(lawn), "the magnet hole")
        // The aim's line: off the right edge and back into the hole, one bounce on the way; or up to two.
        let rebound = Golf.path(GolfBall(position: CGPoint(x: 100, y: 100), velocity: CGVector(dx: 500, dy: 0)),
                             size: CGSize(width: 300, height: 200), holes: [CGPoint(x: 100, y: 100)], rules: lawn)
        check(rebound.sunk && rebound.bounces.count == 1 && (rebound.bounces.first?.x ?? 0) > 280, "aim: back into the hole \(rebound.bounces)")
        let long = Golf.path(GolfBall(position: CGPoint(x: 100, y: 100), velocity: CGVector(dx: 1400, dy: 700), leftHole: true),
                             size: CGSize(width: 300, height: 200), holes: [], rules: lawn)
        check(!long.sunk && long.bounces.count == 2, "aim: two bounces \(long.bounces.count)")
        // The portals: in one, out of the other with the same speed, and in again only once away.
        var portaled = GolfRules(day: .portali)
        portaled.portals = [CGPoint(x: 80, y: 50), CGPoint(x: 250, y: 150)]
        var traveller = GolfBall(position: CGPoint(x: 50, y: 50), velocity: CGVector(dx: 300, dy: 0), leftHole: true)
        for _ in 0..<10 { _ = Golf.advance(&traveller, dt: 1.0 / 60, size: CGSize(width: 400, height: 200), holes: [], rules: portaled) }
        check(traveller.position.x > 250 && abs(traveller.position.y - 150) < 1 && traveller.velocity.dx > 0 && traveller.cushions == 0,
              "through a portal: \(traveller)")
        // Pac-Man: out of the right side, back in from the left, and no cushion.
        var pac = GolfBall(position: CGPoint(x: 295, y: 100), velocity: CGVector(dx: 300, dy: 0), leftHole: true)
        _ = Golf.advance(&pac, dt: 0.1, size: CGSize(width: 300, height: 200), holes: [], rules: GolfRules(day: .pacman))
        check(pac.position.x < 40 && pac.velocity.dx > 0 && pac.cushions == 0, "Pac-Man sides: \(pac)")
        // The shy hole steps aside, off the ball's line, on the side it leans to; by an edge, the other side.
        let right = CGVector(dx: 300, dy: 0), field = CGSize(width: 300, height: 200)
        let shy = lawn.shyStep(hole: CGPoint(x: 150, y: 110), ball: CGPoint(x: 120, y: 100), velocity: right, size: field)
        let cornered = lawn.shyStep(hole: CGPoint(x: 150, y: 175), ball: CGPoint(x: 120, y: 172), velocity: right, size: field)
        check(abs(shy.x - 150) < 0.5 && abs(shy.y - 150) < 0.5 && abs(cornered.y - 135) < 0.5, "the shy hole steps aside: \(shy) \(cornered)")
        var portalRandom = GolfSeeded(state: 11)
        let twoPortals = lawn.withPortals(size: CGSize(width: 360, height: 200), hole: CGPoint(x: 60, y: 100), using: &portalRandom).portals
        check(twoPortals.count == 2 && twoPortals.allSatisfy { hypot($0.x - 60, $0.y - 100) > 70 }
              && hypot(twoPortals[0].x - twoPortals[1].x, twoPortals[0].y - twoPortals[1].y) > 110, "portals placed: \(twoPortals)")

        // The same shot rolls farther on the ice than on the lawn, and stops later.
        func roll(_ rules: GolfRules) -> (distance: CGFloat, steps: Int) {
            var ball = GolfBall(position: CGPoint(x: 10, y: 500), velocity: CGVector(dx: 300, dy: 0), leftHole: true)
            var steps = 0
            while ball.velocity != .zero && steps < 20_000 {
                _ = Golf.advance(&ball, dt: 1.0 / 60, size: CGSize(width: 100_000, height: 1000), holes: [], rules: rules)
                steps += 1
            }
            return (ball.position.x - 10, steps)
        }
        let onLawn = roll(lawn), onIce = roll(ice)
        check(onIce.distance > 3 * onLawn.distance && onIce.steps > onLawn.steps, "ice glides: \(onIce) vs \(onLawn)")

        // On the ice a fast ball jumps the hole, a slow one drops; on the lawn the fast one drops too.
        func pass(_ speed: CGFloat, _ rules: GolfRules) -> Bool {
            var ball = GolfBall(position: CGPoint(x: 20, y: 50), velocity: CGVector(dx: speed, dy: 0), leftHole: true)
            return Golf.advance(&ball, dt: 40 / speed, size: CGSize(width: 3000, height: 100), holes: [CGPoint(x: 40, y: 51)], rules: rules) != nil
        }
        check(!pass(1200, ice) && pass(400, ice) && pass(1200, lawn), "ice: fast over the hole")

        // The billiards: six pockets, and one counts only off a cushion.
        let pockets = pool.pocketCenters(CGSize(width: 360, height: 200))
        check(pockets.count == 6 && pockets.contains(CGPoint(x: 180, y: 11)) && pockets.contains(CGPoint(x: 349, y: 189)), "pockets: \(pockets)")
        check(GolfRules(field: .biliardo).pocketCenters(CGSize(width: 200, height: 400)).contains(CGPoint(x: 11, y: 200)), "pockets on tall lists")
        var straight = GolfBall(position: CGPoint(x: 60, y: 11), velocity: CGVector(dx: -400, dy: 0), leftHole: true)
        check(Golf.advance(&straight, dt: 0.1, size: CGSize(width: 360, height: 200), holes: pockets, rules: pool) == nil, "billiards: no pocket without a cushion")
        var bank = GolfBall(position: CGPoint(x: 60, y: 11), velocity: CGVector(dx: -400, dy: 0), leftHole: true, cushions: 1)
        check(Golf.advance(&bank, dt: 0.1, size: CGSize(width: 360, height: 200), holes: pockets, rules: pool) == CGPoint(x: 11, y: 11),
              "billiards: a pocket off a cushion")
        check(pool.restitution == 0.92 && pool.friction == 0.6 && pool.holeRadius == 11 && pool.cushionsNeeded == 1, "billiards numbers")

        // A course just won plays by itself; one clicked stays, while it is open.
        check(GolfRules.pick(open: [.prato, .ghiaccio], chosen: nil) == .ghiaccio
              && GolfRules.pick(open: [.prato, .ghiaccio], chosen: "prato") == .prato
              && GolfRules.pick(open: [.prato], chosen: "biliardo") == .prato, "course picked")

        // A hard shot from the hole is not a hole in one: the ball has to leave it first.
        for (rules, speed, dt) in [(club, CGFloat(2100), CGFloat(1.0 / 60)), (lawn, 1500, 0.05)] {
            var shot = GolfBall(position: CGPoint(x: 100, y: 100), velocity: CGVector(dx: speed, dy: 0))
            check(Golf.advance(&shot, dt: dt, size: CGSize(width: 360, height: 200), holes: [CGPoint(x: 100, y: 100)], rules: rules) == nil
                  && shot.leftHole, "no hole in one off a hard shot from the hole (\(speed))")
        }

        // The combo: holes in one in a row at the end, and the longest run.
        var stats = GolfStats()
        for shots in [1, 1, 1, 2, 1, 1] { _ = stats.finish(start: 0, end: 5, shots: shots, sunk: true, cushions: 1, totalCushions: 1, nearMisses: 0) }
        let last = stats.finish(start: 0, end: 5, shots: 1, sunk: true, cushions: 1, totalCushions: 1, nearMisses: 0)
        check(stats.combo == 3 && stats.bestCombo == 3 && last.combo == 3, "combo: \(stats.combo), best \(stats.bestCombo)")
        _ = stats.finish(start: 0, end: 5, shots: 1, sunk: false, cushions: 0, totalCushions: 0, nearMisses: 0)
        check(stats.combo == 0 && stats.bestCombo == 3, "combo broken by a lost game")

        // The obstacles: one at 5 holes in one in a row, one more at each, at most 4.
        check([0, 4, 5, 6, 7, 8, 12].map(GolfObstacle.count) == [0, 0, 1, 2, 3, 4, 4], "obstacles by combo")

        // Thrown at a wall or a mushroom at full speed in a slow frame, the ball bounces back off it
        // (it does not go through) and that is a cushion.
        let wall = GolfObstacle(kind: .wall, frame: CGRect(x: 200, y: 60, width: 8, height: 60))
        let mushroom = GolfObstacle(kind: .mushroom, frame: CGRect(x: 190, y: 80, width: 20, height: 20))
        for o in [wall, mushroom] {
            var rules = club
            rules.obstacles = [o]
            var ball = GolfBall(position: CGPoint(x: 120, y: 90), velocity: CGVector(dx: 2100, dy: 0), leftHole: true)
            _ = Golf.advance(&ball, dt: 0.05, size: CGSize(width: 400, height: 200), holes: [], rules: rules)
            check(ball.velocity.dx < 0 && ball.position.x < 194 && ball.cushions == 1, "bounce off a \(o.kind): \(ball)")
        }
        // Off the side of a mushroom it goes off sideways, and a wall's corner deflects it too.
        var glance = GolfBall(position: CGPoint(x: 150, y: 84), velocity: CGVector(dx: 600, dy: 0), leftHole: true)
        var withOne = lawn
        withOne.obstacles = [mushroom]
        for _ in 0..<10 { _ = Golf.advance(&glance, dt: 1.0 / 60, size: CGSize(width: 400, height: 200), holes: [], rules: withOne) }
        check(glance.velocity.dy < 0 && glance.cushions == 1, "glancing off a mushroom: \(glance)")
        var corner = GolfBall(position: CGPoint(x: 150, y: 57), velocity: CGVector(dx: 600, dy: 0), leftHole: true)
        withOne.obstacles = [wall]
        for _ in 0..<10 { _ = Golf.advance(&corner, dt: 1.0 / 60, size: CGSize(width: 400, height: 200), holes: [], rules: withOne) }
        check(corner.velocity.dy < 0 && corner.cushions == 1, "off a wall's corner: \(corner)")

        // Placed at random (the same every run here): walls and mushrooms in turn, inside the list
        // with room for the ball, apart, and away from the hole; on the billiards from the pockets.
        var random = GolfSeeded(state: 7)
        let size = CGSize(width: 360, height: 200), hole = CGPoint(x: 60, y: 100)
        let placed = GolfObstacle.place(4, in: size, clear: [(at: hole, radius: 44)], using: &random)
        check(placed.map(\.kind) == [.wall, .mushroom, .wall, .mushroom], "obstacles placed: \(placed.count)")
        check(placed.allSatisfy { $0.contact(hole, radius: 44) == nil && CGRect(origin: .zero, size: size).insetBy(dx: 20, dy: 20).contains($0.frame) },
              "obstacles away from the hole and the edges")
        check(placed.indices.allSatisfy { i in placed.indices.allSatisfy { j in i == j || !placed[i].frame.insetBy(dx: -20, dy: -20).intersects(placed[j].frame) } },
              "obstacles apart")
        check(GolfObstacle.place(4, in: CGSize(width: 90, height: 40), clear: [], using: &random).isEmpty, "a tiny list: no obstacles")
        let table = pool.withObstacles(4, size: size, hole: hole)
        check(!table.obstacles.isEmpty && table.obstacles.allSatisfy { o in pockets.allSatisfy { o.contact($0, radius: 24) == nil } },
              "obstacles away from the pockets")
        check(lawn.withObstacles(GolfObstacle.count(combo: 4), size: size, hole: hole).obstacles.isEmpty, "no obstacles under 5")

        // The round of the day: 18 holes of 0 to 5 cushions, the same all day, another the next day;
        // from hole 6 one obstacle, one more every 3 holes, at most 4, and the ball starts at random.
        let day = Date(timeIntervalSince1970: 1_793_000_000)
        let round = GolfRound.of(day), again = GolfRound.of(day.addingTimeInterval(60)), next = GolfRound.of(day.addingTimeInterval(86400))
        check(round.needs.count == 18 && round.needs.allSatisfy { (0...5).contains($0) } && Set(round.needs).count >= 3, "round: \(round.needs)")
        check(round == again && next.needs != round.needs && next.day != round.day, "a new round every day")
        check([1, 5, 6, 8, 9, 12, 15, 18].map(GolfRound.obstacles) == [0, 0, 1, 1, 2, 3, 4, 4]
              && !GolfRound.ballAtRandom(hole: 5) && GolfRound.ballAtRandom(hole: 6), "round: from hole 6")

        // A hole drops only off at least the cushions it asks for; on the billiards at least one.
        var asks = GolfRules()
        asks.holeCushions = 3
        var two = GolfBall(position: CGPoint(x: 20, y: 50), velocity: CGVector(dx: 400, dy: 0), leftHole: true, cushions: 2)
        var three = GolfBall(position: CGPoint(x: 20, y: 50), velocity: CGVector(dx: 400, dy: 0), leftHole: true, cushions: 3)
        check(Golf.advance(&two, dt: 0.1, size: CGSize(width: 3000, height: 100), holes: [CGPoint(x: 40, y: 51)], rules: asks) == nil
              && Golf.advance(&three, dt: 0.1, size: CGSize(width: 3000, height: 100), holes: [CGPoint(x: 40, y: 51)], rules: asks) != nil,
              "a hole off its cushions")
        check(asks.cushionsNeeded == 3 && GolfRules(field: .biliardo).cushionsNeeded == 1, "cushions needed")

        // The card: hole after hole, a "–" for a ball left alone, then free play until tomorrow.
        var played = GolfStats()
        check(played.round(day).nextHole == 1 && played.round(day).needs == round.needs, "a round not started")
        for i in 0..<18 { _ = played.record(round, shots: i == 6 ? 0 : 2, cushions: round.needs[i]) }
        let card = played.round(day)
        check(card.done && card.holesMade == 17 && card.overPar == -17 && card.shots[6] == 0, "a round played: \(card.shots)")
        check(played.record(round, shots: 1, cushions: 0).shots.count == 18 && played.rounds.count == 1, "no hole 19")
        check(played.round(day.addingTimeInterval(86400)).nextHole == 1, "a new round the next day")

        // The back nine: from hole 10 the ball drops anyway, also off fewer cushions; each one off the
        // exact number, more or fewer, makes the hole worth minus 50 points.
        check(!GolfRound.exact(hole: 9) && GolfRound.exact(hole: 10) && GolfRound.exact(hole: 18)
              && GolfRound.offBy(hole: 9, target: 2, cushions: 7) == 0 && GolfRound.offBy(hole: 12, target: 3, cushions: 3) == 0
              && GolfRound.offBy(hole: 12, target: 3, cushions: 4) == 1 && GolfRound.offBy(hole: 12, target: 5, cushions: 3) == 2
              && GolfRound.offBy(hole: 18, target: 0, cushions: 1) == 1, "exact cushions from hole 10")
        var exact = GolfRules()
        exact.holeCushions = 3
        exact.exactHole = true
        var none = GolfBall(position: CGPoint(x: 20, y: 50), velocity: CGVector(dx: 400, dy: 0), leftHole: true)
        check(Golf.advance(&none, dt: 0.1, size: CGSize(width: 3000, height: 100), holes: [CGPoint(x: 40, y: 51)], rules: exact) != nil
              && exact.cushionsNeeded == 0 && exact.cushionsAsked == 3, "an exact hole drops off fewer cushions too")
        var exactPool = GolfRules(field: .biliardo)
        exactPool.exactHole = true
        check(exactPool.cushionsNeeded == 1 && exactPool.cushionsAsked == 1, "an exact pocket still wants a cushion")
        var back = GolfRoundCard(round)
        for _ in 0..<9 { back.record(shots: 2, cushions: 1) }
        back.record(shots: 2, cushions: 1, offBy: 2)
        check(back.shots[9] == 2 && back.offBy(hole: 10) == 2 && back.offBy(hole: 9) == 0 && back.overPar == -10
              && back.pointsLost == 100 && back.offBy?.count == 10, "cushions off: \(String(describing: back.offBy))")
        var scored = GolfStats()
        check(scored.finish(start: 0, end: 5, shots: 1, sunk: true, cushions: 3, totalCushions: 3, nearMisses: 0, offBy: 2).record.points == -100
              && scored.finish(start: 0, end: 5, shots: 1, sunk: true, cushions: 3, totalCushions: 3, nearMisses: 0).record.points > 0,
              "an exact hole missed: minus 50 points a cushion")
        // A card saved before the back nine was exact still reads, with nothing off.
        let old = "{\"day\":\"2026-10-25\",\"needs\":\(round.needs),\"shots\":[2,0],\"cushions\":[1,0]}"
        if var saved = try? JSONDecoder().decode(GolfRoundCard.self, from: Data(old.utf8)) {
            check(saved.offBy == nil && saved.offBy(hole: 1) == 0 && saved.pointsLost == 0 && saved.nextHole == 3, "an old card")
            saved.record(shots: 1, cushions: 0, offBy: 1)
            check(saved.offBy == [0, 0, 1] && saved.shots == [2, 0, 1] && saved.pointsLost == 50, "an old card goes on: \(saved.shots)")
        } else {
            check(false, "an old card does not read")
        }

        // From hole 6 the ball starts somewhere at random: inside, away from the hole and the obstacles.
        for _ in 0..<20 {
            let start = placedRules(placed).ballStart(size: size, hole: hole, using: &random)
            check(start.map { s in hypot(s.x - hole.x, s.y - hole.y) > 90 && placed.allSatisfy { $0.contact(s, radius: 18) == nil }
                && CGRect(origin: .zero, size: size).insetBy(dx: 20, dy: 20).contains(s) } ?? false, "ball start: \(String(describing: start))")
        }
        check(lawn.ballStart(size: CGSize(width: 30, height: 30), hole: hole, using: &random) == nil, "no room for the ball")

        // The words on the board and in the day's line, in each language.
        let iceClub = GolfRules(field: .ghiaccio, strongClub: true)
        Loc.testing(.it) {
            check(iceClub.label == "Ghiaccio · mazza forte" && lawn.label == "Prato" && GolfDay.timida.title == "Buca timida"
                  && GolfDay.pacman.titleInSentence == "giorno pac-man"
                  && GolfDay.bucaXXL.how() == "la buca è più grande del solito", "board words (it): \(iceClub.label)")
        }
        Loc.testing(.en) {
            check(iceClub.label == "Ice · power club" && pool.label == "Billiards" && GolfDay.timida.title == "Shy hole"
                  && GolfDay.pacman.titleInSentence == "Pac-Man day" && GolfDay.vento.titleInSentence == "windy day"
                  && GolfDay.vento.how(today).hasPrefix("the wind blows towards \(GolfDay.wind(today).arrow)"), "board words (en): \(iceClub.label)")
        }
        return out + GolfTraceTest.failures()
    }

    private static func placedRules(_ obstacles: [GolfObstacle]) -> GolfRules {
        var rules = GolfRules()
        rules.obstacles = obstacles
        return rules
    }
}
