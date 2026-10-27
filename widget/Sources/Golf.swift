import AppKit
import AVFoundation
import SwiftUI

// Mini golf, hidden behind the "in corso" dot and unlocked at its 101st click: hold the dot and
// pull it back like a slingshot, let go, and it flies off bouncing around the list. Where the dot
// was there is now a hole: get the ball back in and fireworks go off. Otherwise it stops somewhere
// and can be pulled again from there. From 5 holes in one in a row (the combo) the course has walls
// and mushrooms to bounce off (GolfObstacle, in GolfRules.swift).

struct GolfBall: Equatable {
    var position: CGPoint
    var velocity: CGVector
    /// It has been away from the hole: passing over it again now counts.
    var leftHole = false
    /// Bounces off the edges in this shot: a hole after more of them is worth more.
    var cushions = 0
    /// Just out of a portal (the portals' day): it goes in again only once away from both.
    var inPortal = false
}

enum Golf {
    static let radius: CGFloat = 6
    // The hole, the bounce, the friction and the launch are the course's and the club's: GolfRules.

    /// One step of the ball on the lawn: moves, bounces off the edges of the list, slows down. True
    /// when it went over the hole on the way. The courses' own step is in GolfRules.swift.
    static func advance(_ ball: inout GolfBall, dt: CGFloat, size: CGSize, hole: CGPoint) -> Bool {
        advance(&ball, dt: dt, size: size, holes: [hole], rules: GolfRules()) != nil
    }

    /// "+200 punti", "−100 punti".
    static func points(_ n: Int) -> String {
        L(n < 0 ? "−\(-n) points" : "+\(n) points", n < 0 ? "−\(-n) punti" : "+\(n) punti")
    }

    /// "1 sponda", "3 sponde"; on the back nine "1 sponda esatta", "3 sponde esatte".
    static func cushions(_ n: Int, exact: Bool = false) -> String {
        if n == 0 { return exact ? L("no cushions, straight", "nessuna sponda, dritta") : L("no cushions", "nessuna sponda") }
        if n == 1 { return L(exact ? "exactly 1 cushion" : "1 cushion", "1 sponda" + (exact ? " esatta" : "")) }
        return L(exact ? "exactly \(n) cushions" : "\(n) cushions", "\(n) sponde" + (exact ? " esatte" : ""))
    }

    /// Distance from point p to the segment a-b.
    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

/// The cheer on a hole, wilder with every cushion: the user's own clip if they put one in the
/// sounds folder (cheer.mp3, .m4a, .wav, .aiff or .caf), else the Mac's singing voices. Both
/// over an original fanfare made here.
enum HoleCheer {
    private static let voice = AVSpeechSynthesizer()

    /// ~/.claude/task-eta/sounds (next to the live folder).
    static var soundsDir: URL {
        TaskStore.defaultDir.deletingLastPathComponent().appendingPathComponent("sounds", isDirectory: true)
    }

    static func customClip() -> URL? {
        ["mp3", "m4a", "wav", "aiff", "caf"].lazy
            .map { soundsDir.appendingPathComponent("cheer.\($0)") }
            .first { isRegularFile($0.path) }
    }

    /// The dinosaur's entrance: a roar.
    static func roar() {
        NSSound(named: "Submarine")?.play()
        let line = AVSpeechUtterance(string: "Raaawr!")
        line.voice = AVSpeechSynthesisVoice.speechVoices().first { $0.name == "Bad News" }
            ?? AVSpeechSynthesisVoice(language: "en-US")
        line.preUtteranceDelay = 0.3
        voice.speak(line)
    }

    /// The cheer is on unless switched off in the settings ("Esultanza quando fai buca"): off, a hole
    /// and the 101 clicks of the dot make no sound, the show stays.
    static let onKey = "holeCheer"
    static var isOn: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? true }

    /// level 0: a hole; 1-2: off one or two cushions; 3: three or more. `always`: the settings' try.
    static func cheer(level: Int = 0, always: Bool = false) {
        guard always || isOn else { return }
        Fanfare.shared.play(level: level)
        voice.stopSpeaking(at: .immediate)
        if let clip = customClip(), let sound = NSSound(contentsOf: clip, byReference: true) {
            sound.play()
            if level >= 3 { // twice for the big one
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0.6, sound.duration * 0.85)) {
                    NSSound(contentsOf: clip, byReference: true)?.play()
                }
            }
            return
        }
        let lines: [(voice: String, text: String)] = level >= 3
            ? [("Superstar", "Yes! Yes! Yes!"), ("Good News", "What a shot!"), ("Jester", "Woo hoo hoo!")]
            : level >= 1 ? [("Superstar", "Yes! Yes!"), ("Good News", "What a shot!")]
            : [("Good News", "In the hole!")]
        for (i, line) in lines.enumerated() {
            let u = AVSpeechUtterance(string: line.text)
            u.voice = AVSpeechSynthesisVoice.speechVoices().first { $0.name == line.voice }
                ?? AVSpeechSynthesisVoice(language: "en-US")
            u.preUtteranceDelay = i == 0 ? 0.5 : 0
            voice.speak(u)
        }
    }
}

/// A short brass-like fanfare, made on the spot (rising arpeggios and a final chord), longer and
/// higher with the level. The audio engine runs only while it plays.
final class Fanfare {
    static let shared = Fanfare()
    private var engine: AVAudioEngine?

    typealias Note = (f: Double, at: Double, len: Double)

    /// The notes of a rising run, one every step seconds.
    private static func run(_ freqs: [Double], from at: Double, step: Double) -> [Note] {
        var notes: [Note] = []
        for (i, f) in freqs.enumerated() { notes.append((f, at + Double(i) * step, step + 0.01)) }
        return notes
    }

    private static func notes(level: Int) -> [Note] {
        let c5 = 523.25, e5 = 659.25, g5 = 783.99, c6 = 1046.5, e6 = 1318.5, g6 = 1568.0, g4 = 392.0
        switch level {
        case 0:
            return [(c5, 0, 0.11), (e5, 0.11, 0.11), (g5, 0.22, 0.11), (c6, 0.33, 0.55)]
        case 1, 2:
            return [(g4, 0, 0.1), (c5, 0.1, 0.1), (e5, 0.2, 0.1), (g5, 0.3, 0.1),
                    (c6, 0.42, 0.8), (e6, 0.42, 0.8), (g5, 0.42, 0.8)]
        default:
            let rise: [Note] = run([g4, c5, e5, g5, c6], from: 0, step: 0.08)
            let higher: [Note] = run([c5, e5, g5, c6, e6], from: 0.5, step: 0.08)
            let trill: [Note] = run([e6, g6, e6, g6, e6, g6], from: 0.95, step: 0.07)
            let chord: [Note] = [(c6, 1.4, 1.3), (e6, 1.4, 1.3), (g6, 1.4, 1.3), (c5, 1.4, 1.3)]
            return rise + higher + trill + chord
        }
    }

