import SwiftUI

// The game's mood: how the results are named and drawn. Miniera (the default since v2.8, Nick: "in
// stile Minecraft") is the mine of Miniera.swift: ten finds, blocks of diamond and beacons, no points; for the
// map and the course's words it keeps the old gems' names. Minigolf, the extra, is one world with
// the map: hole in one, birdie, par, bogey, written as on a golf score card, with points and rounds
// of 18. A stored "gemme" (the old third mood) reads as Miniera. Picked in Settings > Gioco, kept in
// UserDefaults; whatever shows a result reads it when it draws.

enum GameMood: String, CaseIterable, Identifiable {
    case miniera, minigolf

    static let key = "gameMood"
    static let fallback = GameMood.miniera

    /// Once at launch: the old "gemme" is the mine now, so the picker shows it picked.
    static func migrate(_ defaults: UserDefaults = .standard) {
        if defaults.string(forKey: key) == "gemme" { defaults.set(GameMood.miniera.rawValue, forKey: key) }
    }

    /// The mood picked, read from UserDefaults (cheap: a string): for code that is not a view.
    static var current: GameMood { GameMood(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? fallback }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .miniera: return L("The Mine", "Miniera")
        case .minigolf: return L("Mini golf", "Minigolf")
        }
    }

    /// What it looks like, for the setting.
    var about: String {
        switch self {
        case .miniera:
            return L("Minecraft style: every estimate is a stroke of the pickaxe, from diamond to rotten flesh, and 9 diamonds make a block.",
                     "In stile Minecraft: ogni stima è un colpo di piccone, dal diamante alla carne marcia, e con 9 diamanti fai un blocco.")
        case .minigolf:
            return L("Extra: hole in one, birdie, par and bogey on a golf scorecard, with points and rounds of 18.",
                     "Extra: hole in one, birdie, par e bogey su uno scorecard da golf, con i punti e i giri da 18.")
        }
    }

    /// The card in the dashboard.
    var cardTitle: String {
        switch self {
        case .miniera: return L("The Mine", "La miniera")
        case .minigolf: return L("The scorecard", "Lo scorecard")
        }
    }

    var cardSubtitle: String {
        self == .miniera ? L("Every spot-on estimate is a diamond, 9 make a block", "Ogni stima centrata è un diamante, 9 fanno un blocco")
            : L("Every task is a hole, Claude's estimate is par", "Ogni task è una buca, la stima di Claude è il par")
    }

    /// A result's name: «Birdie» or «Zaffiro».
    func name(_ gem: Gem) -> String {
        switch self {
        case .minigolf: return gem.hole
        case .miniera: return gem.name
        }
    }

    /// What earns it, with the other mood's name where it helps.
    func detail(_ gem: Gem) -> String {
        switch self {
        case .minigolf: return gem.rule
        case .miniera: return "\(gem.hole.lowercased()), \(gem.rule)"
        }
    }

    /// A result at par or better, singular and plural: «buca buona», «gemma».
    var good: String { self == .minigolf ? L("good hole", "buca buona") : L("gem", "gemma") }
    var goods: String { self == .minigolf ? L("good holes", "buche buone") : L("gems", "gemme") }
    /// A result past the range: «bogey», «sasso».
    var bad: String { self == .minigolf ? L("bogey", "bogey") : L("pebble", "sasso") }
    var bads: String { self == .minigolf ? L("bogeys", "bogey") : L("pebbles", "sassi") }

    /// «1 buca buona», «12 buche buone»; «1 gemma», «12 gemme».
    func goods(_ n: Int) -> String { "\(n) \(n == 1 ? good : goods)" }
    func bads(_ n: Int) -> String { "\(n) \(n == 1 ? bad : bads)" }

    /// The row of the score card under the hole numbers.
    var rowLabel: String { self == .minigolf ? L("Result", "Esito") : L("Gem", "Gemma") }

    /// The score against par, in this mood's names.
    var parLine: String {
        Gem.allCases.map { "\(name($0).lowercased()) \(CampoData.signed(CampoHole.toPar($0)))" }.joined(separator: ", ")
    }

    var perDayTitle: String {
        switch self {
        case .minigolf: return L("HOLES PER DAY, LAST 2 WEEKS", "BUCHE PER GIORNO, ULTIME 2 SETTIMANE")
        case .miniera: return L("GEMS PER DAY, LAST 2 WEEKS", "GEMME PER GIORNO, ULTIME 2 SETTIMANE")
        }
    }

    /// The colours of the results in the charts: the course's greens and the flag, or the gems' cut.
    func color(_ gem: Gem, _ s: CampoStyle) -> Color {
        switch self {
        case .miniera: return gem.tones[1]
        case .minigolf:
            switch gem {
            case .diamond: return s.done
            case .sapphire: return s.dark ? Color(red: 0.45, green: 0.72, blue: 0.50) : Color(red: 0.43, green: 0.70, blue: 0.47)
            case .emerald: return s.laneOff
            case .pebble: return s.flag
            }
        }
    }
}

