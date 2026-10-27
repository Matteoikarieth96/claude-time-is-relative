import Foundation

// The mini golf's history and its game layer: every game is kept (the last 500), and from them the
// streaks, the par of each hole, the points, the challenge of the day and the achievements. All in
// the app's own preferences, nothing leaves the Mac.

/// One game: from the first pull of the dot until the ball drops in, or is left alone.
struct GolfRecord: Codable, Equatable {
    var start: Double
    var end: Double
    var shots: Int
    var sunk: Bool
    /// Cushions of the shot that went in.
    var cushions: Int
    /// Cushions of all the game's shots.
    var totalCushions: Int
    var nearMisses: Int
    var points: Int

    var seconds: Double { max(0, end - start) }
}

/// What a hole is worth against par 3.
enum GolfPar {
    static let par = 3

    static func label(shots: Int) -> String {
        switch shots {
        case 1: return "Ace"
        case 2: return "Birdie"
        case 3: return "Par"
        case 4: return "Bogey"
        default: return L("Double bogey", "Doppio bogey")
        }
    }

    /// 100 for a hole, 50 more per cushion, doubled for an ace, 25 per hole of the streak before it.
    static func points(shots: Int, cushions: Int, streakBefore: Int) -> Int {
        (100 + 50 * cushions) * (shots == 1 ? 2 : 1) + 25 * streakBefore
    }
}

/// The challenge of the day: one of these, the same all day.
enum GolfChallenge: Int, CaseIterable {
    case bank2, twoShots, ace, oneCushion, fast, streak3

    var text: String {
        switch self {
        case .bank2: return L("hole with at least 2 cushions", "buca con almeno 2 sponde")
        case .twoShots: return L("hole in exactly 2 shots", "buca in 2 tiri esatti")
        case .ace: return L("hole in one", "hole in one")
        case .oneCushion: return L("hole with exactly 1 cushion", "buca con 1 sponda esatta")
        case .fast: return L("hole in under 10 seconds", "buca in meno di 10 secondi")
        case .streak3: return L("3 holes in a row", "3 buche di fila")
        }
    }

    static func of(_ date: Date = Date()) -> GolfChallenge {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return allCases[day % allCases.count]
    }

    func isMet(by game: GolfRecord, streak: Int) -> Bool {
        guard game.sunk else { return false }
        switch self {
        case .bank2: return game.cushions >= 2
        case .twoShots: return game.shots == 2
        case .ace: return game.shots == 1
        case .oneCushion: return game.cushions == 1
        case .fast: return game.seconds < 10
        case .streak3: return streak >= 3
        }
    }
}

/// The outcome of a finished game, for the sticker.
struct GolfResult: Equatable {
    var record: GolfRecord
    var par: String
    var streak: Int
    var newCushionRecord: Bool
    var challengeDone: Bool
    /// Holes in one in a row, this game included.
    var combo = 0
    /// The obstacles that were on the course (GolfRules.swift).
    var obstacles = 0
    /// The hole of the round of the day this game was (from 1), and the round's card after it.
    var roundHole: Int? = nil
    var round: GolfRoundCard? = nil
    /// The cushions that hole wanted on this course (on the back nine, exactly).
    var roundTarget = 0
}

struct GolfAchievement: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let how: String
    let earned: Bool
}

/// The round of the day: 18 holes, each asking for 0 to 5 cushions, drawn from the day itself (the
/// same all day, new at midnight). A hole drops only off at least that many cushions in the shot;
/// from hole 6 the course has obstacles and the ball starts somewhere at random; on the back nine
/// (from hole 10) the cushions must be exact, and each one more costs a stroke on the card. Once the
/// 18 are played the game is free until the next day.
struct GolfRound: Equatable {
    static let holes = 18
    static let maxCushions = 5
    let day: String
    let needs: [Int]

    static func of(_ date: Date = Date()) -> GolfRound {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        var random = GolfSeeded(state: UInt64(day) &* 0x9E37_79B9_7F4A_7C15)
        return GolfRound(day: GolfStats.dayKey(date), needs: (0..<holes).map { _ in Int.random(in: 0...maxCushions, using: &random) })
    }

    /// One obstacle from hole 6, one more every 3 holes, at most 4; and from 6 the ball does not
    /// start from the hole.
    static func obstacles(hole: Int) -> Int { hole < 6 ? 0 : min(4, 1 + (hole - 6) / 3) }
    static func ballAtRandom(hole: Int) -> Bool { hole >= 6 }
    /// Shots gone wrong in a hole of the round before the way out to the classic game shows.
    static let missesBeforeClassic = 4