    func play(level: Int) {
        let rate = 44100.0
        let notes = Fanfare.notes(level: level)
        let total = (notes.map { $0.at + $0.len }.max() ?? 1) + 0.25
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total * rate)),
              let data = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        let frames = Int(buffer.frameLength)
        for i in 0..<frames { data[i] = 0 }
        for note in notes {
            let from = Int(note.at * rate), count = Int((note.len + 0.15) * rate)
            for k in 0..<count where from + k < frames {
                let t = Double(k) / rate
                let env = min(1, t / 0.012) * (t < note.len ? 1 : max(0, 1 - (t - note.len) / 0.15))
                let phase = t * note.f
                let saw = 2 * (phase - (phase + 0.5).rounded(.down))
                let sample = 0.55 * saw + 0.45 * sin(2 * .pi * phase)
                data[from + k] += Float(0.11 * env * sample)
            }
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        guard (try? engine.start()) != nil else { return }
        self.engine?.stop()
        self.engine = engine
        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard self?.engine === engine else { return }
                engine.stop()
                self?.engine = nil
            }
        }
        player.play()
    }
}

/// One game, in one list (the panel's or the popover's). The timer runs only while the ball rolls.
final class GolfGame: ObservableObject {
    /// One game per place, kept while the list is rebuilt (the panel pauses when covered).
    private static var games: [String: GolfGame] = [:]
    static func game(_ place: String) -> GolfGame {
        if let game = games[place] { return game }
        let game = GolfGame()
        games[place] = game
        return game
    }

    @Published private(set) var ball: GolfBall?
    @Published private(set) var hole: CGPoint?
    /// While pulling: from the ball to the pointer.
    @Published private(set) var aim: (from: CGPoint, to: CGPoint)?
    @Published private(set) var sunkAt: Double?
    @Published private(set) var shots = 0
    /// Cushions of the shot that went in.
    @Published private(set) var sunkCushions = 0
    /// What the last game was worth (par, points, streak, records), for the sticker.
    @Published private(set) var result: GolfResult?
    /// The ball just brushed the hole: "Uuuh!".
    @Published private(set) var nearMissAt: Double?
    /// The dinosaur of the 69th cushion, once: when it walks in.
    @Published private(set) var dinoAt: Double?
    /// Record, streak and challenge, shown while playing (read when a game starts and ends).
    @Published private(set) var board = GolfBoard()
    /// The course and the club of this game (GolfRules.swift), read when it starts. A click on the
    /// course's name picks the one of the next game.
    @Published private(set) var rules = GolfRules()
    @Published private(set) var nextField: CampoMinigolf?
    /// The hole of the round of the day this game plays (GolfRound), nil in a free game: the 18
    /// are played until tomorrow.
    @Published private(set) var roundHole: GolfRoundHole?
    /// Where the ball can drop: the billiards' six pockets (at the list's edges, as it is now), or
    /// the hole where the dot was. None between games: the pockets are not drawn on a list at rest.
    var targets: [CGPoint] {
        guard let hole else { return [] }
        return rules.pockets ? rules.pocketCenters(size) : [hole]
    }
    var size: CGSize = .zero
    private var gameStart: Double?
    private var totalCushions = 0
    private var nearMisses = 0
    private var nearMissThisShot = false
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private var giveUp: DispatchWorkItem?
    /// The ball started somewhere else: the drag of the dot that started the game does not shoot.
    private var dotStillHeld = false
    /// The launch speed of the last shot: under a fifth of it the ball can be caught.
    private var shotSpeed: CGFloat = 0
    /// The rainbow day's trail behind the ball (GolfDay.arcobaleno), the last 18 points.
    @Published private(set) var trail: [CGPoint] = []
    /// The shy hole just stepped away: "🙈 Ops!" by it, for a moment. Once a shot.
    @Published private(set) var shyAt: Double?
    private var shyThisShot = false
    /// The game's way on the list, for the heat map in the dashboard (GolfTrace.swift).
    private var trace = GolfTraceRecorder()

    /// Pulling the dot (which becomes the ball, its place the hole) or the ball at rest. From hole
    /// 6 of the round the ball appears somewhere else, to be pulled from there.
    func pull(from start: CGPoint, to point: CGPoint) {
        if ball == nil {
            hole = start
            ball = GolfBall(position: start, velocity: .zero)
            shots = 0
            gameStart = Date().timeIntervalSince1970
            totalCushions = 0
            nearMisses = 0
            let stats = GolfStats.load()
            board = GolfBoard(stats)
            rules = GolfRules.current()
            nextField = nil
            let card = stats.round()
            if let n = GolfRules.debugHole ?? card.nextHole {
                let playing = GolfRoundHole(round: GolfRound(day: card.day, needs: card.needs), hole: n)
                roundHole = playing
                rules.holeCushions = playing.cushions
                rules.exactHole = playing.exact
                rules = rules.withObstacles(GolfRound.obstacles(hole: n), size: size, hole: start)
                var random = SystemRandomNumberGenerator()
                if rules.day == .portali { rules = rules.withPortals(size: size, hole: start, using: &random) }
                if GolfRound.ballAtRandom(hole: n), let elsewhere = rules.ballStart(size: size, hole: start, using: &random) {
                    ball = GolfBall(position: elsewhere, velocity: .zero, leftHole: true)
                    dotStillHeld = true
                    waitForShot()
                }
            } else { // the round played: a free game, with the combo's obstacles
                roundHole = nil
                rules = rules.withObstacles(GolfObstacle.count(combo: board.combo), size: size, hole: start)
                var random = SystemRandomNumberGenerator()
                if rules.day == .portali { rules = rules.withPortals(size: size, hole: start, using: &random) }
            }
            trace.begin(size: size, hole: start, field: rules.field)
        }
        guard !dotStillHeld, var b = ball, sunkAt == nil else { return }
        if b.velocity != .zero {
            // Still rolling, but slowly: caught where it is, and the shot is over.
            guard GolfRules.catchable(speed: hypot(b.velocity.dx, b.velocity.dy), shot: shotSpeed) else { return }
            stop()
            totalCushions += b.cushions
            b.velocity = .zero
            ball = b
            trace.sample(b.position, last: true)
        }
        giveUp?.cancel()
        aim = (b.position, point)
    }

