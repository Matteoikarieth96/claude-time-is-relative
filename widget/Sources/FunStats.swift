import SwiftUI

// "Statistiche inutili": true, and good for a laugh. Worked out on this Mac from the index and
// shown only here: the prompts never leave this Mac. Which ones show, the
// multiplier of the hours without AI and the words to count are the user's, from edit mode, kept as
// JSON in UserDefaults under "dashboardFunStats".

enum FunStat: String, CaseIterable, Identifiable {
    case doomscroll, withoutAI, useless, night, tool, papyrus, opener, interrupted, language, waited, shortest, agents, marathon

    var id: String { rawValue }

    /// Its name in the editor.
    var title: String {
        switch self {
        case .doomscroll: return L("Doomscrolling avoided (mini golf)", "Doomscrolling evitato (minigolf)")
        case .withoutAI: return L("Hours without AI (rough guess)", "Ore senza AI (a occhio)")
        case .useless: return L("Useless prompts", "Prompt inutili")
        case .night: return L("Night-time prompts", "Prompt di notte")
        case .tool: return L("Claude's favourite tool", "Lo strumento preferito di Claude")
        case .papyrus: return L("Prompts longer than a tweet", "Prompt più lunghi di un tweet")
        case .opener: return L("“Open the file for me”", "«Aprimi il file»")
        case .interrupted: return L("Times you stopped it", "Le volte che l'hai interrotto")
        case .language: return L("The most edited file type", "Il tipo di file più toccato")
        case .waited: return L("Claude waited for you", "Claude ti ha aspettato")
        case .shortest: return L("The shortest prompt", "Il prompt più corto")
        case .agents: return L("Subagents launched", "Subagenti lanciati")
        case .marathon: return L("The longest task", "Il task più lungo")
        }
    }
}

struct FunSettings: Equatable {
    /// The statistics on, in the order they show.
    var stats: [FunStat]
    /// Hours without AI = Claude's working hours × this: a guess, and said as one.
    var multiplier: Double
    /// The words you picked; nil until you change them: then the language's own, and only yours are saved.
    var customWords: [String]? = nil
    /// Words counted in the prompts (whole words, any case).
    var words: [String] {
        get { customWords ?? FunSettings.standardWords }
        set { customWords = newValue }
    }

    static var standardWords: [String] {
        Loc.lang == .it ? ["okei", "dai", "grazie", "cazzo", "per favore"] : ["ok", "go on", "thanks", "damn", "please"]
    }

    static let standard = FunSettings(stats: [.doomscroll, .withoutAI, .useless, .night, .tool, .papyrus, .opener,
                                              .interrupted, .language], multiplier: 4)

    private struct Saved: Codable {
        var v: Int
        var stats: [String]
        var multiplier: Double?
        var words: [String]?
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(Saved(v: 1, stats: stats.map(\.rawValue), multiplier: multiplier, words: customWords))
    }

    /// Read leniently: statistics this version does not know are left out.
    static func decoded(_ data: Data) -> FunSettings? {
        guard let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        var seen = Set<FunStat>()
        let stats = saved.stats.compactMap(FunStat.init(rawValue:)).filter { seen.insert($0).inserted }
        let multiplier = saved.multiplier.flatMap { $0.isFinite ? min(20, max(1, $0)) : nil } ?? standard.multiplier
        return FunSettings(stats: stats, multiplier: multiplier, customWords: saved.words)
    }
}

final class FunSettingsStore: ObservableObject {
    static let shared = FunSettingsStore()
    static let defaultsKey = "dashboardFunStats"

    @Published var settings: FunSettings {
        didSet {
            guard settings != oldValue, let data = settings.encoded() else { return }
            UserDefaults.standard.set(data, forKey: FunSettingsStore.defaultsKey)
        }
    }

    init() {
        settings = UserDefaults.standard.data(forKey: FunSettingsStore.defaultsKey).flatMap(FunSettings.decoded) ?? .standard
    }

    func setOn(_ stat: FunStat, _ on: Bool) {
        if on, !settings.stats.contains(stat) { settings.stats.append(stat) }
        if !on { settings.stats.removeAll { $0 == stat } }
    }

