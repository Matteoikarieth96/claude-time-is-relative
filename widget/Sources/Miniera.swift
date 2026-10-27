import AppKit
import SwiftUI

// La miniera, the game's mood of partenza (GameMood.miniera): the estimates as a Minecraft mine.
// Every finished task with Claude's estimate is a stroke of the pickaxe, and what it finds says how
// close the estimate came: five good finds from the diamond (within 5%) to coal, then five bad ones
// from the cobweb to the rotten flesh. No points:
// 9 diamonds make a block of diamond, as on the crafting table, and the blocks are the goal. The
// last 16 strokes say which way the estimates miss. The icons are Minecraft's own, if the user saves them in
// ~/.claude/task-eta/minerali (Mojang's: never in the repo); a missing one is a plain coloured
// square. Worked out from task-eta's index, nothing is saved.

enum Ore: String, CaseIterable {
    case diamante, smeraldo, oro, ferro, carbone, ragnatela, patata, polvere, occhio, marcia

    /// The one rule: how far the real time went from the estimate, either way, and the likely range
    /// (seconds). Five good finds, carbone the last, then five bad ones from the cobweb to the
    /// rotten flesh. Within 5% is a diamond, with no floor.
    init(real: Double, estimate est: Double, range: (low: Double, high: Double)?) {
        let q = real / max(est, 1)
        let off = max(q, 1 / max(q, 0.0001))   // times off, longer or shorter
        let r = range ?? (est * 0.7, est * 1.5)
        if abs(real - est) <= est * 0.05 { self = .diamante }
        else if off <= 1.25 { self = .smeraldo }
        else if real >= r.low && real <= r.high { self = .oro }
        else if off <= 1.5 { self = .ferro }
        else if off <= 2 { self = .carbone }
        else if off <= 3 { self = .ragnatela }
        else if off <= 5 { self = .patata }
        else if off <= 7 { self = .polvere }
        else if off <= 10 { self = .occhio }
        else { self = .marcia }
    }

    var name: String {
        switch self {
        case .diamante: return L("Diamond", "Diamante")
        case .smeraldo: return L("Emerald", "Smeraldo")
        case .oro: return L("Gold Ingot", "Lingotto d'oro")
        case .ferro: return L("Iron Ingot", "Lingotto di ferro")
        case .carbone: return L("Coal", "Carbone")
        case .ragnatela: return L("Cobweb", "Ragnatela")
        case .patata: return L("Poisonous Potato", "Patata velenosa")
        case .polvere: return L("Gunpowder", "Polvere da sparo")
        case .occhio: return L("Spider Eye", "Occhio di ragno")
        case .marcia: return L("Rotten Flesh", "Carne marcia")
        }
    }

    /// For the Touch Bar and the menu bar.
    var short: String {
        switch self {
        case .oro: return L("Gold", "Oro")
        case .ferro: return L("Iron", "Ferro")
        case .patata: return L("Potato", "Patata")
        case .polvere: return L("Gunpowder", "Polvere")
        case .occhio: return L("Eye", "Occhio")
        default: return name
        }
    }

    /// "Volte" counts either way: twice as long or half as long are both "il doppio".
    var rule: String {
        switch self {
        case .diamante: return L("exact time, within 5%", "tempo esatto, entro il 5%")
        case .smeraldo: return L("within 25% of the estimate", "entro il 25% della stima")
        case .oro: return L("inside the range", "dentro la forchetta")
        case .ferro: return L("outside the range, within 1.5 times", "fuori dalla forchetta, entro una volta e mezza")
        case .carbone: return L("within 2 times", "entro il doppio")
        case .ragnatela: return L("off by up to 3 times", "sbagliata fino a 3 volte")
        case .patata: return L("off by up to 5 times", "sbagliata fino a 5 volte")
        case .polvere: return L("off by up to 7 times", "sbagliata fino a 7 volte")
        case .occhio: return L("off by up to 10 times", "sbagliata fino a 10 volte")
        case .marcia: return L("off by over 10 times", "sbagliata di oltre 10 volte")
        }
    }

    /// The wooden sign under each block: the kind of estimate.
    var sign: String {
        switch self {
        case .diamante: return L("Exact", "Esatta")
        case .smeraldo: return L("Nearly exact", "Quasi esatta")
        case .oro: return L("In range", "Nella forchetta")
        case .ferro: return L("A bit off", "Un po' fuori")
        case .carbone: return L("Borderline", "Al limite")
        case .ragnatela: return L("Wrong", "Sbagliata")
        case .patata: return L("Way off", "Molto sbagliata")
        case .polvere: return L("Blown up", "Esplosa")
        case .occhio: return L("Off track", "Fuori strada")
        case .marcia: return L("Junk", "Da buttare")
        }
    }

    /// Diamond to coal: an estimate to plan with, more or less.
    var isGood: Bool { Ore.allCases.firstIndex(of: self)! < 5 }

    /// The file of Minecraft's icon in ~/.claude/task-eta/minerali.
    var file: String {
        switch self {
        case .patata: return "patata-velenosa.png"
        case .polvere: return "polvere-da-sparo.png"
        case .occhio: return "occhio-di-ragno.png"
        case .marcia: return "carne-marcia.png"
        default: return rawValue + ".png"
        }
    }

    /// What the beacon's pyramid can be built of: Minecraft's four, and coal, the last good find.
    static let beaconBases: [Ore] = [.diamante, .smeraldo, .oro, .ferro, .carbone]

    /// The block of 9, for the beacon's pyramid.
    var blockFile: String { "blocco-\(rawValue).png" }

    /// What a thing is made of: «di diamante», «d'oro».
    var ofName: String { L("of \(blockName)", self == .oro ? "d'oro" : "di \(blockName)") }

    /// A pile of it, for the beacon's pyramid: «1 diamante», «14 diamanti», «81 lingotti d'oro».
    func pile(_ n: Int) -> String {
        if n == 1 { return "1 \(name.lowercased())" }
        switch self {
        case .diamante: return L("\(n) diamonds", "\(n) diamanti")
        case .smeraldo: return L("\(n) emeralds", "\(n) smeraldi")
        case .oro: return L("\(n) gold ingots", "\(n) lingotti d'oro")
        case .ferro: return L("\(n) iron ingots", "\(n) lingotti di ferro")
        case .carbone: return L("\(n) coal", "\(n) carboni")
        default: return "\(n) × \(name.lowercased())"
        }
    }

    /// The block's name: «Blocco di diamante».
    var blockName: String {
        switch self {
        case .diamante: return L("diamond", "diamante")
        case .smeraldo: return L("emerald", "smeraldo")
        case .oro: return L("gold", "oro")
        case .ferro: return L("iron", "ferro")
        case .carbone: return L("coal", "carbone")
        default: return name.lowercased()
        }
    }

    /// The square standing in for a missing icon, and the Touch Bar's colours: light and deep.
    var tones: (light: NSColor, deep: NSColor) {
        func c(_ hex: UInt32) -> NSColor {
            NSColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        switch self {
        case .diamante: return (c(0x4FD6D0), c(0x137A76))
        case .smeraldo: return (c(0x3CC46A), c(0x0B6E2E))
        case .oro: return (c(0xF0C433), c(0x9C6F08))
        case .ferro: return (c(0xD8D3CE), c(0x8C8782))
        case .carbone: return (c(0x4A4A4A), c(0x0E0E0E))
        case .ragnatela: return (c(0xE6E6E6), c(0x8F969A))
        case .patata: return (c(0xC8C24A), c(0x55682A))
        case .polvere: return (c(0x8A8A8A), c(0x3E3E3E))
        case .occhio: return (c(0xB0203A), c(0x5E0E1E))
        case .marcia: return (c(0xB8683E), c(0x6B3A1E))
        }
    }

    /// The end-of-task show for this find, so a 6% emerald gets no diamond's fireworks.
    func celebration(slow: Bool) -> Outcome {
        switch self {
        case .diamante: return .exact
        case .smeraldo, .oro: return .onTime
        default: return slow ? .slower : .faster
        }
    }

    /// Dark text on the light ones (Touch Bar).
    var lightTone: Bool { [.oro, .ferro, .ragnatela, .patata].contains(self) }
}

/// The game's level, as in Minecraft: wood at the start, then stone at the first block of diamond,
/// iron at the third, gold at the first beacon, diamond at the third. Never taken by itself:
/// Claude asks for it at the end of a reply (task_eta.py, the elapsed line), and it is taken on the
/// user's yes there (`piccone su`) or with the card's button. Kept in ~/.claude/task-eta/miniera.json,
/// shared with the hook.
enum Pickaxe: String, CaseIterable {
    case legno, pietra, ferro, oro, diamante

    var name: String {
        switch self {
        case .legno: return L("Wooden Pickaxe", "Piccone di legno")
        case .pietra: return L("Stone Pickaxe", "Piccone di pietra")
        case .ferro: return L("Iron Pickaxe", "Piccone di ferro")
        case .oro: return L("Golden Pickaxe", "Piccone d'oro")
        case .diamante: return L("Diamond Pickaxe", "Piccone di diamante")
        }
    }

    var file: String { "piccone-\(rawValue).png" }

    /// What earns it: blocks of diamond or beacons.
    var need: (blocks: Int, beacons: Int) {
        switch self {
        case .legno: return (0, 0)
        case .pietra: return (1, 0)
        case .ferro: return (3, 0)
        case .oro: return (0, 1)
        case .diamante: return (0, 3)
        }
    }