    /// Let go: off it goes, opposite to the pull, faster the longer the pull (GolfRules.launchSpeed).
    func release() {
        if dotStillHeld {
            dotStillHeld = false
            return
        }
        guard var b = ball, let a = aim else { return }
        aim = nil
        guard let v = rules.launch(dx: a.from.x - a.to.x, dy: a.from.y - a.to.y) else {
            // A press without a pull: the dot goes back in its place; a ball elsewhere stays.
            if shots == 0, b.position == hole { reset() } else { waitForShot() }
            return
        }
        shotSpeed = hypot(v.dx, v.dy)
        b.velocity = v
        b.cushions = 0
        ball = b
        trail = []
        trace.shot(from: b.position)
        shots += 1
        nearMissThisShot = false
        shyThisShot = false
        NSSound(named: "Tink")?.play()
        lastTick = CACurrentMediaTime()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(0.05, now - lastTick))
        lastTick = now
        guard var b = ball, hole != nil, size.width > 0 else { return stop() }
        let from = b.position
        let wasAway = b.leftHole
        let targets = self.targets
        if let sunk = Golf.advance(&b, dt: dt, size: size, holes: targets, rules: rules) {
            b.position = sunk
            b.velocity = .zero
            ball = b
            trace.sample(sunk, last: true)
            stop()
            totalCushions += b.cushions
            sunkCushions = b.cushions
            result = finish(sunk: true, cushions: b.cushions)
            sunkAt = Date().timeIntervalSince1970
            let level = min(3, b.cushions)
            HoleCheer.cheer(level: level)
            DispatchQueue.main.asyncAfter(deadline: .now() + HoleInOne.duration(level) + 0.1) { [weak self] in
                self?.reset()
            }
            return
        }
        ball = b
        trace.sample(b.position, last: b.velocity == .zero)
        // The shy hole: once a shot, when the ball that left it comes near, it steps away.
        if rules.day == .timida, !rules.pockets, !shyThisShot, wasAway, let h = hole,
           hypot(b.position.x - h.x, b.position.y - h.y) < 46 {
            shyThisShot = true
            let step = rules.shyStep(hole: h, ball: b.position, velocity: b.velocity, size: size)
            if step != h {
                hole = step
                let at = Date().timeIntervalSince1970
                shyAt = at
                NSSound(named: "Pop")?.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    if self?.shyAt == at { self?.shyAt = nil }
                }
            }
        }
        // The rainbow day's trail: the last points of the way, one every other step.
        if rules.day == .arcobaleno, trail.last.map({ hypot($0.x - b.position.x, $0.y - b.position.y) > 7 }) ?? true {
            trail = Array((trail + [b.position]).suffix(18))
        }
        // A pass close to the hole that did not drop: once a shot, and not the shot leaving it.
        if wasAway, !nearMissThisShot,
           targets.contains(where: { Golf.distance(from: $0, toSegment: from, b.position) < rules.holeRadius * 2.2 }) {
            nearMissThisShot = true
            nearMisses += 1
            let at = Date().timeIntervalSince1970
            nearMissAt = at
            NSSound(named: "Basso")?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
                if self?.nearMissAt == at { self?.nearMissAt = nil }
            }
        }
        if b.velocity == .zero {
            stop()
            totalCushions += b.cushions
            waitForShot()
        }
    }

    /// Left alone for a minute and a half, the ball goes back to being the dot: the game is lost
    /// (and so is the streak; in the round, a "–" on the hole).
    private func waitForShot() {
        giveUp?.cancel()
        let work = DispatchWorkItem { [weak self] in
            _ = self?.finish(sunk: false, cushions: 0)
            self?.reset()
        }
        giveUp = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: work)
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Writes the game in the history.
    private func finish(sunk: Bool, cushions: Int) -> GolfResult? {
        guard let start = gameStart, shots > 0 else { return nil }
        gameStart = nil
        trace.finish(sunk: sunk)
        var stats = GolfStats.load()
        // On the back nine of the round each cushion off the exact number costs 50 points.
        let off = sunk ? roundHole.map { GolfRound.offBy(hole: $0.hole, target: rules.cushionsAsked, cushions: cushions) } ?? 0 : 0
        var r = stats.finish(start: start, end: Date().timeIntervalSince1970, shots: shots, sunk: sunk,
                             cushions: cushions, totalCushions: totalCushions, nearMisses: nearMisses, offBy: off)
        r.obstacles = rules.obstacles.count
        r.roundTarget = rules.cushionsAsked
        if let playing = roundHole, GolfRules.debugHole == nil {
            r.roundHole = playing.hole
            r.round = stats.record(playing.round, shots: sunk ? shots : 0, cushions: sunk ? cushions : 0, offBy: off)
        }
        stats.save()
        board = GolfBoard(stats)
        // 69 cushions in all: the dinosaur comes, once, after the hole's own show.
        if stats.totalCushions >= 69, !UserDefaults.standard.bool(forKey: "dinoSeen") {
            UserDefaults.standard.set(true, forKey: "dinoSeen")
            let delay = sunk ? HoleInOne.duration(min(3, cushions)) : 0
            let at = Date().timeIntervalSince1970 + delay
            dinoAt = at
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { HoleCheer.roar() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + DinoComingSoon.duration + 0.2) { [weak self] in
                if self?.dinoAt == at { self?.dinoAt = nil }
            }
        }
        return r
    }

    /// Four shots gone wrong in a hole of the round, the ball at rest: the way out shows.
    var canGoClassic: Bool {
        roundHole != nil && shots >= GolfRound.missesBeforeClassic && sunkAt == nil && ball?.velocity == .zero
    }

    /// The way out: this game becomes a classic one, no cushions to make and no obstacles. The
    /// round's hole stays to be played, from the next game.
    func goClassic() {
        guard canGoClassic else { return }
        roundHole = nil
        rules.holeCushions = 0
        rules.exactHole = false
        rules.obstacles = []
    }

    /// A click on the course's name while playing: the next open course, from the next game.
    func switchField() {
        let next = GolfRules.choose(after: nextField ?? rules.field)
        nextField = next == rules.field ? nil : next
    }

    func reset() {
        stop()
        giveUp?.cancel()
        result = nil
        nearMissAt = nil
        gameStart = nil
        ball = nil
        hole = nil
        aim = nil
        sunkAt = nil
        shots = 0
        sunkCushions = 0
        rules.obstacles = [] // the next game places its own
        roundHole = nil
        dotStillHeld = false
        trail = []
        shyAt = nil
        rules.portals = []
    }

    /// Where the shot being aimed would go, up to its second bounce: the aim's line, when the
    /// "Mira con i rimbalzi" of the strip's menu is on.
    func aimPath() -> (points: [CGPoint], bounces: [CGPoint], sunk: Bool)? {
        guard let a = aim, var b = ball, size.width > 0,
              let v = rules.launch(dx: a.from.x - a.to.x, dy: a.from.y - a.to.y) else { return nil }
        b.velocity = v
        return Golf.path(b, size: size, holes: targets, rules: rules)
    }

    deinit { timer?.invalidate() }
}