    func addWord(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !w.isEmpty, w.count <= 40, !settings.words.contains(w) else { return }
        settings.words.append(w)
    }

    func reset() {
        settings = .standard
        UserDefaults.standard.removeObject(forKey: FunSettingsStore.defaultsKey)
    }
}

/// The facts, each a figure and the rest of its sentence.
struct FunFacts {
    struct Fact: Identifiable {
        let id: FunStat
        let figure: String
        let text: String
    }

    var facts: [Fact] = []
    var words: [(word: String, count: Int)] = []

    /// Words that, alone, say nothing new to Claude ("okei", "vai", "?"), typos included.
    static let filler: Set<String> = [
        "ok", "okay", "okei", "oeki", "okie", "oki", "okk", "k", "si", "sì", "yes", "vai", "dai", "daje", "continua",
        "procedi", "fatto", "done", "go", "grazie", "perfetto", "bene", "pure", "allora", "quindi", "e", "ora", "adesso",
        "fai", "fallo", "tu", "esatto", "va", "andiamo", "top", "nice", "ottimo", "super", "ancora", "avanti", "certo",
        "meglio", "eccolo", "eccoli",
    ]

    static func isUseless(_ prompt: String) -> Bool {
        let s = prompt.lowercased().trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }
        if s.allSatisfy({ "?!. ".contains($0) }) { return true }
        let words = s.split { !$0.isLetter }.map(String.init)
        return !words.isEmpty && words.count <= 3 && s.count <= 25 && words.allSatisfy { filler.contains($0) }
    }

    /// Whole word or phrase, any case: "dai" is not in "daily".
    static func contains(_ prompt: String, _ word: String) -> Bool {
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])"
        return prompt.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    init(_ tasks: [PastTask], settings: FunSettings, hidePrompts: Bool) {
        let n = tasks.count
        let calendar = Calendar.current
        for stat in settings.stats {
            if let fact = FunFacts.fact(stat, tasks, n: n, settings: settings, hidePrompts: hidePrompts, calendar: calendar) {
                facts.append(fact)
            }
        }
        words = settings.words.map { w in (w, tasks.filter { FunFacts.contains($0.prompt, w) }.count) }
    }

    private static func fact(_ stat: FunStat, _ tasks: [PastTask], n: Int, settings: FunSettings, hidePrompts: Bool,
                             calendar: Calendar) -> Fact? {
        switch stat {
        case .doomscroll:
            // The minutes in the mini golf while Claude worked, instead of on the socials: the
            // games of the period (from its first task on).
            let from = tasks.map(\.start).min() ?? Date().timeIntervalSince1970
            let games = GolfStats.load().games.filter { $0.start >= from }
            let seconds = games.reduce(0) { $0 + $1.seconds }
            let played = grouped(games.count)
            return games.isEmpty
                ? Fact(id: stat, figure: "0 min",
                       text: L("of mini golf while Claude worked. Social media says thanks: it had you all to itself.",
                               "di minigolf mentre Claude lavorava. I social ringraziano: ti hanno avuto tutto per loro."))
                : Fact(id: stat, figure: duration(seconds),
                       text: L("of mini golf instead of social media, in \(played) game\(games.count == 1 ? "" : "s"). Doomscrolling avoided.",
                               "a minigolf invece che sui social, in \(played) \(games.count == 1 ? "partita" : "partite"). Doomscrolling evitato."))
        case .withoutAI:
            let hours = tasks.reduce(0) { $0 + $1.active } / 3600 * settings.multiplier
            let days = safeInt((hours / 8).rounded())
            let m = times(settings.multiplier)
            return Fact(id: stat, figure: "≈\(grouped(safeInt(hours.rounded()))) h",
                        text: L("by hand, without Claude: its working time ×\(m), roughly. \(days == 1 ? "One 8\u{2011}hour day" : "\(grouped(days)) 8\u{2011}hour days").",
                                "a mano, senza Claude: il suo tempo di lavoro ×\(m), a occhio. \(days == 1 ? "Una giornata" : "\(grouped(days)) giornate") da 8 ore."))
        case .useless:
            let count = tasks.filter { isUseless($0.prompt) }.count
            guard n > 0 else { return nil }
            return count == 0
                ? Fact(id: stat, figure: "0", text: L("prompts of filler words only. A shining example.",
                                                      "prompt di sole parole di riempimento. Un esempio per tutti."))
                : Fact(id: stat, figure: grouped(count),
                       text: L("\(count == 1 ? "prompt was" : "prompts were") just “ok”, “go” or “?”: \(percent(count, n)) of what you wrote to it.",
                               "prompt erano solo «okei», «vai» o «?»: il \(percent(count, n)) di quello che gli hai scritto."))
        case .night:
            let night = tasks.filter { calendar.component(.hour, from: Date(timeIntervalSince1970: $0.start)) < 6 }
            guard !night.isEmpty else {
                return Fact(id: stat, figure: "0", text: L("prompts between midnight and 6 am. Sleeping like a baby, lucky you.",
                                                           "prompt tra mezzanotte e le 6. Dormi, beato te."))
            }
            let latest = night.map { Date(timeIntervalSince1970: $0.start) }
                .max { calendar.dateComponents([.hour, .minute], from: $0).minuteOfDay < calendar.dateComponents([.hour, .minute], from: $1).minuteOfDay }
            let at = latest.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
            return Fact(id: stat, figure: grouped(night.count),
                        text: L("prompt\(night.count == 1 ? "" : "s") between midnight and 6 am, the latest at \(at). Bed can wait.",
                                "prompt tra mezzanotte e le 6, il più tardo alle \(at). Il letto può aspettare."))
        case .tool:
            var total: [String: Int] = [:]
            for t in tasks { for (k, v) in t.toolNames { total[toolName(k), default: 0] += v } }
            let top = total.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            guard let first = top.first else { return nil }
            let second = top.dropFirst().first.map { next -> String in
                let chased = grouped(next.value)
                return L(" \(next.key) chases it with \(chased).", " \(next.key) lo insegue a \(chased).")
            } ?? ""
            let uses = grouped(first.value)
            return Fact(id: stat, figure: first.key,
                        text: L("\(uses) time\(first.value == 1 ? "" : "s"): Claude's favourite tool.\(second)",
                                "\(uses) volte: lo strumento preferito di Claude.\(second)"))
        case .papyrus:
            // The index keeps the first 300 characters: a prompt past 280 is longer than a tweet.
            let long = tasks.filter { $0.prompt.count > 280 }.count
            return Fact(id: stat, figure: grouped(long),
                        text: long == 0 ? L("prompts longer than a tweet. Master of brevity.", "prompt più lunghi di un tweet. Sintesi da maestro.")
                            : L("\(long == 1 ? "prompt" : "prompts") longer than a tweet. A tweet isn't enough for you.",
                                "prompt più lunghi di un tweet. Un tweet non ti basta."))
        case .opener:
            // The verb in Italian or in English, whatever the language shown.
            let count = tasks.filter { $0.prompt.range(of: "(?<![\\p{L}])((ri)?apri(mi|li|lo|la|melo|mela|meli)?|(re)?open)(?![\\p{L}])",
                                                       options: [.regularExpression, .caseInsensitive]) != nil }.count
            return Fact(id: stat, figure: grouped(count),
                        text: count == 0 ? L("times you asked it to open something for you. You open your own files.",
                                             "volte gli hai chiesto di aprirti qualcosa. I file li apri da solo.")
                                         : L("\(count == 1 ? "time" : "times") you asked it to open something for you. The priciest doorman in the world.",
                                             "volte gli hai chiesto di aprirti qualcosa. Il portiere più caro del mondo."))
        case .interrupted:
            let count = tasks.filter(\.interrupted).count
            return Fact(id: stat, figure: grouped(count),
                        text: count == 0 ? L("times you stopped it halfway. The patience of a saint.", "volte l'hai fermato a metà. Pazienza da santo.")
                            : L("\(count == 1 ? "time" : "times") you stopped it halfway. It holds no grudge.",
                                "volte l'hai fermato a metà. Non porta rancore."))
        case .language:
            var total: [String: Int] = [:]
            for t in tasks { for (k, v) in t.editExts { total[k.lowercased(), default: 0] += v } }
            guard let top = total.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) else { return nil }
            let changes = grouped(top.value), aside = quip(top.key)
            return Fact(id: stat, figure: ".\(top.key)",
                        text: L("the file type it changes most often: \(changes) time\(top.value == 1 ? "" : "s"). \(aside)",
                                "il tipo di file che cambia più spesso: \(changes) volte. \(aside)"))
        case .waited:
            let wait = tasks.reduce(0) { $0 + $1.wait }
            return Fact(id: stat, figure: duration(wait), text: L("waiting for your answers mid-task. Endless patience, and free.",
                                                                  "ad aspettare le tue risposte a metà lavoro. Pazienza infinita, e gratis."))
        case .shortest:
            guard let short = tasks.map(\.prompt).filter({ !$0.isEmpty }).min(by: { $0.count < $1.count }) else { return nil }
            return hidePrompts
                ? Fact(id: stat, figure: "\(short.count)",
                       text: L("character\(short.count == 1 ? "" : "s"): the shortest prompt (the text is hidden, as per Settings).",
                               "caratteri: il prompt più corto (il testo è nascosto, come da impostazioni)."))
                : Fact(id: stat, figure: L("“\(short)”", "«\(short)»"),
                       text: L("the shortest prompt: \(short.count) character\(short.count == 1 ? "" : "s"). It did the job.",
                               "il prompt più corto: \(short.count) \(short.count == 1 ? "carattere" : "caratteri"). È bastato."))
        case .agents:
            let count = tasks.reduce(0) { $0 + $1.agents }
            return Fact(id: stat, figure: grouped(count),
                        text: count == 0 ? L("subagents launched. Claude does it all by itself.", "subagenti lanciati. Claude fa tutto da solo.")
                            : L("\(count == 1 ? "subagent" : "subagents") launched: a small army at your command.",
                                "subagenti lanciati: un piccolo esercito ai tuoi ordini."))
        case .marathon:
            guard let longest = tasks.max(by: { $0.real < $1.real }) else { return nil }
            return Fact(id: stat, figure: duration(longest.real), text: L("the longest task. A marathon, not a sprint.",
                                                                          "il task più lungo. Maratona, non sprint."))
        }
    }

    /// "4", "4.5" or "4,5": the multiplier as people write it.
    static func times(_ m: Double) -> String { decimal(m, m.rounded() == m ? 0 : 1) }

    /// "mcp__claude-in-chrome__computer" is "computer".
    private static func toolName(_ name: String) -> String {
        name.components(separatedBy: "__").last.flatMap { $0.isEmpty ? nil : $0 } ?? name
    }

    private static func quip(_ ext: String) -> String {
        switch ext {
        case "md", "txt": return L("More prose than code.", "Più prosa che codice.")
        case "html", "css": return L("The web doesn't build itself.", "Il web non si fa da solo.")
        case "swift": return L("All for the Mac.", "Tutto per il Mac.")
        case "py": return L("Snakes everywhere.", "Serpenti ovunque.")
        case "js", "ts", "jsx", "tsx": return L("Semicolons, or maybe not.", "Punto e virgola, o forse no.")
        case "json", "yml", "yaml": return L("Config without end.", "Configurazioni a non finire.")
        default: return ""
        }
    }

    private static func grouped(_ n: Int) -> String { Loc.integer(n) }

    private static func percent(_ part: Int, _ whole: Int) -> String {
        let p = Double(part) / Double(max(1, whole)) * 100
        return p < 10 ? "\(decimal(p))%" : "\(safeInt(p.rounded()))%"
    }

    /// "3 h 12 min", "45 min", "40 s".
    private static func duration(_ seconds: Double) -> String {
        let s = max(0, safeInt(seconds.rounded()))
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min" }
        return s % 3600 / 60 == 0 ? "\(s / 3600) h" : "\(s / 3600) h \(s % 3600 / 60) min"
    }
}