    /// The back nine, from hole 10: the cushions must be exact. The ball drops anyway, also off
    /// fewer; each cushion off the number, more or fewer, turns the hole's points into minus 50
    /// apiece (`target` is what the course asks, at least 1 on the billiards).
    static let exactFrom = 10
    static let pointsPerCushionOff = 50
    static func exact(hole: Int) -> Bool { hole >= exactFrom }
    static func offBy(hole: Int, target: Int, cushions: Int) -> Int { exact(hole: hole) ? abs(cushions - target) : 0 }
}

/// The hole of the round of the day a game plays (from 1).
struct GolfRoundHole: Equatable {
    let round: GolfRound
    let hole: Int
    var cushions: Int { round.needs.indices.contains(hole - 1) ? round.needs[hole - 1] : 0 }
    var exact: Bool { GolfRound.exact(hole: hole) }
}

/// A round as played, kept for good: the cushions each hole asked for and, hole by hole, the shots
/// (0: the ball was left alone, a "–" on the card) and the cushions of the shot that went in.
struct GolfRoundCard: Codable, Equatable {
    var day: String
    var needs: [Int]
    var shots: [Int] = []
    var cushions: [Int] = []
    /// Hole by hole, how many cushions the shot that went in was off an exact hole's number (0 on
    /// the front nine): minus 50 points each. Missing in the cards saved before the back nine was exact.
    var offBy: [Int]?

    init(_ round: GolfRound) {
        day = round.day
        needs = round.needs
    }

    /// The hole the next game plays (from 1), nil once the 18 are played.
    var nextHole: Int? { shots.count < needs.count ? shots.count + 1 : nil }
    var done: Bool { nextHole == nil }
    var holesMade: Int { shots.filter { $0 > 0 }.count }
    /// Against par 3, over the holes made.
    var overPar: Int { shots.filter { $0 > 0 }.reduce(0) { $0 + $1 - GolfPar.par } }

    mutating func record(shots: Int, cushions: Int, offBy off: Int = 0) {
        guard !done else { return }
        offBy = (offBy ?? Array(repeating: 0, count: self.shots.count)) + [off]
        self.shots.append(shots)
        self.cushions.append(cushions)
    }

    /// The cushions a hole (from 1) was off its exact number.
    func offBy(hole: Int) -> Int { offBy.flatMap { $0.indices.contains(hole - 1) ? $0[hole - 1] : nil } ?? 0 }
    /// The points the wrong cushions took away, over the round.
    var pointsLost: Int { (offBy ?? []).reduce(0, +) * GolfRound.pointsPerCushionOff }
}

/// The same numbers from the same seed (SplitMix64): the round of a day, and the selftest.
struct GolfSeeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The history, kept in the app's preferences.
struct GolfStats {
    var games: [GolfRecord] = []
    /// Days (yyyy-MM-dd) the challenge was met.
    var challengeDays: [String] = []
    /// Every round of the day played, oldest first (kept apart: the games are only the last 500).
    var rounds: [GolfRoundCard] = []

    private static let gamesKey = "golfGames"
    private static let daysKey = "golfChallengeDays"
    private static let roundsKey = "golfRounds"

    /// Today's round as played so far (a new card when not started).
    func round(_ date: Date = Date()) -> GolfRoundCard {
        let today = GolfRound.of(date)
        return rounds.last { $0.day == today.day } ?? GolfRoundCard(today)
    }

    /// Writes a hole into the card of that round (the one of the day the game started).
    mutating func record(_ round: GolfRound, shots: Int, cushions: Int, offBy: Int = 0) -> GolfRoundCard {
        if let i = rounds.lastIndex(where: { $0.day == round.day }) {
            rounds[i].record(shots: shots, cushions: cushions, offBy: offBy)
            return rounds[i]
        }
        var card = GolfRoundCard(round)
        card.record(shots: shots, cushions: cushions, offBy: offBy)
        rounds.append(card)
        return card
    }

    /// What the dashboard shows: the saved games, or the sample ones with TASKETA_DEBUG_GOLF.
    static func forDashboard() -> GolfStats { DashDebug.golf ? sample() : load() }

    static func load(_ defaults: UserDefaults = .standard) -> GolfStats {
        var stats = GolfStats()
        if let data = defaults.data(forKey: gamesKey), let games = each(GolfRecord.self, data) {
            stats.games = games
        }
        stats.challengeDays = defaults.stringArray(forKey: daysKey) ?? []
        if let data = defaults.data(forKey: roundsKey), let rounds = each(GolfRoundCard.self, data) {
            stats.rounds = rounds
        }
        return stats
    }