/// What the player sees while playing: the record, the streak, the combo, the challenge of the day.
struct GolfBoard: Equatable {
    var record = 0
    var streak = 0
    var combo = 0
    var today = GolfChallenge.of()
    var challengeDone = false
    /// The challenge's words, in the language of the moment.
    var challenge: String { today.text }

    init() {}

    init(_ stats: GolfStats) {
        record = stats.bestCushions
        streak = stats.streak
        combo = GolfRules.debugCombo ?? stats.combo
        today = GolfChallenge.of()
        challengeDone = stats.challengeDoneToday
    }
}

private struct GolfKey: EnvironmentKey {
    static let defaultValue: GolfGame? = nil
}

extension EnvironmentValues {
    /// The list's game, once unlocked: the "in corso" dot can then be pulled.
    var golf: GolfGame? {
        get { self[GolfKey.self] }
        set { self[GolfKey.self] = newValue }
    }
}

/// The record, streak and challenge line while a game is on, as a row of the list: under the
/// header ("alto") or at its foot ("basso"), in its own room so it never covers a task or the
/// header; hidden ("via"), only its ⋯ is left, at the foot. Kept in the preferences ("golfBoard").
struct GolfBoardSlot: View {
    @ObservedObject var game: GolfGame
    /// The place this slot stands for: "alto" or "basso" (the foot also holds the hidden ⋯).
    let slot: String
    /// The pointer on the line: shown in full only then.
    @State private var boardHover = false
    @AppStorage("golfBoard") private var boardPlace = "basso"
    @AppStorage(GolfLayer.aimKey) private var aimBounces = false