private extension DateComponents {
    var minuteOfDay: Int { (hour ?? 0) * 60 + (minute ?? 0) }
}

// MARK: - the widget

struct FunStatsWidget: View {
    @ObservedObject var model: DashboardModel
    let size: WidgetSize
    @ObservedObject private var store = FunSettingsStore.shared

    var body: some View {
        let facts = FunFacts(model.inRange, settings: store.settings, hidePrompts: UserDefaults.standard.bool(forKey: "hidePrompts"))
        let columns = max(2, min(4, size.width))
        WidgetChrome(role: .plate, title: L("Useless stats", "Statistiche inutili"),
                     subtitle: L("true, but they won't change your life; \(model.periodText)",
                                 "vere, ma non ti cambieranno la vita; \(model.periodText)")) {
            VStack(alignment: .leading, spacing: 12) {
                if facts.facts.isEmpty && facts.words.isEmpty {
                    Text(L("All off. Turn them back on in “Edit”: they're useless, but they care.",
                           "Tutte spente. In «Modifica» puoi riaccenderle: sono inutili, ma ci tengono."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .topLeading), count: columns),
                          alignment: .leading, spacing: 12) {
                    ForEach(facts.facts.prefix(columns * 2)) { fact in
                        (Text(fact.figure).font(.timer(17, .bold)) + Text(" " + fact.text).font(.system(size: 12)).foregroundStyle(Color.secondary))
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                if !facts.words.isEmpty {
                    WordCounts(words: facts.words)
                }
            }
        }
    }
}

/// The words counted in the prompts, one after the other, on more lines when they do not fit.
private struct WordCounts: View {
    let words: [(word: String, count: Int)]

    var body: some View {
        FlowLayout(spacing: 6) {
            Text(L("In prompts", "Nei prompt")).font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                HStack(spacing: 4) {
                    Text(L("“\(w.word)”", "«\(w.word)»")).font(.system(size: 11.5, weight: .medium))
                    Text("\(w.count)").font(.timer(11.5, .bold))
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .lineLimit(1)
                .fixedSize()
            }
        }
    }
}

/// Left to right, then on the next line: chips of any width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((i, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var used: CGFloat = 0
        for line in rows(subviews, width: width) {
            let lineHeight: CGFloat = line.map(\.size.height).max() ?? 0
            let lineWidth: CGFloat = line.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(0, line.count - 1))
            height += (height > 0 ? spacing : 0) + lineHeight
            used = max(used, lineWidth)
        }
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in rows(subviews, width: bounds.width) {
            let h = line.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for item in line {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (h - item.size.height) / 2), anchor: .topLeading,
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += h + spacing
        }
    }
}