    var needText: String {
        let n = need
        if n.beacons > 0 {
            return L(n.beacons == 1 ? "1 Beacon lit" : "\(n.beacons) Beacons lit",
                     n.beacons == 1 ? "1 Faro acceso" : "\(n.beacons) Fari accesi")
        }
        return L(n.blocks == 1 ? "1 Block of Diamond" : "\(n.blocks) Blocks of Diamond",
                 n.blocks == 1 ? "1 blocco di diamante" : "\(n.blocks) blocchi di diamante")
    }

    var next: Pickaxe? {
        let all = Pickaxe.allCases
        let i = all.firstIndex(of: self)!
        return i + 1 < all.count ? all[i + 1] : nil
    }

    func earned(_ stats: MineStats) -> Bool { stats.blocks >= need.blocks && stats.beacons >= need.beacons }
}

/// The pickaxe in hand, from the file the hook shares; read again at most every 5 seconds.
enum MinePick {
    static var file: URL { TaskStore.indexURL.deletingLastPathComponent().appendingPathComponent("miniera.json") }
    private static var cache: (checked: Double, state: [String: Any])?

    static var state: [String: Any] {
        let now = Date().timeIntervalSince1970
        if let cache, now - cache.checked < 5 { return cache.state }
        let read = readFile()
        cache = (now, read)
        return read
    }