    var body: some View {
        if game.ball != nil, game.sunkAt == nil, boardPlace == slot || (slot == "basso" && boardPlace == "via") {
            HStack {
                Spacer(minLength: 0)
                Group {
                    if boardPlace == "via" {
                        boardMenu.opacity(boardHover ? 1 : 0.35)
                    } else {
                        boardView.opacity(boardHover ? 1 : 0.45)
                    }
                }
                .onHover { inside in withAnimation(.easeOut(duration: 0.18)) { boardHover = inside } }
                if boardPlace != "via" { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Record, streak and today's challenge, at the foot of the list while playing: muted, on a
    /// background only with the pointer on it. The challenge only when it fits whole (else it is the
    /// first line of the ⋯ menu); on a narrow list the short line, which shrinks rather than widen
    /// the list past its panel.
    private var boardView: some View {
        ViewThatFits(in: .horizontal) {
            strip(0)
            strip(1)
            strip(2)
            strip(3)
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(boardHover ? 0.88 : 0)))
    }

    private var challengeText: String {
        game.board.challengeDone ? L("📅 challenge won", "📅 sfida vinta") : "📅 \(game.board.challenge)"
    }

    /// 0: all of it; 1: without the challenge; 2: short, without the record (or, in the round, the
    /// streak), its words free to shrink.
    /// 0: all of it; 1: without the challenge; 2: short, the round's hole in few words, without the
    /// record (or the streak); 3: the same, its words free to shrink. The course's name stays whole
    /// down to 2.
    private func strip(_ level: Int) -> some View {
        let whole = level < 3, short = level >= 2
        return HStack(spacing: 10) {
            // The day's twist in an emoji, with what it does on the pointer and in the ⋯ menu.
            if game.rules.day != .classico {
                Text(game.rules.day.mark()).fixedSize()
                    .help("\(game.rules.day.title): \(game.rules.day.how())")
            }
            // The course and the club: a click picks the course of the next game.
            Button { game.switchField() } label: {
                Text(game.nextField.map { "\(game.rules.label) → \(GolfRules.short($0))" } ?? game.rules.label)
                    .underline(true, color: Color.secondary.opacity(0.4)).lineLimit(1).fixedSize(horizontal: whole, vertical: false)
            }
            .buttonStyle(.plain)
            .help(L("The next game's course: click to switch, among those opened by the holes you've made",
                    "Il campo della prossima partita: un clic per cambiarlo, tra quelli aperti dalle buche fatte"))
            .reportsClickFrame() // in the panel, the clicks reach only the frames reported
            if let playing = game.roundHole {
                // The round of the day first: the hole and its cushions.
                Text(short ? shortHole(playing) : longHole(playing))
                    .lineLimit(1).fixedSize(horizontal: whole, vertical: false).layoutPriority(1)
                    .help(L("The round of the day: 18 holes. Up to hole 9 the ball drops only with at least those cushions in the shot. From hole 6, obstacles and the ball in a random spot. From hole 10 the ball always drops, but the cushions must be exact: each one more or less is −50 points. A new round tomorrow",
                            "Il giro del giorno: 18 buche. Fino alla 9 la buca entra solo con almeno quelle sponde nel tiro. Dalla 6 ostacoli e palla a caso. Dalla 10 la palla entra sempre, ma le sponde vanno fatte esatte: ogni sponda in più o in meno vale −50 punti. Domani un giro nuovo"))
                if !short { Text(inARow).lineLimit(1) }
            } else {
                if !short {
                    Text(L(game.board.record == 1 ? "🏆 1 cushion" : "🏆 \(game.board.record) cushions", "🏆 \(game.board.record) sponde")).fixedSize()
                }
                // With the combo next to it, short, so the challenge keeps its room.
                Text(inARow + (game.board.combo > 0 ? " · 🎯 \(game.board.combo)" : ""))
                    .lineLimit(1).fixedSize(horizontal: whole, vertical: false)
                    .help(game.board.combo > 0 ? L("🎯 The combo: holes in one in a row. At 5 the obstacles come, then one more with each hole in one, up to 4",
                                                   "🎯 La combo: hole in one di fila. A 5 arrivano gli ostacoli, poi uno in più a ogni hole in one, fino a 4") : "")
                if level == 0 { Text(challengeText).fixedSize() }
            }
            boardMenu
        }
    }

    /// "🔥 3 in a row".
    private var inARow: String { L("🔥 \(game.board.streak) in a row", "🔥 \(game.board.streak) di fila") }

    /// "⛳ Hole 12/18 · exactly 3 cushions, or −50 per cushion", "⛳ Hole 4/18 · 2 cushions".
    private func longHole(_ playing: GolfRoundHole) -> String {
        let what = Golf.cushions(game.rules.cushionsAsked, exact: playing.exact), off = GolfRound.pointsPerCushionOff
        return L("⛳ Hole \(playing.hole)/\(GolfRound.holes) · \(what)", "⛳ Buca \(playing.hole)/\(GolfRound.holes) · \(what)")
            + (playing.exact ? L(", or −\(off) per cushion", ", o −\(off) a sponda") : "")
    }

    /// "⛳ 12/18 · 3 esatte", "⛳ 4/18 · 2 sponde", "⛳ 15/18 · dritta".
    private func shortHole(_ playing: GolfRoundHole) -> String {
        let n = game.rules.cushionsAsked
        let what = playing.exact ? (n == 0 ? L("straight", "dritta") : L("\(n) exact", "\(n) \(n == 1 ? "esatta" : "esatte")")) : Golf.cushions(n)
        return "⛳ \(playing.hole)/\(GolfRound.holes) · \(what)"
    }

    /// The line's ⋯: to the top or the foot of the list, hidden, or back again; and the challenge.
    private var boardMenu: some View {
        Menu {
            let day = game.rules.day
            Text(L("\(day.emoji) Today: \(day.titleInSentence), \(day.how())", "\(day.emoji) Oggi: \(day.titleInSentence), \(day.how())"))
            Text(game.board.challengeDone ? L("📅 Challenge of the day won", "📅 Sfida del giorno vinta")
                 : L("📅 Challenge of the day: \(game.board.challenge)", "📅 Sfida del giorno: \(game.board.challenge)"))
            Divider()
            Toggle(L("Aim with the bounces, every day", "Mira con i rimbalzi, tutti i giorni"), isOn: $aimBounces)
            Divider()
            switch boardPlace {
            case "alto":
                Button(L("Move to the bottom", "Sposta in basso")) { boardPlace = "basso" }
            case "via":
                Button(L("Show at the bottom", "Mostra in basso")) { boardPlace = "basso" }
                Button(L("Show at the top", "Mostra in alto")) { boardPlace = "alto" }
            default:
                Button(L("Move to the top", "Sposta in alto")) { boardPlace = "alto" }
            }
            if boardPlace != "via" {
                Button(L("Hide (only ⋯ stays)", "Nascondi (resta solo ⋯)")) { boardPlace = "via" }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(boardPlace == "via" ? L("The mini golf strip is hidden: click to bring it back", "La striscia del minigolf è nascosta: un clic per riaverla")
              : L("Move or hide this strip", "Sposta o nascondi questa striscia"))
        .reportsClickFrame()
    }

}

/// The hole, the ball, the slingshot's band and, on a hit, fireworks across the list.
struct GolfLayer: View {
    @ObservedObject var game: GolfGame
    @State private var classicHover = false
    /// The aim's line shows the bounces every day, not only on the caddie's (the strip's ⋯ menu).
    @AppStorage(GolfLayer.aimKey) private var aimBounces = false
    @Environment(\.colorScheme) private var scheme

    static let aimKey = "golfAimBounces"

    /// The ball; on the rainbow day a spinning rainbow, turned by where it rolls (no clock).
    @ViewBuilder private func face(_ ball: GolfBall, rainbow: Bool) -> some View {
        if rainbow {
            Circle()
                .fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
                .rotationEffect(.degrees(Double(ball.position.x + ball.position.y) * 3))
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: UnitPoint(x: 0.35, y: 0.3),
                                                      startRadius: 0, endRadius: Golf.radius)))
        } else {
            Circle()
                .fill(RadialGradient(colors: game.rules.ball(CampoStyle(scheme)),
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: Golf.radius * 1.4))
        }
    }

    /// How high the rainbow ball hops: with the way it rolls, lower as it slows, still at rest.
    static func hop(_ ball: GolfBall, rainbow: Bool) -> CGFloat {
        guard rainbow, ball.velocity != .zero else { return 0 }
        let speed = hypot(ball.velocity.dx, ball.velocity.dy)
        return abs(sin((ball.position.x + ball.position.y) / 16)) * 7 * min(1, speed / 250)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in draw(&ctx, size: size) }
                    .allowsHitTesting(false)
                if let ball = game.ball, game.sunkAt == nil {
                    let rainbow = game.rules.day == .arcobaleno
                    face(ball, rainbow: rainbow)
                        .frame(width: Golf.radius * 2, height: Golf.radius * 2)
                        .shadow(color: .black.opacity(rainbow ? 0 : 0.3), radius: 2, y: 1) // the hop draws its own
                        .offset(y: -GolfLayer.hop(ball, rainbow: rainbow))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("golf"))
                            .onChanged { game.pull(from: ball.position, to: $0.location) }
                            .onEnded { _ in game.release() })
                        .reportsClickFrame()
                        .position(ball.position)
                        .help(L("Pull and let go", "Tira e lascia"))
                }
                if game.canGoClassic, let ball = game.ball {
                    // Small and see-through, by the ball: the way out of a hole of the round.
                    Button { game.goClassic() } label: {
                        Text(L("play classic", "gioca classico"))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(classicHover ? 1 : 0.45)
                    .onHover { classicHover = $0 }
                    .help(L("Four missed shots: one click makes this a classic game, no cushions to make and no obstacles. The round's hole stays to be played",
                            "Quattro tiri a vuoto: con un clic questa partita diventa classica, senza sponde da fare e senza ostacoli. La buca del giro resta da fare"))
                    .reportsClickFrame()
                    .position(x: min(max(ball.position.x, 40), geo.size.width - 40),
                              y: ball.position.y + 22 > geo.size.height - 8 ? ball.position.y - 22 : ball.position.y + 22)
                }
                if game.nearMissAt != nil, let hole = game.hole {
                    Text(L("😱 Ooh!", "😱 Uuuh!"))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.9)))
                        .position(x: hole.x, y: max(12, hole.y - 26))
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(false)
                }
                if game.shyAt != nil, let hole = game.hole {
                    Text(L("🙈 Oops!", "🙈 Ops!"))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.9)))
                        .position(x: hole.x, y: max(12, hole.y - 26))
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(false)
                }
                if let sunk = game.sunkAt {
                    HoleInOne(start: sunk, shots: game.shots, cushions: game.sunkCushions, result: game.result)
                }
                if let dino = game.dinoAt {
                    DinoComingSoon(start: dino)
                }
            }
            .onAppear { game.size = geo.size }
            .onChange(of: geo.size) { _, size in game.size = size }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let rules = game.rules
        if game.hole != nil, let ground = rules.ground(CampoStyle(scheme)) {
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8), with: .color(ground))
        }
        let s = CampoStyle(scheme)
        for o in rules.obstacles { draw(o, in: &ctx, s) }
        drawPortalsAndSides(&ctx, size: size)
        for hole in game.targets {
            let r = rules.holeRadius
            let cup = Path(ellipseIn: CGRect(x: hole.x - r, y: hole.y - r * (rules.pockets ? 1 : 0.6), width: r * 2,
                                             height: r * (rules.pockets ? 2 : 1.2)))
            ctx.fill(cup, with: .color(.black.opacity(0.55)))
            if rules.pockets {
                ctx.stroke(cup, with: .color(.secondary.opacity(0.5)), lineWidth: 1) // seen on the dark felt too
            } else {
                ctx.draw(Text("⛳").font(.system(size: 15)), at: CGPoint(x: hole.x + 6, y: hole.y - 13))
                if let playing = game.roundHole, rules.cushionsAsked > 0 || playing.exact {
                    tag(Golf.cushions(rules.cushionsAsked, exact: playing.exact), at: CGPoint(x: hole.x, y: hole.y + 15), in: &ctx, size: size)
                }
            }
        }
        // In the round, while the ball rolls: its cushions so far against the ones the hole wants;
        // on the back nine red once they are too many.
        if let playing = game.roundHole, rules.cushionsAsked > 0 || playing.exact, let ball = game.ball, ball.velocity != .zero {
            let need = rules.cushionsAsked
            tag("\(playing.exact ? ball.cushions : min(ball.cushions, need))/\(need)", at: CGPoint(x: ball.position.x, y: ball.position.y - 15),
                in: &ctx, size: size, done: playing.exact ? ball.cushions == need : ball.cushions >= need, over: playing.exact && ball.cushions > need)
        }
        drawDay(&ctx, size: size)
        guard let aim = game.aim else { return }
        // The band, from the ball to the pointer, and where the shot goes.
        var band = Path()
        band.move(to: aim.from)
        band.addLine(to: aim.to)
        ctx.stroke(band, with: .color(.secondary.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        let dx = aim.from.x - aim.to.x, dy = aim.from.y - aim.to.y
        let power = rules.launchSpeed(pull: hypot(dx, dy)) / rules.maxSpeed
        let color = power > 0.75 ? Pace.red.color : power > 0.4 ? Pace.yellow.color : Pace.green.color
        if aimBounces || rules.day == .caddie, let path = game.aimPath(), path.points.count > 1 {
            // Where the ball would go, bounces and all, up to the second: fainter the farther.
            let n = path.points.count
            for i in stride(from: 2, to: n, by: 2) where GolfLayer.near(path.points[i - 2], path.points[i]) {
                var piece = Path()
                piece.move(to: path.points[i - 2])
                piece.addLine(to: path.points[i])
                ctx.stroke(piece, with: .color(color.opacity(0.95 - 0.65 * Double(i) / Double(n))),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 4]))
            }
            for hit in path.bounces {
                ctx.stroke(Path(ellipseIn: CGRect(x: hit.x - 4, y: hit.y - 4, width: 8, height: 8)), with: .color(color), lineWidth: 1.5)
            }
            if path.sunk, let end = path.points.last {
                ctx.stroke(Path(ellipseIn: CGRect(x: end.x - 7, y: end.y - 7, width: 14, height: 14)), with: .color(Pace.green.color), lineWidth: 2)
            }
            return
        }
        let sign: CGFloat = rules.day == .contrario ? -1 : 1
        var shot = Path()
        shot.move(to: aim.from)
        shot.addLine(to: CGPoint(x: aim.from.x + sign * dx * 1.2, y: aim.from.y + sign * dy * 1.2))
        ctx.stroke(shot, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 5]))
    }

    /// Two points of a way next to each other, not the two ends of a jump through a side or a portal.
    static func near(_ a: CGPoint, _ b: CGPoint) -> Bool { hypot(a.x - b.x, a.y - b.y) < 80 }

    /// The portals' day's two portals, blue and orange, and the Pac-Man day's open sides, dashed.
    private func drawPortalsAndSides(_ ctx: inout GraphicsContext, size: CGSize) {
        guard game.hole != nil else { return }
        let colors = [Color(red: 0.2, green: 0.55, blue: 1), Color(red: 1, green: 0.55, blue: 0.1)]
        for (i, p) in game.rules.portals.enumerated() {
            let r = GolfRules.portalRadius
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r - 4, y: p.y - r - 4, width: 2 * r + 8, height: 2 * r + 8)),
                     with: .radialGradient(Gradient(colors: [colors[i].opacity(0.55), colors[i].opacity(0)]), center: p, startRadius: r * 0.4, endRadius: r + 4))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.55, y: p.y - r * 0.55, width: r * 1.1, height: r * 1.1)), with: .color(.black.opacity(0.6)))
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(colors[i]), lineWidth: 2.5)
        }
        if game.rules.wrapSides {
            for x in [CGFloat(1.5), size.width - 1.5] {
                var side = Path()
                side.move(to: CGPoint(x: x, y: 4))
                side.addLine(to: CGPoint(x: x, y: size.height - 4))
                ctx.stroke(side, with: .color(Color(red: 1, green: 0.85, blue: 0.1)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 7]))
            }
        }
    }

    /// The rainbow day's marks: the trail and the shadow of the hop under the ball. Drawn with the
    /// rest, so only while the ball moves something changes.
    private func drawDay(_ ctx: inout GraphicsContext, size: CGSize) {
        guard game.hole != nil else { return }
        let rules = game.rules
        if rules.day == .arcobaleno, let ball = game.ball {
            let way = game.trail + [ball.position], n = way.count
            for i in 1..<max(1, n) where GolfLayer.near(way[i - 1], way[i]) {
                var piece = Path()
                piece.move(to: way[i - 1])
                piece.addLine(to: way[i])
                let share = Double(i) / Double(n)
                ctx.stroke(piece, with: .color(Color(hue: (Double(i) / 18).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 1)
                    .opacity(0.15 + 0.6 * share)), style: StrokeStyle(lineWidth: 1.5 + 3 * share, lineCap: .round))
            }
            let hop = GolfLayer.hop(ball, rainbow: true)
            if hop > 0 {
                let w = Golf.radius * (2 - hop / 14)
                ctx.fill(Path(ellipseIn: CGRect(x: ball.position.x - w / 2, y: ball.position.y + Golf.radius - 3, width: w, height: 4)),
                         with: .color(.black.opacity(0.25)))
            }
        }
    }

    /// A small label on a pale capsule, readable over the rows; green once its goal is reached.
    private func tag(_ text: String, at point: CGPoint, in ctx: inout GraphicsContext, size: CGSize,
                     done: Bool = false, over: Bool = false) {
        let label = ctx.resolve(Text(text).font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(over ? Pace.red.color : done ? Pace.green.color : .primary))
        let m = label.measure(in: CGSize(width: 200, height: 30))
        // Kept inside the list, by a hole or a ball near its edge too.
        let p = CGPoint(x: min(max(point.x, m.width / 2 + 6), size.width - m.width / 2 - 6), y: point.y)
        let box = CGRect(x: p.x - m.width / 2 - 5, y: p.y - m.height / 2 - 1, width: m.width + 10, height: m.height + 2)
        ctx.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.9)))
        ctx.draw(label, at: p)
    }

    /// A wooden wall, a board with its grain, or a red mushroom with white dots; both with a shadow.
    private func draw(_ o: GolfObstacle, in ctx: inout GraphicsContext, _ s: CampoStyle) {
        let f = o.frame
        switch o.kind {
        case .wall:
            let board = Path(roundedRect: f, cornerRadius: 3)
            let across = f.width > f.height
            ctx.fill(Path(roundedRect: f.offsetBy(dx: 1, dy: 2), cornerRadius: 3), with: .color(.black.opacity(0.25)))
            ctx.fill(board, with: .linearGradient(Gradient(colors: [s.wood, s.woodDeep]), startPoint: f.origin,
                                                  endPoint: across ? CGPoint(x: f.minX, y: f.maxY) : CGPoint(x: f.maxX, y: f.minY)))
            var grain = Path()
            grain.move(to: across ? CGPoint(x: f.minX + 5, y: f.midY) : CGPoint(x: f.midX, y: f.minY + 5))
            grain.addLine(to: across ? CGPoint(x: f.maxX - 5, y: f.midY) : CGPoint(x: f.midX, y: f.maxY - 5))
            ctx.stroke(grain, with: .color(s.woodDeep.opacity(0.8)), lineWidth: 1)
            ctx.stroke(board, with: .color(s.woodDeep), lineWidth: 1)
        case .mushroom:
            let cap = Path(ellipseIn: f)
            ctx.fill(Path(ellipseIn: f.offsetBy(dx: 1, dy: 2)), with: .color(.black.opacity(0.25)))
            ctx.fill(cap, with: .radialGradient(Gradient(colors: [s.flag.opacity(0.8), s.flag]),
                                                center: CGPoint(x: f.midX - 3, y: f.midY - 3), startRadius: 0, endRadius: f.width * 0.7))
            let dots: [(dx: CGFloat, dy: CGFloat, r: CGFloat)] = [(-4, -3, 2.2), (3.5, -3.5, 1.7), (1, 3.5, 2)]
            for d in dots {
                ctx.fill(Path(ellipseIn: CGRect(x: f.midX + d.dx - d.r, y: f.midY + d.dy - d.r, width: d.r * 2, height: d.r * 2)),
                         with: .color(s.carved))
            }
            ctx.stroke(cap, with: .color(.black.opacity(0.25)), lineWidth: 1)
        }
    }
}