    /// One record that cannot be read is skipped, not the whole list: the next save would write
    /// over all of them.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    private static func each<T: Decodable>(_ type: T.Type, _ data: Data) -> [T]? {
        (try? JSONDecoder().decode([Lenient<T>].self, from: data)).map { $0.compactMap(\.value) }
    }

    /// Changes whenever a game is saved (the games are only ever added at the end): for what is
    /// worked out from them, like the map's numbers.
    static func stamp(_ defaults: UserDefaults = .standard) -> String {
        defaults.data(forKey: gamesKey).map { "\($0.count):\($0.suffix(64).base64EncodedString())" } ?? ""
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(Array(games.suffix(500))) { defaults.set(data, forKey: GolfStats.gamesKey) }
        defaults.set(Array(challengeDays.suffix(400)), forKey: GolfStats.daysKey)
        if let data = try? JSONEncoder().encode(Array(rounds.suffix(1000))) { defaults.set(data, forKey: GolfStats.roundsKey) }
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - figures

    var holes: Int { games.filter(\.sunk).count }
    var aces: Int { games.filter { $0.sunk && $0.shots == 1 }.count }
    var shots: Int { games.reduce(0) { $0 + $1.shots } }
    var points: Int { games.reduce(0) { $0 + $1.points } }
    var nearMisses: Int { games.reduce(0) { $0 + $1.nearMisses } }
    var totalCushions: Int { games.reduce(0) { $0 + $1.totalCushions } }
    var bestCushions: Int { games.filter(\.sunk).map(\.cushions).max() ?? 0 }
    var bestPoints: Int { games.map(\.points).max() ?? 0 }
    var fastestHole: Double? { games.filter(\.sunk).map(\.seconds).min() }
    var shotsPerHole: Double? { holes == 0 ? nil : Double(games.filter(\.sunk).reduce(0) { $0 + $1.shots }) / Double(holes) }

    /// Holes in a row at the end of the history, and the longest run ever.
    var streak: Int { games.reversed().prefix { $0.sunk }.count }
    var bestStreak: Int {
        var best = 0, run = 0
        for g in games {
            run = g.sunk ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    /// The combo: holes in one in a row at the end of the history, and the longest run ever. From 5
    /// the course has obstacles (GolfObstacle).
    var combo: Int { games.reversed().prefix { $0.sunk && $0.shots == 1 }.count }
    var bestCombo: Int {
        var best = 0, run = 0
        for g in games {
            run = g.sunk && g.shots == 1 ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    /// Days in a row, up to today or yesterday, with the challenge met.
    var challengeStreak: Int {
        let done = Set(challengeDays)
        var day = Date()
        if !done.contains(GolfStats.dayKey(day)) { day = day.addingTimeInterval(-86400) }
        var n = 0
        while done.contains(GolfStats.dayKey(day)) {
            n += 1
            day = day.addingTimeInterval(-86400)
        }
        return n
    }

    var challengeDoneToday: Bool { challengeDays.contains(GolfStats.dayKey(Date())) }

    /// Holes by par label, in order: Ace, Birdie, Par, Bogey, Doppio bogey.
    var parCounts: [(label: String, count: Int)] {
        let sunk = games.filter(\.sunk)
        return (1...5).map { shots in
            (GolfPar.label(shots: shots), sunk.filter { shots == 5 ? $0.shots >= 5 : $0.shots == shots }.count)
        }
    }

    var bestGames: [GolfRecord] {
        Array(games.filter(\.sunk).sorted { ($0.points, -$0.shots) > ($1.points, -$1.shots) }.prefix(5))
    }

    // MARK: - a game ends

    /// Adds the game and says what it was worth.
    /// `offBy`: the cushions an exact hole of the round was off; then the hole is worth minus 50
    /// points apiece instead of its own.
    mutating func finish(start: Double, end: Double, shots: Int, sunk: Bool, cushions: Int,
                         totalCushions: Int, nearMisses: Int, offBy: Int = 0) -> GolfResult {
        let before = streak
        let oldBest = bestCushions
        var game = GolfRecord(start: start, end: end, shots: shots, sunk: sunk, cushions: sunk ? cushions : 0,
                              totalCushions: totalCushions, nearMisses: nearMisses, points: 0)
        if sunk {
            game.points = offBy > 0 ? -GolfRound.pointsPerCushionOff * offBy
                : GolfPar.points(shots: shots, cushions: cushions, streakBefore: before)
        }
        games.append(game)
        let now = streak
        let today = GolfStats.dayKey(Date(timeIntervalSince1970: end))
        var challengeDone = false
        if !challengeDays.contains(today), GolfChallenge.of(Date(timeIntervalSince1970: end)).isMet(by: game, streak: now) {
            challengeDays.append(today)
            challengeDone = true
        }
        return GolfResult(record: game, par: GolfPar.label(shots: shots), streak: now,
                          newCushionRecord: sunk && cushions > oldBest && cushions > 0, challengeDone: challengeDone,
                          combo: combo)
    }

    /// A few games, for snapshots and tests (TASKETA_DEBUG_GOLF shows them in the dashboard).
    static func sample(now: Double = Date().timeIntervalSince1970) -> GolfStats {
        var s = GolfStats()
        let games: [(shots: Int, sunk: Bool, cushions: Int, near: Int)] = [
            (3, true, 0, 1), (1, true, 0, 0), (2, true, 1, 2), (4, false, 0, 1), (2, true, 3, 0), (1, true, 2, 1), (3, true, 0, 0),
        ]
        for (i, g) in games.enumerated() {
            let start = now - Double(games.count - i) * 600
            _ = s.finish(start: start, end: start + 6 + Double(g.shots) * 4, shots: g.shots, sunk: g.sunk,
                         cushions: g.cushions, totalCushions: g.cushions + 1, nearMisses: g.near)
        }
        return s
    }

    // MARK: - achievements

    func achievements(dotClicks: Int, unlocked: Bool, unlockedByKeys: Bool) -> [GolfAchievement] {
        [
            GolfAchievement(id: "curious", emoji: "🟢", title: L("Curious", "Curioso"), how: L("8 clicks on the dot", "8 clic sul pallino"), earned: dotClicks >= 8),
            GolfAchievement(id: "nice", emoji: "😏", title: L("Nice", "Nice"), how: L("69 clicks on the dot", "69 clic sul pallino"), earned: dotClicks >= 69),
            GolfAchievement(id: "unlocked", emoji: "🔓", title: L("Unlocked", "Sbloccato"), how: L("open the mini golf", "apri il minigolf"), earned: unlocked),
            GolfAchievement(id: "slide", emoji: "⌨️", title: L("Shortcut", "Scorciatoia"), how: L("find the other way in", "scopri l'altra strada"), earned: unlockedByKeys),
            GolfAchievement(id: "first", emoji: "⛳", title: L("First hole", "Prima buca"), how: L("sink the ball", "fai una buca"), earned: holes >= 1),
            GolfAchievement(id: "ace", emoji: "🎯", title: L("Ace", "Ace"), how: L("in on the first shot", "buca al primo tiro"), earned: aces >= 1),
            GolfAchievement(id: "bank", emoji: "🎱", title: L("Bank shot", "Di sponda"), how: L("sink it off a cushion", "buca con una sponda"), earned: bestCushions >= 1),
            GolfAchievement(id: "billiard", emoji: "🔥", title: L("Billiards", "Biliardo"), how: L("sink it off 3 cushions", "buca con 3 sponde"), earned: bestCushions >= 3),
            GolfAchievement(id: "streak3", emoji: "🔁", title: L("Streak of 3", "Serie da 3"), how: L("3 holes in a row", "3 buche di fila"), earned: bestStreak >= 3),
            GolfAchievement(id: "near", emoji: "😱", title: L("So close!", "Quasi!"), how: L("5 near misses", "5 volte a un soffio"), earned: nearMisses >= 5),
            GolfAchievement(id: "points", emoji: "💯", title: L("A thousand", "Mille"), how: L("1,000 points in all", "1000 punti in tutto"), earned: points >= 1000),
            GolfAchievement(id: "daily", emoji: "📅", title: L("Challenge of the day", "Sfida del giorno"), how: L("win a challenge", "vinci una sfida"), earned: !challengeDays.isEmpty),
            GolfAchievement(id: "daily3", emoji: "🗓️", title: L("Three days", "Tre giorni"), how: L("challenges 3 days in a row", "sfide 3 giorni di fila"), earned: challengeStreak >= 3),
            GolfAchievement(id: "dino", emoji: "🦖", title: L("Coming soon", "Coming soon"), how: L("69 cushions in all", "69 sponde in tutto"), earned: totalCushions >= 69),
        ]
    }
}