    private static func readFile() -> [String: Any] {
        (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    static var current: Pickaxe { (state["piccone"] as? String).flatMap(Pickaxe.init(rawValue:)) ?? .legno }

    /// The button's yes: the next pickaxe is taken, the hook's question goes away. Under the lock the
    /// hook takes too (mine_lock in task_eta.py), the file read again: if a session took it meanwhile
    /// (`piccone su`), nothing is undone, and it is taken only while still earned.
    static func take(_ pick: Pickaxe, stats: MineStats) {
        cache = nil
        let lock = open(file.path + ".lock", O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { return }
        defer { close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { return }
        defer { flock(lock, LOCK_UN) }
        var s = readFile()
        let before = (s["piccone"] as? String).flatMap(Pickaxe.init(rawValue:)) ?? .legno
        guard before.next == pick, pick.earned(stats) else { return }
        s["piccone"] = pick.rawValue
        s["pronto"] = NSNull()
        s["preso"] = Int(Date().timeIntervalSince1970)
        guard let data = try? JSONSerialization.data(withJSONObject: s, options: [.sortedKeys]) else { return }
        if Loc.writePrivate(data, to: file) { cache = (Date().timeIntervalSince1970, s) }
    }
}

/// Minecraft's icons, read from the folder the user fills by hand, again only when a file changes.
enum MineIcons {
    static var dir: URL { TaskStore.indexURL.deletingLastPathComponent().appendingPathComponent("minerali") }
    /// The crafted block, in the card.
    static let block = "blocco-diamante.png"
    /// The beacon on top of its pyramid.
    static let beacon = "faro.png"
    /// Every file the card can use, for the help text.
    static var files: [String] { Ore.allCases.map(\.file) + Ore.beaconBases.map(\.blockFile) + [beacon] + Pickaxe.allCases.map(\.file) }
    /// The ones not in the folder yet.
    static var missing: [String] { files.filter { image($0) == nil } }

    private static var cache: [String: (stamp: String, checked: Double, image: NSImage?)] = [:]

    /// The icon, from memory; the file is looked at again only if 5 seconds have gone by, so a
    /// redraw costs nothing and a new file still shows up.
    static func image(_ file: String) -> NSImage? {
        let now = Date().timeIntervalSince1970
        if let hit = cache[file], now - hit.checked < 5 { return hit.image }
        let path = dir.appendingPathComponent(file).path
        let stamp = fileStamp(path)
        if let hit = cache[file], hit.stamp == stamp {
            cache[file] = (stamp, now, hit.image)
            return hit.image
        }
        let image = stamp.isEmpty ? nil : NSImage(contentsOfFile: path)
        cache[file] = (stamp, now, image)
        return image
    }
}

/// An ore as the card draws it: Minecraft's icon when it is in the folder, sharp pixels, else a
/// coloured square with its edge. nil: an empty slot.
struct OreIcon: View {
    let ore: Ore?
    var file: String? = nil
    var size: CGFloat = 26

    var body: some View {
        if let ore {
            if let image = MineIcons.image(file ?? ore.file) ?? (file != nil ? MineIcons.image(ore.file) : nil) {
                Image(nsImage: image).interpolation(.none).resizable().scaledToFit().frame(width: size, height: size)
                    .accessibilityLabel(ore.name)
            } else {
                Rectangle().fill(Color(nsColor: ore.tones.light))
                    .overlay(Rectangle().strokeBorder(Color(nsColor: ore.tones.deep), lineWidth: max(2, size * 0.12)))
                    .frame(width: size * 0.7, height: size * 0.7)
                    .frame(width: size, height: size)
                    .accessibilityLabel(ore.name)
            }
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

struct MineStats {
    struct Hit: Equatable {
        let start: Double
        let real: Double
        let estimate: Double
        let ore: Ore
        var kind: String? = nil
        var segments = 1
        var tools = 0
        /// Subagents: their waking the task also stops and restarts it, not the user's fault.
        var agents = 0
        var end: Double { start + real }
        /// Past the estimate: it was too short.
        var slow: Bool { real > estimate }

        /// Silk touch: one turn only, and the tools of its kind (a quick up to 3, a medium up to 15).
        /// Clean strokes are good far more often: the habit that matters most.
        var clean: Bool {
            segments <= 1 && tools <= (kind == "quick" ? 3 : kind == "medium" ? 15 : Int.max)
        }

        /// Why it went so, and for a bad find what to do next. The first rule that holds wins.
        var why: String {
            let times = { (x: Double) -> String in
                x < 9.95 ? Loc.decimal(x, digits: 1) : "\(Int(x.rounded()))"
            }
            let pair = L("\(clock(real)) of \(clock(estimate))", "\(clock(real)) su \(clock(estimate))")
            if ore == .diamante { return L("Spot on: \(pair).", "Stima centrata: \(pair).") }
            if ore.isGood { return L("Close enough: \(pair).", "Abbastanza vicina: \(pair).") }
            if segments >= 2 && agents == 0 {
                let n = segments - 1
                return L("It stopped and restarted \(n == 1 ? "once" : "\(n) times"): the estimate was for a single turn. Write it all at the start, send the rest afterwards.",
                         "Si è fermato e ripartito \(n == 1 ? "1 volta" : "\(n) volte"): la stima era per un turno solo. Scrivi tutto all'inizio, il resto mandalo dopo.")
            }
            if kind == "quick", tools > 3 {
                return L("It was a quick one and used \(tools) tools. One thing at a time, or say it's a medium job.",
                         "Era un quick e ha usato \(tools) strumenti. Una cosa per volta, o di' che è un lavoro medio.")
            }
            if kind == "medium", tools > 15 {
                return L("It was a medium one and used \(tools) tools. Split it into two prompts.",
                         "Era un medium e ha usato \(tools) strumenti. Spezzalo in due prompt.")
            }
            if slow {
                let x = times(real / max(estimate, 1))
                return L("\(x) times the estimate: the job was bigger. Ask for one piece at a time.",
                         "\(x) volte la stima: il lavoro era più grosso. Chiedi un pezzo alla volta.")
            }
            return L("Done in \(pair): Claude played it safe. You can ask for more at once.",
                     "Finito in \(pair): Claude si è tenuto largo. Puoi chiedere di più in una volta.")
        }
    }

    static let perBlock = 9
    /// Minecraft goes by 16: the strokes the card reads.
    static let window = 16

    private(set) var hits: [Hit] = []   // oldest first
    private(set) var now = Date()
    /// Worked out once, here: the card reads them many times per redraw.
    private(set) var counts: [Ore: Int] = [:]
    private(set) var weeks: [Week] = []

    init(_ tasks: [PastTask], now: Date = Date()) {
        self.now = now
        hits = tasks.compactMap { t -> Hit? in
            guard let est = t.estimate, est > 0 else { return nil }
            return Hit(start: t.start, real: t.real, estimate: est, ore: Ore(real: t.real, estimate: est, range: t.range),
                       kind: t.kind, segments: t.segments, tools: t.tools, agents: t.agents)
        }
        .sorted { $0.start < $1.start }
        for h in hits { counts[h.ore, default: 0] += 1 }
        weeks = MineStats.weeks(hits)
    }

    init() {}

    func count(_ ore: Ore) -> Int { counts[ore] ?? 0 }
    /// The vein: good strokes in a row up to now, and the longest ever.
    var vein: Int { hits.reversed().prefix { $0.ore.isGood }.count }
    var bestVein: Int {
        var best = 0, run = 0
        for h in hits { run = h.ore.isGood ? run + 1 : 0; best = max(best, run) }
        return best
    }

    /// Good strokes out of these, in percent; nil with fewer than 10 to count.
    static func goodShare(_ hits: [Hit]) -> Int? {
        hits.count < 10 ? nil : Int((Double(hits.filter(\.ore.isGood).count) / Double(hits.count) * 100).rounded())
    }

    /// A week from Monday: its strokes and the good ones (diamond to coal).
    struct Week: Equatable {
        let start: Date
        var strokes = 0
        var good = 0
        /// What was found, by kind, and how: the clean strokes (silk touch) and the good ones among them.
        var ores: [Ore: Int] = [:]
        var clean = 0
        var cleanGood = 0
        var share: Double { strokes == 0 ? 0 : Double(good) / Double(strokes) }
        var percent: Int { Int((share * 100).rounded(.down)) }
        /// «19–25 ott».
        var days: String {
            let end = MineStats.calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let f = DateFormatter()
            f.locale = Loc.locale
            f.dateFormat = "d MMM"
            let d = DateFormatter()
            d.dateFormat = "d"
            let sameMonth = Calendar.current.component(.month, from: start) == Calendar.current.component(.month, from: end)
            return (sameMonth ? d.string(from: start) : f.string(from: start)) + "–" + f.string(from: end)
        }
        /// The beacon: 80% good in a week, with at least 20 strokes.
        var lit: Bool { strokes >= MineStats.beaconStrokes && share >= MineStats.beaconShare }
    }

    static let beaconShare = 0.8
    static let beaconStrokes = 20

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    /// Every week with a stroke, oldest first.
    private static func weeks(_ hits: [Hit]) -> [Week] {
        let cal = MineStats.calendar
        var out: [Date: Week] = [:]
        for h in hits {
            guard let start = cal.dateInterval(of: .weekOfYear, for: Date(timeIntervalSince1970: h.end))?.start else { continue }
            var w = out[start] ?? Week(start: start)
            w.strokes += 1
            if h.ore.isGood { w.good += 1 }
            w.ores[h.ore, default: 0] += 1
            if h.clean {
                w.clean += 1
                if h.ore.isGood { w.cleanGood += 1 }
            }
            out[start] = w
        }
        return out.values.sorted { $0.start < $1.start }
    }

    /// The week before this one, if it had strokes.
    var lastWeek: Week? {
        let start = thisWeek.start
        return weeks.last { $0.start < start }
    }

    /// The strokes of this week, oldest first: what the advice reads.
    var weekHits: [Hit] {
        let start = thisWeek.start.timeIntervalSince1970
        return hits.filter { $0.end >= start }
    }

    /// This week so far.
    var thisWeek: Week {
        let start = MineStats.calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return weeks.first { $0.start == start } ?? Week(start: start)
    }

    /// The beacons lit: the weeks at 80% (this one too, while it holds).
    var beacons: Int { weeks.filter(\.lit).count }
    var diamonds: Int { count(.diamante) }
    var blocks: Int { diamonds / MineStats.perBlock }
    /// Diamonds on the crafting table, toward the next block.
    var toNext: Int { diamonds % MineStats.perBlock }
    var recent: [Hit] { Array(hits.suffix(MineStats.window)) }

    func isToday(_ hit: Hit) -> Bool { hit.end >= Calendar.current.startOfDay(for: now).timeIntervalSince1970 }

    /// The last 16 strokes in words: how many good, and which way the misses go, with what to do.
    var advice: String {
        let r = weekHits
        guard !r.isEmpty else {
            return hits.isEmpty ? L("No strokes yet: Claude's first estimate opens the mine.", "Nessun colpo ancora: la prima stima di Claude apre la miniera.")
                : L("No strokes yet this week.", "Questa settimana nessun colpo ancora.")
        }
        let good = r.filter(\.ore.isGood).count
        let dia = r.filter { $0.ore == .diamante }.count
        let head = L("\(good) good out of \(r.count)", "\(good) buoni su \(r.count)")
            + (dia == 0 ? "." : dia == 1 ? L(", with 1 diamond.", ", con 1 diamante.") : L(", with \(dia) diamonds.", ", con \(dia) diamanti."))
        let miss = r.filter { !$0.ore.isGood }
        guard !miss.isEmpty else { return head + L(" No wrong estimates: you can plan around Claude's times.", " Nessuna stima sbagliata: puoi organizzarti sui tempi di Claude.") }
        let slow = miss.filter(\.slow).count, fast = miss.count - slow
        let short = L("the job was bigger than it looked. Ask for one piece at a time.", "il lavoro era più grosso di come sembrava. Chiedi un pezzo alla volta.")
        let long = L("the job was simpler than expected. You can ask for more at once.", "il lavoro era più semplice del previsto. Puoi chiedere di più in una volta.")
        if miss.count == 1 {
            return head + L(" The only wrong estimate was too ", " L'unica stima sbagliata era troppo ")
                + (slow == 1 ? L("short: ", "corta: ") + short : L("long: ", "lunga: ") + long)
        }
        let of = L(" Of the \(miss.count) wrong estimates, ", " Delle \(miss.count) stime sbagliate, ")
        if slow >= 2 * fast {
            return head + of + L(slow == 1 ? "1 was too short: " : "\(slow) were too short: ", slow == 1 ? "1 era troppo corta: " : "\(slow) erano troppo corte: ") + short
        }
        if fast >= 2 * slow {
            return head + of + L(fast == 1 ? "1 was too long: " : "\(fast) were too long: ", fast == 1 ? "1 era troppo lunga: " : "\(fast) erano troppo lunghe: ") + long
        }
        return head + of + L("\(slow) too short and \(fast) too long: take them as a ballpark.", "\(slow) troppo corte e \(fast) troppo lunghe: prendile come ordine di grandezza.")
    }

    private static var cache: (key: String, stats: MineStats)?

    /// The mine of the index on disk, made again only when it changes or the day turns: one copy
    /// for the Touch Bar and the iPhone's server (main thread).
    static func current(_ index: URL = TaskStore.indexURL) -> MineStats {
        let key = "\(index.path)|\(fileStamp(index.path))|\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)"
        if let cache, cache.key == key { return cache.stats }
        let stats = MineStats(PastTask.loadShared(from: index))
        cache = (key, stats)
        return stats
    }

    /// For TASKETA_DEBUG_GEMS and the tests: 20 strokes, 12 of them diamonds.
    static func sample(now: Date = Date()) -> MineStats {
        let t = now.timeIntervalSince1970
        let reals: [Double] = [300, 300, 330, 300, 900, 300, 380, 300, 300, 700, 300, 300, 2400, 300, 120, 300, 340, 300, 300, 650]
        let tasks = reals.enumerated().map { i, real in
            PastTask(id: "m\(i)", start: t - Double(reals.count - i) * 900 - real, real: real, estimate: 300,
                     range: (200, 450), model: "opus-5-5 xhigh", project: "demo", prompt: "", session: nil)
        }
        return MineStats(tasks, now: now)
    }
}

extension PastTask {
    private static var shared: (key: String, tasks: [PastTask])?

    /// The index's tasks, read once per change of the file for every reader on the main thread
    /// (the gems and the mine, for the Touch Bar and the iPhone's server).
    static func loadShared(from index: URL) -> [PastTask] {
        let key = "\(index.path)|\(fileStamp(index.path))"
        if let shared, shared.key == key { return shared.tasks }
        let tasks = PastTask.load(from: index)
        shared = (key, tasks)
        return tasks
    }
}

/// «primo», «quinto», «decimo»: the blocks in words.
func ordinal(_ n: Int) -> String {
    let words = [L("first", "primo"), L("second", "secondo"), L("third", "terzo"), L("fourth", "quarto"), L("fifth", "quinto"),
                 L("sixth", "sesto"), L("seventh", "settimo"), L("eighth", "ottavo"), L("ninth", "nono"), L("tenth", "decimo")]
    guard n >= 1 && n <= words.count else {
        let suffix = (11...13).contains(n % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
        return L("\(n)\(suffix)", "\(n)°")
    }
    return words[n - 1]
}

// MARK: - the look: Minecraft's inventory

enum MC {
    static func grey(_ v: Double) -> Color { Color(red: v, green: v, blue: v) }
    static let panel = grey(0.776)      // #C6C6C6
    static let shade = grey(0.333)      // #555555
    static let slot = grey(0.545)       // #8B8B8B
    static let slotEdge = grey(0.216)   // #373737
    static let ink = grey(0.247)        // #3F3F3F
    static let muted = grey(0.333)
    static let button = grey(0.478)     // #7A7A7A
    static let today = Color(red: 1.0, green: 0.85, blue: 0.29)
    static let velvet = Color(red: 0.66, green: 0.49, blue: 0.97)   // #A97CF8, silk touch

    /// Pixelify Sans (OFL, in Resources/miniera/fonts), registered once; false when it is missing.
    static let ready: Bool = {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("miniera/fonts") else { return false }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: "Pixelify Sans", size: 12) != nil || NSFont(name: "PixelifySans-Regular", size: 12) != nil
    }()

    private static var fonts: [String: Font] = [:]

    /// The face at a weight of its own axis, with the ligatures off: Pixelify's «fi» drew as an «A».
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let w: Double = weight == .bold ? 700 : weight == .semibold ? 600 : weight == .medium ? 500 : 400
        let key = "\(size)|\(w)"
        if let hit = fonts[key] { return hit }
        guard ready, let base = NSFont(name: "Pixelify Sans", size: size) ?? NSFont(name: "PixelifySans-Regular", size: size) else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kLigaturesType,
                                NSFontDescriptor.FeatureKey.selectorIdentifier: kCommonLigaturesOffSelector]],
            .variation: [NSNumber(value: 0x7767_6874): w],   // 'wght'
        ])
        let font = Font(NSFont(descriptor: descriptor, size: size) ?? base)
        fonts[key] = font
        return font
    }

    /// Pixelify's 5 reads as an S and its 2 as a Z: digits come from VT323 (OFL), a pixel face with
    /// clear ones, a little bigger to match.
    static func digits(_ size: CGFloat) -> Font {
        let key = "digits|\(size)"
        if let hit = fonts[key] { return hit }
        guard ready, let face = NSFont(name: "VT323-Regular", size: size * 1.3) else { return font(size) }
        let font = Font(face)
        fonts[key] = font
        return font
    }

    /// A line in the mine's type: letters in Pixelify, digits in VT323.
    static func text(_ s: String, _ size: CGFloat, _ weight: Font.Weight = .regular) -> Text {
        var out = Text(verbatim: "")
        var run = ""
        var inDigits: Bool?
        func flush() {
            guard !run.isEmpty else { return }
            out = out + Text(verbatim: run).font(inDigits == true ? digits(size) : font(size, weight))
            run = ""
        }
        for ch in s {
            let digit = ch.isASCII && ch.isNumber
            if let inDigits, inDigits != digit { flush() }
            inDigits = digit
            run.append(ch)
        }
        flush()
        return out
    }

    /// A line with its key words in bold, marked **like this**.
    static func rich(_ text: String, _ size: CGFloat) -> Text {
        text.components(separatedBy: "**").enumerated().reduce(Text(verbatim: "")) { line, part in
            line + self.text(part.element, size, part.offset % 2 == 1 ? .bold : .regular)
        }
    }
}

/// Light on the top and left edges, dark on the bottom and right: the raised or sunk look of the GUI.
struct Bevel: ViewModifier {
    let top: Color
    let bottom: Color
    var width: CGFloat = 3

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) { top.frame(height: width) }
            .overlay(alignment: .leading) { top.frame(width: width) }
            .overlay(alignment: .bottom) { bottom.frame(height: width) }
            .overlay(alignment: .trailing) { bottom.frame(width: width) }
    }
}

extension View {
    func bevel(_ top: Color, _ bottom: Color, _ width: CGFloat = 3) -> some View { modifier(Bevel(top: top, bottom: bottom, width: width)) }