/// The show on a hole, bigger with every cushion: fireworks over the whole list and a sticker; off
/// cushions also more waves of fireworks and bouncing dots; off three or more, confetti, 101 dots
/// and a shaking sticker.
struct HoleInOne: View {
    let start: Double
    let shots: Int
    var cushions = 0
    var result: GolfResult? = nil

    /// Under the title: par, points, streak, and the news of the hole.
    private var details: [String] {
        guard let r = result else { return [] }
        var line = ["\(r.par)", Golf.points(r.record.points)]
        if r.streak >= 2 { line.append(L("🔥 \(r.streak) in a row", "🔥 \(r.streak) di fila")) }
        var out = [line.joined(separator: "   ")]
        if r.newCushionRecord { out.append(L("🏆 New cushion record!", "🏆 Nuovo record di sponde!")) }
        if r.challengeDone { out.append(L("📅 Challenge of the day won!", "📅 Sfida del giorno vinta!")) }
        if let hole = r.roundHole, let card = r.round {
            if card.offBy(hole: hole) > 0, card.cushions.indices.contains(hole - 1) {
                let instead = r.roundTarget == 0 ? L("going straight", "andare dritta") : Golf.cushions(r.roundTarget, exact: true)
                let made = Golf.cushions(card.cushions[hole - 1]), points = Golf.points(r.record.points)
                out.append(L("⛳ \(made) instead of \(instead): \(points)", "⛳ \(made) invece di \(instead): \(points)"))
            }
            out.append(roundNews(hole, card))
            if r.combo >= 2 { out.append(L("🎯 Combo \(r.combo)", "🎯 Combo \(r.combo)")) } // in the round the obstacles come from the hole
        } else if r.combo >= 2 {
            out.append(comboNews(r.combo))
        } else if r.combo == 0, r.obstacles > 0 {
            out.append(L("🧱 Combo broken: obstacles gone", "🧱 Combo rotta: via gli ostacoli"))
        }
        return out
    }