/// A result as this mood draws it: the score card mark or the cut gem. nil: a hole still to play.
struct ResultMark: View {
    let gem: Gem?
    var size: CGFloat = 18
    var mood: GameMood

    var body: some View {
        switch mood {
        case .miniera: GemView(gem: gem, size: size)
        case .minigolf: ScoreMarkView(gem: gem, size: size)
        }
    }
}

/// The marks of the score card, as Nick picked them for the Touch Bar: a hole in one is a filled
/// green disc in a ring, a birdie a circle, a par a dot, a bogey a square. Nothing moves.
struct ScoreMarkView: View {
    let gem: Gem?
    var size: CGFloat = 18
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let line = max(1.2, w * 0.08)
            let full = CGRect(x: line / 2 + w * 0.06, y: line / 2 + h * 0.06, width: w * 0.88 - line, height: h * 0.88 - line)
            guard let gem else {
                ctx.stroke(Path(ellipseIn: full.insetBy(dx: w * 0.14, dy: h * 0.14)), with: .color(s.todo),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                return
            }
            switch gem {
            case .diamond:
                ctx.stroke(Path(ellipseIn: full), with: .color(s.done), lineWidth: line)
                ctx.fill(Path(ellipseIn: full.insetBy(dx: w * 0.2, dy: h * 0.2)), with: .color(s.done))
            case .sapphire:
                ctx.stroke(Path(ellipseIn: full.insetBy(dx: w * 0.06, dy: h * 0.06)), with: .color(s.done), lineWidth: line)
            case .emerald:
                let r = w * 0.15
                ctx.fill(Path(ellipseIn: CGRect(x: w / 2 - r, y: h / 2 - r, width: 2 * r, height: 2 * r)), with: .color(s.ink))
            case .pebble:
                ctx.stroke(Path(full.insetBy(dx: w * 0.1, dy: h * 0.1)), with: .color(s.flag), lineWidth: line)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(gem.map(\.hole) ?? L("hole to play", "buca da giocare"))
    }
}

/// The mood picker: two (later more) choices side by side.
struct GameMoodPicker: View {
    @AppStorage(GameMood.key) private var moodRaw = GameMood.fallback.rawValue
    var showsAbout = true

    var body: some View {
        let mood = GameMood(rawValue: moodRaw) ?? .fallback
        VStack(alignment: .leading, spacing: 4) {
            Picker(L("Game mood", "Mood del gioco"), selection: $moodRaw) {
                ForEach(GameMood.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            if showsAbout {
                Text(mood.about).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

enum GameMoodTest {
    static func failures() -> [String] {
        var out: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { out.append(what) } }
        Loc.testing(.it) {
            check(GameMood.minigolf.name(.diamond) == "Hole in one" && GameMood.miniera.name(.diamond) == "Diamante", "mood names")
            check(GameMood.minigolf.goods(1) == "1 buca buona" && GameMood.minigolf.goods(3) == "3 buche buone", "mood minigolf goods")
            check(GameMood.miniera.goods(1) == "1 gemma" && GameMood.miniera.bads(2) == "2 sassi", "mood miniera words")
            check(GameMood.minigolf.parLine == "hole in one −2, birdie −1, par 0, bogey +1", "mood par line")
            check(GameMood.miniera.parLine == "diamante −2, zaffiro −1, smeraldo 0, sasso +1", "mood gemme par line")
        }
        Loc.testing(.en) {
            check(GameMood.minigolf.goods(1) == "1 good hole" && GameMood.minigolf.bads(2) == "2 bogeys"
                  && GameMood.miniera.goods(3) == "3 gems" && GameMood.miniera.bads(1) == "1 pebble", "mood words in English")
            check(GameMood.miniera.cardTitle == "The Mine" && GameMood.minigolf.title == "Mini golf", "mood titles in English")
        }
        check(GameMood(rawValue: "gemme") == nil && GameMood.fallback == .miniera, "mood fallback: the old gemme reads as miniera")
        return out
    }
}