    /// The inventory's panel: light grey, raised, with a black outline.
    func mcPanel() -> some View {
        background(MC.panel).bevel(.white, MC.shade, 4).padding(2).background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    /// White text with the hard shadow of Minecraft's labels.
    func mcLabel() -> some View { foregroundStyle(.white).shadow(color: MC.ink, radius: 0, x: 1.5, y: 1.5) }
}

/// A slot of the inventory, sunk: an icon in it, the stack's count in its corner, today's strokes
/// with a yellow bottom edge.
struct MCSlot<Content: View>: View {
    var size: CGFloat = 40
    var count: Int? = nil
    var today = false
    /// Silk touch: a violet top edge.
    var velvet = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack { MC.slot; content() }
            .frame(width: size, height: size)
            .bevel(MC.slotEdge, today ? MC.today : .white, 2)
            .overlay(alignment: .top) { if velvet { MC.velvet.frame(height: 3) } }
            .overlay(alignment: .bottomTrailing) {
                if let count, count > 0 {
                    MC.text("\(count)", size * 0.34, .medium).mcLabel().padding(.trailing, 3).padding(.bottom, 1)
                }
            }
    }
}

/// A wooden sign, as in Minecraft: dark letters on an oak plank.
struct MCSign: View {
    let text: String
    var size: CGFloat = 11
    /// Two in the narrow columns of the scale, so «Nella forchetta» is never cut.
    var lines = 1

    var body: some View {
        MC.text(text, size, .medium).foregroundStyle(Color(red: 0.17, green: 0.11, blue: 0.05))
            .lineLimit(lines).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: lines > 1)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Color(red: 0.69, green: 0.54, blue: 0.33))
            .bevel(Color(red: 0.80, green: 0.66, blue: 0.43), Color(red: 0.45, green: 0.33, blue: 0.17), 1.5)
    }
}

/// The crafting table's grey arrow, as on the recipe.
struct MCArrow: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var p = Path()
            p.addRect(CGRect(x: 0, y: h * 0.36, width: w * 0.55, height: h * 0.28))
            p.move(to: CGPoint(x: w * 0.5, y: h * 0.12))
            p.addLine(to: CGPoint(x: w, y: h * 0.5))
            p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.88))
            p.closeSubpath()
            ctx.fill(p, with: .color(MC.slot))
        }
        .frame(width: 40, height: 30)
        .accessibilityHidden(true)
    }
}

/// What the mine card keeps behind a button.
enum MineDetail: String, CaseIterable, Identifiable {
    case inventory, guide, styles
    var id: String { rawValue }

    var title: String {
        switch self {
        case .inventory: return L("Inventory", "Inventario")
        case .guide: return L("What it's for", "A cosa serve")
        case .styles: return L("iPhone styles", "Stili iPhone")
        }
    }

    static var debugOpen: MineDetail? { DashDebug.flags.lazy.compactMap { MineDetail(rawValue: $0) }.first }
}

// MARK: - the card