    /// The round after a hole: what the next hole wants, or the round's score once the 18 are played.
    private func roundNews(_ hole: Int, _ card: GolfRoundCard) -> String {
        guard let next = card.nextHole else {
            let over = card.overPar
            let par = over == 0 ? L("even par", "in par") : over > 0 ? L("\(over) over par", "+\(over) sul par") : L("\(-over) under par", "−\(-over) sul par")
            return L("🏁 Round over: \(card.holesMade) of \(GolfRound.holes) holes, \(par)", "🏁 Giro finito: \(card.holesMade) buche su \(GolfRound.holes), \(par)")
        }
        let need = card.needs.indices.contains(next - 1) ? card.needs[next - 1] : 0, exact = GolfRound.exact(hole: next)
        let wants = need > 0 ? L("hole \(next) wants \(Golf.cushions(need, exact: exact))", "la \(next) vuole \(Golf.cushions(need, exact: exact))")
            : exact ? L("hole \(next) goes straight, no cushions", "la \(next) va dritta, senza sponde")
            : L("hole \(next) can go in straight", "la \(next) entra anche dritta")
        return L("⛳ Hole \(hole) of \(GolfRound.holes) · \(wants)", "⛳ Buca \(hole) di \(GolfRound.holes) · " + wants)
    }