/// The editor, from edit mode: which statistics, the multiplier, the words.
struct FunStatsEditor: View {
    @ObservedObject private var store = FunSettingsStore.shared
    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Useless stats", "Statistiche inutili")).font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(FunStat.allCases) { stat in
                    Toggle(stat.title, isOn: Binding(get: { store.settings.stats.contains(stat) },
                                                     set: { store.setOn(stat, $0) }))
                        .font(.system(size: 12))
                }
            }
            Divider()
            Stepper(value: $store.settings.multiplier, in: 1...20, step: 0.5) {
                let m = FunFacts.times(store.settings.multiplier)
                Text(L("Hours without AI: Claude's time ×\(m)", "Ore senza AI: tempo di Claude ×\(m)")).font(.system(size: 12))
            }
            Divider()
            Text(L("Words to count in prompts", "Parole da contare nei prompt")).font(.system(size: 12, weight: .semibold))
            ForEach(store.settings.words, id: \.self) { word in
                HStack {
                    Text(L("“\(word)”", "«\(word)»")).font(.system(size: 12))
                    Spacer()
                    Button { store.settings.words.removeAll { $0 == word } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help(L("Remove “\(word)”", "Togli «\(word)»"))
                }
            }
            HStack {
                TextField(L("Another word", "Un'altra parola"), text: $newWord).textFieldStyle(.roundedBorder).onSubmit(add)
                Button(L("Add", "Aggiungi"), action: add).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Spacer()
                Button(L("Reset", "Ripristina")) { store.reset() }
                    .help(L("The starting stats, the ×4 and the words", "Le statistiche, il ×4 e le parole di partenza"))
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func add() {
        store.addWord(newWord)
        newWord = ""
    }
}