/// The mine in the dashboard: the crafting table with the diamonds toward the next block, the
/// blocks made, the last 16 strokes (today's with a yellow edge) and what they say, the next style
/// to win. Inventory, what it is for and the iPhone's styles wait behind their buttons: open as
/// soon as the pointer is on one, kept open by a click. Nothing moves.
struct MinieraCard: View {
    let stats: MineStats
    /// For the iPhone's styles won with the golf's rules too.
    var gems = GemStats()
    /// A find clicked: the History shows its tasks, in that week (nil: all of them).
    var onFind: ((Ore, Date?) -> Void)? = nil
    /// Bumped by the button, so the card draws the new pickaxe at once.
    @State private var picked = 0
    /// The beacon beside the rest (a wide widget) or under it.
    var wide = true
    @State private var hovered: MineDetail?
    @State private var pinned: MineDetail? = MineDetail.debugOpen

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if wide {
                HStack(alignment: .top, spacing: 24) {
                    main.frame(maxWidth: .infinity, alignment: .leading)
                    MineBeacon(stats: stats).frame(width: 230)
                }
            } else {
                main
                MineBeacon(stats: stats).frame(maxWidth: .infinity)
            }
            details
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .mcPanel()
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                MC.text(L("The Mine", "La miniera"), 22, .medium).foregroundStyle(MC.ink)
                MC.text(L("Every exact estimate (within 5%) is a diamond. 9 diamonds make a block.",
                          "Ogni stima esatta (entro il 5%) è un diamante. Con 9 diamanti fai un blocco."), 14)
                    .foregroundStyle(MC.muted).fixedSize(horizontal: false, vertical: true)
            }
            pickaxe
            crafting
            week
            weeksBefore
            if let last = stats.hits.last {
                MC.rich(L("Last stroke: **\(last.ore.name)**. \(last.why)", "Ultimo colpo: **\(last.ore.name)**. \(last.why)"), 15)
                    .foregroundStyle(MC.ink).fixedSize(horizontal: false, vertical: true)
            }
            MC.text(stats.advice, 15).foregroundStyle(MC.ink).fixedSize(horizontal: false, vertical: true)
            MC.rich(velvetLine, 15).foregroundStyle(MC.ink).fixedSize(horizontal: false, vertical: true)
            MC.text(nextStyle, 15).foregroundStyle(MC.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The crafting table: the diamonds so far toward the next block, the arrow, the blocks made.
    private var crafting: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { col in
                            MCSlot(size: 40) { OreIcon(ore: row * 3 + col < stats.toNext ? .diamante : nil, size: 28) }
                        }
                    }
                }
            }
            MCArrow()
            MCSlot(size: 56, count: stats.blocks) {
                if stats.blocks > 0 { OreIcon(ore: .diamante, file: MineIcons.block, size: 40) }
            }
            VStack(alignment: .leading, spacing: 3) {
                MC.text(L(stats.blocks == 1 ? "1 Block of Diamond" : "\(stats.blocks) Blocks of Diamond",
                          stats.blocks == 1 ? "1 blocco di diamante" : "\(stats.blocks) blocchi di diamante"), 20, .medium).foregroundStyle(MC.ink)
                MC.text(L("\(stats.toNext) of 9 diamonds toward the \(ordinal(stats.blocks + 1)) block.",
                          "\(stats.toNext) \(stats.toNext == 1 ? "diamante" : "diamanti") su 9 verso il \(ordinal(stats.blocks + 1))."), 15)
                    .foregroundStyle(MC.ink)
                MC.rich(veinLine, 15).foregroundStyle(MC.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// The level: the pickaxe in hand, the next one and what it wants; once earned, the button.
    private var pickaxe: some View {
        let _ = picked
        let now = MinePick.current
        return HStack(alignment: .center, spacing: 12) {
            MCSlot(size: 48) { MineIconImage(file: now.file, size: 34) }
            VStack(alignment: .leading, spacing: 4) {
                MC.text(now.name, 17, .bold).foregroundStyle(MC.ink)
                if let next = now.next {
                    if next.earned(stats) {
                        let asked = (MinePick.state["pronto"] as? String) == next.rawValue
                        MC.rich(L("You've earned the **\(next.name)**: ", "Hai i requisiti per il **\(next.name.lowercased())**: ")
                                + (asked ? L("Claude will tell you at the end of a reply (answer “take the pickaxe”), or take it here.",
                                             "Claude te lo dice a fine risposta (rispondi «prendi il piccone»), oppure prendilo qui.")
                                         : L("take it here.", "prendilo qui.")), 14)
                            .foregroundStyle(MC.ink).fixedSize(horizontal: false, vertical: true)
                        Button { MinePick.take(next, stats: stats); picked += 1 } label: {
                            MC.text(L("Take the \(next.name)", "Prendi il \(next.name.lowercased())"), 14).mcLabel()
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(MC.button).bevel(MC.grey(0.66), MC.grey(0.29), 2)
                                .padding(2).background(Color.black)
                        }
                        .buttonStyle(.plain)
                    } else {
                        MC.text(L("Next: the \(next.name), with \(next.needText).", "Prossimo: \(next.name.lowercased()), con \(next.needText)."), 14)
                            .foregroundStyle(MC.muted).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    MC.text(L("You have the strongest pickaxe.", "Hai il piccone più forte."), 14).foregroundStyle(MC.muted)
                }
            }
        }
    }

    /// Good strokes in a row: a goal on every task, while a block takes days.
    private var veinLine: String {
        let v = stats.vein, best = stats.bestVein
        if stats.hits.isEmpty { return L("The vein starts with your first good stroke.", "Il filone parte dal primo colpo buono.") }
        if v == 0 {
            return L("Vein broken. Record: \(best) good \(best == 1 ? "stroke" : "strokes") in a row.",
                     "Filone interrotto. Record: \(best) \(best == 1 ? "colpo buono" : "colpi buoni") di fila.")
        }
        let now = L(v == 1 ? "1 good stroke" : "\(v) good strokes", v == 1 ? "1 colpo buono" : "\(v) colpi buoni")
        if v >= 5 && v == best { return L("**Vein: \(now) in a row. New record!**", "**Filone: \(now) di fila. Nuovo record!**") }
        return L("Vein: **\(now) in a row**. Record: \(best).", "Filone: **\(now) di fila**. Record: \(best).")
    }

    /// This week: every find by kind, as stacks, the good share and the week before. A stack opens
    /// the History on its tasks. The goal is a beacon a week: 80% good with at least 20 strokes.
    private var week: some View {
        let w = stats.thisWeek
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                MC.text(L("This week", "Questa settimana"), 16, .medium).foregroundStyle(MC.ink)
                MC.text(w.days, 13).foregroundStyle(MC.muted)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach([Array(Ore.allCases.prefix(5)), Array(Ore.allCases.suffix(5))], id: \.first) { row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { ore in findSlot(ore, count: w.ores[ore] ?? 0, week: w.start) }
                    }
                }
            }
            MC.rich(weekLine(w), 15).foregroundStyle(MC.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A stack of one find in a week; a click opens the History on those tasks.
    private func findSlot(_ ore: Ore, count: Int, week: Date?) -> some View {
        MCSlot(size: 42, count: count) { OreIcon(ore: ore, size: 28).opacity(count > 0 ? 1 : 0.3) }
            .contentShape(Rectangle())
            .onTapGesture { if count > 0 { onFind?(ore, week) } }
            .help(count > 0
                  ? L("\(ore.name) (\(ore.sign.lowercased())): \(count) \(count == 1 ? "stroke" : "strokes"). Click: their prompts in History",
                      "\(ore.name) (\(ore.sign.lowercased())): \(count) \(count == 1 ? "colpo" : "colpi"). Clic: i loro prompt nello Storico")
                  : L("\(ore.name): none", "\(ore.name): nessuno"))
    }

    /// The good share against the week before, and what it means for the beacon.
    private func weekLine(_ w: MineStats.Week) -> String {
        guard w.strokes > 0 else {
            return L("No strokes yet: the week starts with the first task with an estimate.", "Nessun colpo ancora: la settimana parte col primo task con la stima.")
        }
        var line = L("**\(w.percent)% good** out of \(MineBeacon.strokes(w.strokes))", "**\(w.percent)% buoni** su \(MineBeacon.strokes(w.strokes))")
        if let before = stats.lastWeek, before.strokes > 0 {
            let d = w.percent - before.percent
            line += d == 0 ? L(", same as last week", ", come la settimana scorsa")
                : L(", **\(d > 0 ? "+" : "−")\(abs(d)) point\(abs(d) == 1 ? "" : "s")** vs last week (\(before.percent)%)",
                    ", **\(d > 0 ? "+" : "−")\(abs(d)) punti** sulla settimana scorsa (\(before.percent)%)")
        }
        line += w.lit ? L(". **Beacon lit.**", ". **Faro acceso.**")
            : L(". The beacon lights at 80%", ". Il faro si accende all'80%")
                + (w.strokes < MineStats.beaconStrokes
                   ? L(", with at least \(MineStats.beaconStrokes) strokes.", ", con almeno \(MineStats.beaconStrokes) colpi.") : ".")
        return line
    }

    /// The weeks before, newest first: the good share, the beacon if lit, what was found most.
    @ViewBuilder
    private var weeksBefore: some View {
        let before = Array(stats.weeks.filter { $0.start < stats.thisWeek.start }.reversed().prefix(6))
        if before.isEmpty {
            MC.text(L("Past weeks show up here from Monday, so you can see if the estimates improve.",
                      "Le settimane passate compaiono qui da lunedì: così vedi se le stime migliorano."), 13).foregroundStyle(MC.muted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                MC.text(L("Past weeks", "Le settimane passate"), 14, .medium).foregroundStyle(MC.ink)
                ForEach(before, id: \.start) { w in
                    HStack(spacing: 8) {
                        MC.text(w.days, 13).foregroundStyle(MC.muted).frame(width: 96, alignment: .leading)
                        MC.rich("**\(w.percent)%**", 14).foregroundStyle(MC.ink).frame(width: 44, alignment: .leading)
                        if w.lit { MineIconImage(file: MineIcons.beacon, size: 16).help(L("Beacon lit", "Faro acceso")) }
                        ForEach(w.ores.sorted { $0.value > $1.value }.prefix(4).map(\.key), id: \.self) { ore in
                            HStack(spacing: 2) {
                                OreIcon(ore: ore, size: 16)
                                MC.text("\(w.ores[ore] ?? 0)", 12).foregroundStyle(MC.ink)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onFind?(ore, w.start) }
                            .help(L("\(ore.name): their prompts in History", "\(ore.name): i loro prompt nello Storico"))
                        }
                        Spacer(minLength: 0)
                        MC.text(MineBeacon.strokes(w.strokes), 12).foregroundStyle(MC.muted)
                    }
                }
            }
        }
    }

    /// Silk touch this week: how many, and how they went against the others.
    private var velvetLine: String {
        let r = stats.weekHits
        let c = r.filter(\.clean), others = r.filter { !$0.clean }
        guard !r.isEmpty else {
            return L("**Silk Touch** is a stroke with a single turn and few tools.", "Il **tocco di velluto** è un colpo con un turno solo e pochi strumenti.")
        }
        guard !c.isEmpty else {
            return L("No Silk Touch this week: **a single turn and few tools**.", "Nessun tocco di velluto questa settimana: **un turno solo e pochi strumenti**.")
        }
        let good = c.filter(\.ore.isGood).count, othersGood = others.filter(\.ore.isGood).count
        return L("**Silk Touch** on \(c.count) of \(r.count) strokes this week: \(good) good. Without it: \(othersGood) good out of \(others.count).",
                 "**Tocco di velluto** in \(c.count) \(c.count == 1 ? "colpo" : "colpi") su \(r.count) questa settimana: \(good) buoni. Senza: \(othersGood) buoni su \(others.count).")
    }

    /// The last 16 strokes, two rows of 8.
    private var recent: some View {
        let r = stats.recent
        let anyToday = r.contains { stats.isToday($0) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                MC.text(L("Last \(MineStats.window) strokes", "Ultimi \(MineStats.window) colpi"), 16).foregroundStyle(MC.ink)
                if anyToday { MC.text(L("yellow edge: today", "bordo giallo: oggi"), 13).foregroundStyle(MC.muted) }
                if r.contains(where: \.clean) { MC.text(L("violet edge: Silk Touch", "bordo viola: tocco di velluto"), 13).foregroundStyle(MC.muted) }
            }
            if r.isEmpty {
                MC.text(L("No strokes yet.", "Ancora nessun colpo."), 14).foregroundStyle(MC.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { col in
                                let i = row * 8 + col
                                if i < r.count {
                                    let h = r[i]
                                    MCSlot(size: 40, today: stats.isToday(h), velvet: h.clean) { OreIcon(ore: h.ore, size: 28) }
                                        .help(L("\(h.ore.name) (\(h.ore.sign.lowercased())): \(clock(h.real)) of a \(clock(h.estimate)) estimate. \(h.why)",
                                                "\(h.ore.name) (\(h.ore.sign.lowercased())): \(clock(h.real)) su \(clock(h.estimate)) di stima. \(h.why)"))
                                } else {
                                    MCSlot(size: 40) { EmptyView() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var nextStyle: String {
        let won = WidgetTheme.won(gems: gems, mine: stats)
        guard let next = WidgetTheme.allCases.first(where: { !won.contains($0) }) else {
            return L("All the iPhone widget's styles are yours.", "Tutti gli stili del widget iPhone sono tuoi.")
        }
        return L("At your \(ordinal(next.blocks)) block: the \(next.title(.miniera)) style for the iPhone widget.",
                 "Al \(ordinal(next.blocks)) blocco: lo stile \(next.title(.miniera)) del widget iPhone.")
    }

    /// The buttons and, under them, the detail open: instant, no animation.
    private var details: some View {
        let open = hovered ?? pinned
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(MineDetail.allCases) { d in button(d, open: open == d) }
                Spacer(minLength: 0)
            }
            if let d = open {
                panel(d)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(MC.grey(0.70))
                    .bevel(MC.slotEdge, .white, 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in if !inside { hovered = nil } }
        .transaction { $0.animation = nil }
    }

    private func button(_ d: MineDetail, open: Bool) -> some View {
        Button { pinned = pinned == d ? nil : d } label: {
            MC.text(d.title, 15).mcLabel()
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(open ? MC.grey(0.55) : MC.button)
                .bevel(MC.grey(0.66), MC.grey(0.29), 2)
                .padding(2).background(pinned == d ? MC.today : Color.black)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { hovered = d } }
        .help(pinned == d ? L("Click: close", "Clic: chiudi") : L("Click: keep it open", "Clic: tienilo aperto"))
        .accessibilityLabel(d.title)
        .accessibilityHint(L("Opens on hover; a click keeps it open", "Si apre passandoci sopra; un clic lo tiene aperto"))
    }

    @ViewBuilder
    private func panel(_ d: MineDetail) -> some View {
        switch d {
        case .inventory: inventory
        case .guide: guide
        case .styles:
            PhoneThemeTiles(won: WidgetTheme.won(gems: gems, mine: stats).map(\.rawValue), mood: .miniera)
        }
    }

    /// Every ore found so far, as stacks, with what earns it.
    private var inventory: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .topLeading)], alignment: .leading, spacing: 10) {
                ForEach(Ore.allCases, id: \.self) { ore in
                    HStack(alignment: .top, spacing: 8) {
                        MCSlot(size: 44, count: stats.count(ore)) { OreIcon(ore: ore, size: 30) }
                        VStack(alignment: .leading, spacing: 1) {
                            MC.text(ore.name, 15, .medium).foregroundStyle(MC.ink)
                            MCSign(text: ore.sign)
                            MC.text(ore.rule, 13).foregroundStyle(MC.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            MC.text(L("The first five are good estimates, from diamond to coal; the other five are wrong, from least to worst. “Times” counts both ways: twice or half the estimate.",
                      "Le prime cinque sono stime buone, dal diamante al carbone; le altre cinque sbagliate, dalla meno grave alla peggiore. «Volte» vale nei due sensi: il doppio o la metà della stima."), 13)
                .foregroundStyle(MC.muted).fixedSize(horizontal: false, vertical: true)
            if !MineIcons.missing.isEmpty {
                let files = MineIcons.missing.joined(separator: ", ")
                MC.text(L("Minecraft icons missing from ~/.claude/task-eta/minerali: \(files). Until they're there, a coloured square stands in.",
                          "Icone di Minecraft che mancano in ~/.claude/task-eta/minerali: \(files). Finché mancano, al loro posto c'è un quadrato colorato."), 13)
                    .foregroundStyle(MC.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 14) {
            MineChain()
            MineScale()
            VStack(alignment: .leading, spacing: 6) {
                MC.rich(L("It measures how far you can **trust the estimate** Claude writes at the start of every reply (“about 10 min”). **It doesn't grade** you or Claude.",
                          "Misura quanto puoi **fidarti della stima** che Claude scrive all'inizio di ogni risposta («circa 10 min»). **Non dà un voto** a te né a Claude."), 14)
                MC.rich(L("Every task with an estimate is **a stroke of the pickaxe**: the closer the real time is to the estimate, the more precious your find. **From diamond to coal** are estimates you can plan around; **from cobweb to rotten flesh** the estimate was far off, too long or too short.",
                          "Ogni task con la stima è **un colpo di piccone**: più il tempo vero è vicino alla stima, più è prezioso quello che trovi. **Dal diamante al carbone** sono stime su cui puoi organizzarti; **dalla ragnatela alla carne marcia** la stima era lontana, troppo lunga o troppo corta."), 14)
                MC.rich(L("The goal: **9 diamonds make a block**, and **a week with 80% good estimates lights a Beacon**. Every week that makes it is one more beacon. No points to count.",
                          "Il fine: **9 diamanti fanno un blocco**, e **una settimana con l'80% di stime buone accende un Faro**. Ogni settimana riuscita è un faro in più. Niente punti da contare."), 14)
                MC.rich(L("Under the last 16 strokes you see **which way the estimates miss**: too short means tasks bigger than they looked, too long means simpler tasks.",
                          "Sotto gli ultimi 16 colpi c'è **da che parte sbagliano le stime**: troppo corte vuol dire task più grossi di come sembravano, troppo lunghe task più semplici."), 14)
            }
            .foregroundStyle(MC.ink).fixedSize(horizontal: false, vertical: true)
            howTo
        }
    }

    /// How a diamond is made: what to do so the estimate lands within 5%, with the user's own numbers.
    private var howTo: some View {
        let all = stats.hits
        let clean = MineStats.goodShare(all.filter(\.clean)), rough = MineStats.goodShare(all.filter { !$0.clean })
        let quick = all.filter { $0.kind == "quick" }
        let small = MineStats.goodShare(quick.filter { $0.tools <= 3 }), big = MineStats.goodShare(quick.filter { $0.tools > 3 })
        let miss = all.filter { !$0.ore.isGood }
        return VStack(alignment: .leading, spacing: 6) {
            MC.text(L("How to make a diamond", "Come si fa un diamante"), 16, .bold).foregroundStyle(MC.ink)
            MC.rich(L("A diamond is **the exact time, within 5%**. You can't force it: it comes when the prompt is clear and the job is the kind Claude said (quick, medium, long).",
                      "Il diamante è **il tempo esatto, entro il 5%**. Non si forza: arriva quando il prompt è chiaro e il lavoro è del tipo che Claude ha detto (quick, medium, long)."), 14)
            MC.rich(L("1. **Write it all in the first message.** If you add things halfway, the task stops, restarts and the estimate breaks.",
                      "1. **Scrivi tutto nel primo messaggio.** Se aggiungi cose a metà il task si ferma, riparte e la stima salta.")
                    + (clean.flatMap { c in rough.map { r in L(" In your strokes: a single turn and few tools, \(c)% good; the others \(r)%.",
                                                               " Nei tuoi colpi: un turno solo e pochi strumenti, buoni il \(c)%; gli altri il \(r)%.") } } ?? ""), 14)
            MC.rich(L("2. **A quick is one thing.** If it needs more than 3 tools, it's a medium job.",
                      "2. **Un quick è una cosa sola.** Se servono più di 3 strumenti, è un lavoro medio.")
                    + (small.flatMap { s in big.map { b in L(" Your quicks with 3 tools or fewer are \(s)% good, those with more \(b)%.",
                                                             " I tuoi quick con 3 strumenti o meno sono buoni il \(s)%, quelli con di più il \(b)%.") } } ?? ""), 14)
            MC.rich(L("3. **One piece at a time.** Big tasks overrun.", "3. **Un pezzo alla volta.** I task grossi sforano.")
                    + (miss.isEmpty ? "" : L(" Of your wrong estimates, \(miss.filter(\.slow).count) of \(miss.count) were too short.",
                                             " Delle tue stime sbagliate, \(miss.filter(\.slow).count) su \(miss.count) erano troppo corte.")), 14)
            MC.rich(L("4. **Let Claude finish.** Questions and messages halfway make the task longer: wait for the end, then send the rest.",
                      "4. **Lascia finire Claude.** Domande e messaggi a metà allungano il task: aspetta la fine, poi manda il resto."), 14)
            MC.rich(L("That's how the **diamonds** go up, then the **blocks**, and a week at 80% (with at least 20 strokes) lights **a Beacon**.",
                      "Così salgono i **diamanti**, poi i **blocchi**, e una settimana all'80% (con almeno 20 colpi) accende **il Faro**."), 14)
            MC.rich(L("Your level is **the pickaxe**: you start with wood; stone at the first Block of Diamond, iron at the third, gold at the first Beacon, diamond at the third. **Claude rates itself**: at the end of a reply it writes what it found, and when the next pickaxe is ready **it tells you**. You only take it if you answer “take the pickaxe”, or with the button here.",
                      "Il livello è **il piccone**: parti col legno; pietra al primo blocco di diamante, ferro al terzo, oro al primo Faro, diamante al terzo. **Claude si valuta da solo**: a fine risposta scrive cosa ha trovato, e quando il piccone dopo è pronto **te lo dice**. Si prende solo se rispondi «prendi il piccone», o col pulsante qui."), 14)
        }
        .foregroundStyle(MC.ink).fixedSize(horizontal: false, vertical: true)
    }
}

/// The game in one line: a task, the find, 9 diamonds, a block, the beacon lit.
struct MineChain: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            step(L("a task with an estimate", "un task con la stima")) {
                Image(systemName: "timer").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            }
            MCArrow().scaleEffect(0.7).padding(.top, 12)
            step(L("estimate within 5%: a diamond", "stima entro il 5%: un diamante")) { OreIcon(ore: .diamante, size: 28) }
            MCArrow().scaleEffect(0.7).padding(.top, 12)
            step(L("9 diamonds", "9 diamanti")) {
                VStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 1) { ForEach(0..<3, id: \.self) { _ in OreIcon(ore: .diamante, size: 10) } }
                    }
                }
            }
            MCArrow().scaleEffect(0.7).padding(.top, 12)
            step(L("1 block", "1 blocco")) { BlockCell(ore: .diamante, size: 28) }
            MCArrow().scaleEffect(0.7).padding(.top, 12)
            step(L("a week at 80%: a Beacon", "una settimana all'80%: il Faro")) {
                if let image = MineIcons.image(MineIcons.beacon) {
                    Image(nsImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 30, height: 30)
                } else {
                    BlockCell(ore: .diamante, size: 28)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func step<Icon: View>(_ caption: String, @ViewBuilder icon: () -> Icon) -> some View {
        let drawn = icon()
        return VStack(spacing: 5) {
            MCSlot(size: 44) { drawn }
            MC.text(caption, 12).foregroundStyle(MC.ink).multilineTextAlignment(.center)
                .frame(width: 92).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The ten finds in order, best to worst, with when each comes: five good, then five bad.
struct MineScale: View {
    private var marks: [String] { ["5%", "25%", L("range", "forchetta"), "×\(Loc.decimal(1.5))", "×2", "×3", "×5", "×7", "×10", L("over", "oltre")] }

    var body: some View {
        let ores = Ore.allCases
        let m = marks
        HStack(alignment: .top, spacing: 14) {
            group(L("Good estimates", "Stime buone"), Array(ores.prefix(5)), Array(m.prefix(5)), good: true)
            group(L("Wrong estimates", "Stime sbagliate"), Array(ores.suffix(5)), Array(m.suffix(5)), good: false)
        }
        .accessibilityElement(children: .combine)
    }

    private func group(_ title: String, _ ores: [Ore], _ marks: [String], good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MC.text(title, 13, .bold).foregroundStyle(good ? Color(red: 0.12, green: 0.42, blue: 0.20) : Color(red: 0.55, green: 0.13, blue: 0.13))
            HStack(spacing: 0) {
                ForEach(Array(zip(ores, marks)), id: \.0) { ore, mark in
                    VStack(spacing: 3) {
                        MCSlot(size: 38) { OreIcon(ore: ore, size: 26) }.help("\(ore.name): \(ore.rule)")
                        MC.text(mark, 11).foregroundStyle(MC.ink).lineLimit(1).minimumScaleFactor(0.8)
                        MCSign(text: ore.sign, size: 10, lines: 2)
                    }
                    .frame(width: 64)
                }
            }
        }
    }
}

/// Il Faro, Minecraft's beacon, on its pyramid seen from the side: three levels of 3, 5 and
/// 7 blocks, 15 in all. The slider picks what the pyramid is built of (diamond, emerald, gold, iron
/// or coal), and its blocks are the minerals of that kind found so far, on one scale for all five
/// (100 coal and 20 diamonds: more blocks on the coal side than the diamond one). The light
/// is this week: it goes on at 80% good with at least 20 strokes, and every week that makes it is
/// one more beacon. Nothing moves.
struct MineBeacon: View {
    let stats: MineStats
    @State private var base: Ore = MineBeacon.debugBase ?? .diamante
    /// For a snapshot: TASKETA_DEBUG_DASH=faro-oro (or faro-ferro…) starts the slider there.
    static var debugBase: Ore? { DashDebug.flags.lazy.compactMap { $0.hasPrefix("faro-") ? Ore(rawValue: String($0.dropFirst(5))) : nil }.first }
    /// The levels, top to bottom.
    static let rows = [3, 5, 7]
    static var size: Int { rows.reduce(0, +) }
    private let cell: CGFloat = 26

    /// Blocks in each level, top to bottom, the pyramid laid from the bottom row.
    static func fill(_ placed: Int) -> [Int] {
        var left = max(0, placed)
        return rows.reversed().map { row -> Int in
            let n = min(row, left)
            left -= n
            return n
        }.reversed()
    }

    /// «1 colpo», «20 colpi».
    static func strokes(_ n: Int) -> String { L(n == 1 ? "1 stroke" : "\(n) strokes", n == 1 ? "1 colpo" : "\(n) colpi") }

    /// The pyramids of a pile, 9 minerals a block as on the crafting table: the ones finished, and
    /// the blocks of the one being built. A fixed measure, so the pyramid never stops: a finished one
    /// goes behind, in perspective, and a new one starts in front.
    static func pyramids(_ count: Int) -> (finished: Int, building: Int) {
        let blocks = max(0, count) / MineStats.perBlock
        return (blocks / size, blocks % size)
    }

    /// How many finished pyramids are drawn behind: the newest nearest, the rest as a number.
    static let behindShown = 3

    var body: some View {
        let week = stats.thisWeek
        let lit = week.lit
        // TASKETA_DEBUG_DASH=faro-x10: ten times the pile, to see the finished pyramids behind in a snapshot.
        let have = stats.count(base) * (DashDebug.flags.contains("faro-x10") ? 10 : 1)
        let piles = MineBeacon.pyramids(have)
        let blocks = have / MineStats.perBlock
        let pct = Int((week.share * 100).rounded(.down))   // 79.5% must not read «80%» while the beacon is off
        VStack(spacing: 10) {
            MC.text(L("Beacon", "Il Faro"), 18, .medium).foregroundStyle(MC.ink)
            MCSlider(options: Ore.beaconBases, selection: $base)
            MC.rich("**\(base.pile(have))**: " + L(blocks == 1 ? "1 block" : "\(blocks) blocks", blocks == 1 ? "1 blocco" : "\(blocks) blocchi")
                    + (piles.finished == 0 ? "" : piles.finished == 1 ? L(", 1 finished pyramid", ", 1 piramide finita")
                       : L(", \(piles.finished) finished pyramids", ", \(piles.finished) piramidi finite")), 14)
                .foregroundStyle(MC.ink).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            // The finished pyramids far behind, on the horizon over the one being built: the newest
            // nearest and biggest, then smaller and paler; past three, a number.
            if piles.finished > 0 {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<min(piles.finished, MineBeacon.behindShown), id: \.self) { k in
                        pyramid(placed: MineBeacon.size, size: cell * (0.42 - 0.08 * CGFloat(k)))
                            .opacity(0.9 - 0.2 * Double(k))
                    }
                    if piles.finished > MineBeacon.behindShown {
                        MC.text("+\(piles.finished - MineBeacon.behindShown)", 13, .medium).foregroundStyle(MC.muted)
                    }
                }
            }
            VStack(spacing: 0) {
                light(lit)
                beaconBlock(lit)
                pyramid(placed: piles.building, size: cell)
            }
            .help(L("9 items make a block, as on the crafting table, and 15 blocks a pyramid. A finished pyramid moves to the back and a new one starts in front.",
                    "9 minerali fanno un blocco, come sul banco da lavoro, e 15 blocchi una piramide. Una piramide finita va dietro e davanti ne parte una nuova."))
            MC.text(L("A block every 9 items, a pyramid every 15 blocks.", "Un blocco ogni 9 minerali, una piramide ogni 15 blocchi."), 12).foregroundStyle(MC.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            MC.rich(beaconLine(week, lit: lit, pct: pct), 14)
                .foregroundStyle(MC.ink).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                MC.text(L(stats.beacons == 1 ? "1 beacon lit" : "\(stats.beacons) beacons lit",
                          stats.beacons == 1 ? "1 faro acceso" : "\(stats.beacons) fari accesi"), 14, .medium).foregroundStyle(MC.ink)
                ForEach(0..<min(stats.beacons, 8), id: \.self) { _ in
                    if let image = MineIcons.image(MineIcons.beacon) {
                        Image(nsImage: image).interpolation(.none).resizable().frame(width: 16, height: 16)
                    }
                }
            }
            .help(L("A week, Monday to Sunday, with 80% good estimates (diamond to coal) and at least 20 strokes is one more beacon.",
                    "Una settimana da lunedì a domenica con l'80% di stime buone (dal diamante al carbone) e almeno 20 colpi è un faro in più."))
        }
        .accessibilityElement(children: .combine)
    }

    /// This week against the beacon's 80%.
    private func beaconLine(_ week: MineStats.Week, lit: Bool, pct: Int) -> String {
        let strokes = MineBeacon.strokes(week.strokes)
        if week.strokes == 0 {
            return L("No strokes yet this week: the beacon lights at **80% good estimates** (diamond to coal).",
                     "Questa settimana nessun colpo ancora: il faro si accende con **l'80% di stime buone** (dal diamante al carbone).")
        }
        if lit {
            return L("**Lit**: this week \(pct)% good estimates (diamond to coal) out of \(strokes).",
                     "**Acceso**: questa settimana \(pct)% di stime buone (dal diamante al carbone) su \(strokes).")
        }
        return L("This week, good estimates (diamond to coal) are at **\(pct)%** out of \(strokes); the beacon lights at **80%**",
                 "Questa settimana stime buone (dal diamante al carbone) al **\(pct)%** su \(strokes); il faro si accende all'**80%**")
            + (week.strokes < MineStats.beaconStrokes
               ? L(", with at least \(MineStats.beaconStrokes) strokes.", ", con almeno \(MineStats.beaconStrokes) colpi.") : ".")
    }

    /// The light from the beacon up, white in a pale cyan: there only once it is lit.
    private func light(_ lit: Bool) -> some View {
        ZStack {
            if lit {
                Rectangle().fill(Color(red: 0.72, green: 0.94, blue: 1.0).opacity(0.6)).frame(width: cell * 0.9)
                Rectangle().fill(Color.white.opacity(0.95)).frame(width: cell * 0.36)
            }
        }
        .frame(height: lit ? 70 : 18)   // off, only a little room above the beacon
    }

    @ViewBuilder
    private func beaconBlock(_ lit: Bool) -> some View {
        if let image = MineIcons.image(MineIcons.beacon) {
            Image(nsImage: image).interpolation(.none).resizable().scaledToFit().frame(width: cell, height: cell)
                .saturation(lit ? 1 : 0.15).brightness(lit ? 0 : -0.3)   // off: grey and dark, lit: its own cyan
        } else {
            Rectangle().fill(lit ? Color(red: 0.72, green: 0.94, blue: 1.0) : MC.grey(0.42))
                .overlay(Rectangle().strokeBorder(lit ? Color(red: 0.2, green: 0.6, blue: 0.7) : MC.slotEdge, lineWidth: 2))
                .overlay(Rectangle().fill(lit ? Color.white : MC.grey(0.3)).frame(width: cell * 0.35, height: cell * 0.35))
                .frame(width: cell, height: cell)
        }
    }

    /// Three levels of 3, 5 and 7 blocks, laid from the bottom, the empty ones as dim slots.
    private func pyramid(placed: Int, size: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(zip(MineBeacon.rows, MineBeacon.fill(placed)).enumerated()), id: \.offset) { _, level in
                HStack(spacing: 0) {
                    ForEach(0..<level.0, id: \.self) { i in
                        if i < level.1 { BlockCell(ore: base, size: size) } else { emptyCell(size) }
                    }
                }
            }
        }
    }

    private func emptyCell(_ size: CGFloat) -> some View {
        MC.slot.opacity(0.45).frame(width: size, height: size).bevel(MC.grey(0.45), MC.grey(0.85), 1)
    }
}

/// One of Minecraft's icons by file name, or nothing while it is missing.
struct MineIconImage: View {
    let file: String
    var size: CGFloat = 28

    var body: some View {
        if let image = MineIcons.image(file) {
            Image(nsImage: image).interpolation(.none).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// A block of 9 of a mineral: Minecraft's block when it is in the folder, else a full square of its colour.
struct BlockCell: View {
    let ore: Ore
    var size: CGFloat = 26

    var body: some View {
        if let image = MineIcons.image(ore.blockFile) {
            Image(nsImage: image).interpolation(.none).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Rectangle().fill(Color(nsColor: ore.tones.light))
                .overlay(Rectangle().strokeBorder(Color(nsColor: ore.tones.deep), lineWidth: 2))
                .frame(width: size, height: size)
        }
    }
}

/// A slider in Minecraft's look: the minerals as stops on a sunk track, the knob a raised button
/// under the one picked. Drag along it or click a stop.
struct MCSlider: View {
    let options: [Ore]
    @Binding var selection: Ore
    private let stop: CGFloat = 44

    var body: some View {
        let i = CGFloat(options.firstIndex(of: selection) ?? 0)
        ZStack(alignment: .topLeading) {
            MC.slot.bevel(MC.slotEdge, .white, 2)   // a slot's grey, so the coal shows
            MC.button.frame(width: stop - 4, height: stop - 4).bevel(MC.grey(0.66), MC.grey(0.29), 2)
                .offset(x: i * stop + 2, y: 2)
            HStack(spacing: 0) {
                ForEach(options, id: \.self) { o in
                    OreIcon(ore: o, size: 26).frame(width: stop, height: stop).opacity(o == selection ? 1 : 0.7)
                        .help(L("Pyramid \(o.ofName)", "Piramide \(o.ofName)"))
                }
            }
        }
        .frame(width: stop * CGFloat(options.count), height: stop)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            let k = min(options.count - 1, max(0, Int(v.location.x / stop)))
            if options[k] != selection { selection = options[k] }
        })
        .accessibilityElement()
        .accessibilityLabel(L("Beacon mineral", "Minerale del faro"))
        .accessibilityValue(selection.name)
        .accessibilityAdjustableAction { direction in
            let k = options.firstIndex(of: selection) ?? 0
            switch direction {
            case .increment: selection = options[min(options.count - 1, k + 1)]
            case .decrement: selection = options[max(0, k - 1)]
            @unknown default: break
            }
        }
    }
}

/// The mine in a widget one row high: the blocks and the diamonds toward the next.
struct MinieraStrip: View {
    let stats: MineStats

    var body: some View {
        HStack(spacing: 12) {
            MCSlot(size: 40, count: stats.blocks) { OreIcon(ore: .diamante, file: MineIcons.block, size: 28) }
            VStack(alignment: .leading, spacing: 2) {
                MC.text(L(stats.blocks == 1 ? "1 Block of Diamond" : "\(stats.blocks) Blocks of Diamond",
                          stats.blocks == 1 ? "1 blocco di diamante" : "\(stats.blocks) blocchi di diamante"), 16, .medium).foregroundStyle(MC.ink)
                MC.text(L("\(stats.toNext) of 9 toward the \(ordinal(stats.blocks + 1)) block", "\(stats.toNext) su 9 verso il \(ordinal(stats.blocks + 1))"), 13)
                    .foregroundStyle(MC.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .mcPanel()
    }
}

enum MineTest {
    static func failures() -> [String] {
        var out: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { out.append(what) } }
        let range = (low: 200.0, high: 450.0)
        func ore(_ real: Double, est: Double = 300) -> Ore { Ore(real: real, estimate: est, range: range) }
        check(ore(300) == .diamante && ore(315) == .diamante && ore(285) == .diamante && ore(324) == .smeraldo, "diamond within 5%")
        check(Ore(real: 34, estimate: 24, range: nil) != .diamante, "no 10 second floor")
        check(ore(360) == .smeraldo && ore(245) == .smeraldo, "emerald within 25%")
        check(ore(420) == .oro && ore(210) == .oro, "gold inside the range")
        check(Ore(real: 420, estimate: 300, range: (250, 400)) == .ferro, "iron outside the range, within 1.5 times")
        check(ore(500) == .carbone && ore(160) == .carbone, "coal within twice")
        check(ore(800) == .ragnatela && ore(110) == .ragnatela, "cobweb up to 3 times")
        check(ore(1400) == .patata && ore(70) == .patata, "potato up to 5 times")
        check(ore(2000) == .polvere && ore(50) == .polvere, "gunpowder up to 7 times")
        check(ore(2900) == .occhio && ore(31) == .occhio, "spider eye up to 10 times")
        check(ore(3100) == .marcia && ore(25) == .marcia, "rotten flesh past 10 times")
        check(Ore.allCases.filter(\.isGood).count == 5 && !Ore.ragnatela.isGood && Ore.carbone.isGood, "five good, five bad")
        check(MineBeacon.fill(8) == [0, 1, 7] && MineBeacon.fill(15) == [3, 5, 7] && MineBeacon.fill(40) == [3, 5, 7], "the pyramid from the bottom")
        check(MineBeacon.pyramids(86) == (0, 9) && MineBeacon.pyramids(135) == (1, 0) && MineBeacon.pyramids(300) == (2, 3), "9 a block, 15 a pyramid")
        check(MineBeacon.pyramids(100).building > MineBeacon.pyramids(20).building, "100 coal, 20 diamonds: more coal blocks")
        check(MineBeacon.pyramids(0) == (0, 0) && MineBeacon.pyramids(8) == (0, 0) && MineBeacon.pyramids(9) == (0, 1), "a block at 9")
        Loc.testing(.it) {
            check(Ore.oro.pile(81) == "81 lingotti d'oro" && Ore.diamante.pile(1) == "1 diamante" && Ore.carbone.pile(0) == "0 carboni", "piles in words")
        }
        Loc.testing(.en) {
            check(Ore.oro.pile(81) == "81 gold ingots" && Ore.diamante.pile(1) == "1 diamond" && Ore.carbone.pile(0) == "0 coal"
                  && Ore.oro.ofName == "of gold" && Ore.ragnatela.sign == "Wrong", "piles and signs in English")
        }
        let week = MineStats.Week(start: Date(), strokes: 20, good: 16)
        check(week.lit && !MineStats.Week(start: Date(), strokes: 19, good: 19).lit && !MineStats.Week(start: Date(), strokes: 30, good: 23).lit, "a beacon at 80% with 20 strokes")
        let s = MineStats.sample()
        check(s.diamonds == 12 && s.blocks == 1 && s.toNext == 3, "blocks of 9: \(s.diamonds) \(s.blocks) \(s.toNext)")
        check(s.recent.count == 16, "the last 16")
        check(s.weeks.reduce(0) { $0 + $1.strokes } == s.hits.count, "weeks hold every stroke")
        Loc.testing(.it) {
            check(MineStats().advice.hasPrefix("Nessun colpo"), "advice when empty")
            check(s.advice.contains("troppo corte"), "advice on the misses: \(s.advice)")
            check(ordinal(1) == "primo" && ordinal(10) == "decimo" && ordinal(12) == "12°", "ordinals")
        }
        Loc.testing(.en) {
            check(MineStats().advice.hasPrefix("No strokes yet") && s.advice.contains("too short"), "advice in English: \(s.advice)")
            check(ordinal(1) == "first" && ordinal(10) == "tenth" && ordinal(12) == "12th" && ordinal(21) == "21st" && ordinal(113) == "113th",
                  "ordinals in English")
        }
        func hit(_ real: Double, kind: String = "quick", segments: Int = 1, tools: Int = 2) -> MineStats.Hit {
            MineStats.Hit(start: 0, real: real, estimate: 300, ore: ore(real), kind: kind, segments: segments, tools: tools)
        }
        check(hit(300).clean && !hit(300, segments: 2).clean && !hit(300, tools: 4).clean && hit(300, kind: "medium", tools: 12).clean, "silk touch")
        Loc.testing(.it) {
            check(hit(1600, segments: 3).why.hasPrefix("Si è fermato e ripartito 2 volte") && hit(1600, tools: 6).why.hasPrefix("Era un quick e ha usato 6"), "why: turns, tools")
            check(hit(800).why.hasPrefix("2,7 volte la stima") && hit(300).why.hasPrefix("Stima centrata"), "why: times, centred")
        }
        Loc.testing(.en) {
            check(hit(1600, segments: 3).why.hasPrefix("It stopped and restarted 2 times") && hit(800).why.hasPrefix("2.7 times the estimate")
                  && hit(300).why.hasPrefix("Spot on"), "why in English")
        }
        check(s.vein == 0 && s.bestVein >= 2, "the vein: \(s.vein) \(s.bestVein)")
        for lang in Lang.allCases {
            Loc.testing(lang) { check(Ore.allCases.map(\.sign).count == Set(Ore.allCases.map(\.sign)).count, "a sign for each find") }
        }
        Loc.testing(.it) {
            check(Pickaxe.legno.next == .pietra && Pickaxe.diamante.next == nil && Pickaxe.oro.needText == "1 Faro acceso", "pickaxes")
        }
        Loc.testing(.en) {
            check(Pickaxe.oro.needText == "1 Beacon lit" && Pickaxe.pietra.name == "Stone Pickaxe"
                  && Pickaxe.ferro.needText == "3 Blocks of Diamond", "pickaxes in English")
        }
        check(Pickaxe.pietra.earned(s) && !Pickaxe.ferro.earned(s), "stone with 1 block, not iron")
        check(WidgetTheme.allCases.map(\.blocks) == [1, 5, 10], "styles by blocks")
        return out
    }
}