    /// The combo after a hole in one, and what it brings to the next game.
    private func comboNews(_ n: Int) -> String {
        if n < 5 { return L("🎯 Combo \(n) · obstacles come at 5", "🎯 Combo \(n) · a 5 arrivano gli ostacoli") }
        if n == 5 { return L("🎯 Combo 5 · here come the obstacles!", "🎯 Combo 5 · arrivano gli ostacoli!") }
        return GolfObstacle.count(combo: n) > GolfObstacle.count(combo: n - 1) ? L("🎯 Combo \(n) · one more obstacle", "🎯 Combo \(n) · un ostacolo in più")
            : L("🎯 Combo \(n)!", "🎯 Combo \(n)!")
    }

    static func duration(_ level: Int) -> Double { level >= 3 ? 5.5 : level >= 1 ? 4.2 : 3.3 }

    private var level: Int { min(3, cushions) }

    private var title: String {
        switch level {
        case 0: return shots == 1 ? L("⛳ Hole in one!", "⛳ Hole in one!") : L("⛳ Hole in \(shots)", "⛳ Buca in \(shots)")
        case 1: return L("⛳ Bank shot!", "⛳ Di sponda!")
        case 2: return L("⛳ 2 cushions!", "⛳ 2 sponde!")
        default: return L("🔥 \(cushions) CUSHIONS! 🔥", "🔥 \(cushions) SPONDE! 🔥")
        }
    }

    private func shakeAmount(_ t: Double) -> Double {
        level >= 3 ? sin(t * 55) * 3 * max(0, 1 - t / 2) : 0
    }

    private func stickerScale(_ t: Double) -> CGFloat {
        let pop: Double = min(1, 0.3 + t * 2.5)
        let beat: Double = level >= 3 ? 1 + 0.06 * sin(t * 9) : 1
        return CGFloat(pop * beat)
    }

    var body: some View {
        let duration = HoleInOne.duration(level)
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince1970 - start
            if t >= 0 && t < duration {
                ZStack {
                    Canvas { ctx, size in
                        Particles(outcome: .exact, t: t, size: size).draw(in: &ctx)
                        if level >= 1 { Particles(outcome: .exact, t: t - 0.7, size: size).draw(in: &ctx) }
                        if level >= 3 {
                            Particles(outcome: .onTime, t: t, size: size).draw(in: &ctx)
                            Particles(outcome: .exact, t: t - 1.6, size: size).draw(in: &ctx)
                        }
                    }
                    let shake: Double = shakeAmount(t)
                    VStack(spacing: 2) {
                        Text(title)
                            .font(.system(size: level >= 3 ? 21 : 17, weight: .black, design: .rounded))
                        ForEach(details, id: \.self) { line in
                            Text(line).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.92)))
                        .overlay(Capsule().strokeBorder(level >= 3 ? Pace.red.color : Outcome.exact.palette[0], lineWidth: 2))
                        .rotationEffect(.degrees(-5 + shake))
                        .offset(x: shake)
                        .scaleEffect(stickerScale(t))
                }
                .opacity(min(1, (duration - t) / 0.5))
            }
        }
        .overlay {
            if level >= 1 { DotBurstView(burst: DotBurst(count: level >= 3 ? 101 : 30, start: start)) }
        }
        .allowsHitTesting(false)
    }
}

/// At 69 cushions in all (once): a dinosaur walks in holding a sign, "Coming soon", turns the sign
/// over ("Dai tempo al tempo, che nessuno mi sta pagando") and walks off.
struct DinoComingSoon: View {
    let start: Double
    static let duration: Double = 8.5

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince1970 - start
                if t >= 0 && t < DinoComingSoon.duration {
                    VStack(spacing: -4) {
                        DinoSign(flip: min(180, max(0, (t - 2.4) / 0.7 * 180)))
                        Text("🦖")
                            .font(.system(size: 46))
                            .scaleEffect(x: -1, y: 1) // the emoji faces left: this one walks right
                    }
                    .position(x: x(t, width: geo.size.width), y: geo.size.height / 2 - bob(t))
                    .opacity(min(1, (DinoComingSoon.duration - t) / 0.4))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// In from the left in 1.6 s, stays, out to the right after 7 s.
    private func x(_ t: Double, width: CGFloat) -> CGFloat {
        let mid = width / 2
        func ease(_ p: Double) -> CGFloat { CGFloat(p * p * (3 - 2 * p)) }
        if t < 1.6 { return -80 + (mid + 80) * ease(t / 1.6) }
        if t > 7 { return mid + (mid + 110) * ease(min(1, (t - 7) / 1.5)) }
        return mid
    }

    /// A walk bobs; standing, it breathes.
    private func bob(_ t: Double) -> CGFloat {
        CGFloat(t < 1.6 || t > 7 ? abs(sin(t * 11)) * 5 : sin(t * 2.2) * 1.5)
    }
}

/// The sign on its stick; past 90 degrees of the flip its back shows.
struct DinoSign: View {
    let flip: Double

    var body: some View {
        let back = flip > 90
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.98))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(red: 0.55, green: 0.38, blue: 0.22), lineWidth: 3))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                if back {
                    Text(L("Give it time,\nnobody's paying me for this", "Dai tempo al tempo,\nche nessuno mi sta pagando"))
                        .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(white: 0.15))
                        .scaleEffect(x: -1, y: 1) // the flip mirrors it: mirror it back
                } else {
                    Text(L("Coming soon", "Coming soon"))
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(Color(white: 0.15))
                }
            }
            .frame(width: 200, height: 58)
            .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            Rectangle()
                .fill(Color(red: 0.55, green: 0.38, blue: 0.22))
                .frame(width: 5, height: 20)
        }
    }
}
