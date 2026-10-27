import Foundation
import SwiftUI

// The language of everything TaskETA shows. English is the base, Italian the second language.
// Every text a person reads goes through L("English", "Italiano"): both words sit together in the
// code, so plurals, genders and interpolations stay where they are decided ("1 needs you" /
// "2 need you", "ti aspetta" / "ti aspettano").
//
// The choice (System, English, Italiano) lives in ~/.claude/task-eta/language.json, shared with the
// hooks: {"choice": "system", "language": "en"}. "language" is the resolved one, so task_eta.py
// never has to ask macOS. The app writes it at launch and from Settings; `task_eta.py language it`
// writes it too, and the running app follows within a few seconds.
//
// Another language later: a case in Lang, and in L() its words looked up by the English template of
// each text, which LText keeps with the interpolations numbered {1}, {2}… ("{1} running" → "{1} en
// cours"), for example from a JSON file in the app's Resources; a text it lacks stays in English.

enum Lang: String, CaseIterable, Identifiable {
    case en, it

    var id: String { rawValue }
    /// Its own name, the same in every language.
    var name: String {
        switch self {
        case .en: return "English"
        case .it: return "Italiano"
        }
    }
    /// Dates and times in this language.
    var locale: Locale {
        switch self {
        case .it:
            // The Mac's own Italian (and its 12/24-hour setting) when it has one.
            return Locale.current.language.languageCode == .italian ? Locale.current : Locale(identifier: "it_IT")
        case .en:
            // The Mac's own English (US, UK…) when it has one, else British: a 24-hour clock.
            return Locale.current.language.languageCode == .english ? Locale.current : Locale(identifier: "en_GB")
        }
    }
}

/// What the person picked in Settings.
enum LangChoice: String, CaseIterable, Identifiable {
    case system, en, it

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L("System (\(Loc.systemLang.name))", "Sistema (\(Loc.systemLang.name))")
        case .en: return Lang.en.name
        case .it: return Lang.it.name
        }
    }
    var resolved: Lang {
        switch self {
        case .system: return Loc.systemLang
        case .en: return .en
        case .it: return .it
        }
    }
}

final class Loc: ObservableObject, @unchecked Sendable {
    static let shared = Loc()

    /// Read by L() on any thread; written on the main thread only.
    nonisolated(unsafe) private(set) static var lang: Lang = initialLang()

    @Published private(set) var current: Lang = Loc.lang
    @Published private(set) var choice: LangChoice = Loc.savedChoice() ?? .system
    private var stamp: Date?
    private var timer: Timer?

    /// In task-eta's folder, found as task_eta.py finds it: TASK_ETA_DIR, else CLAUDE_CONFIG_DIR/task-eta,
    /// else ~/.claude/task-eta.
    static var file: URL {
        let env = ProcessInfo.processInfo.environment
        let dir: URL
        if let data = env["TASK_ETA_DIR"], !data.isEmpty {
            dir = URL(fileURLWithPath: data, isDirectory: true)
        } else {
            let claude = env["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
            dir = claude.appendingPathComponent("task-eta", isDirectory: true)
        }
        return dir.appendingPathComponent("language.json")
    }

    /// The Mac's first language, if TaskETA speaks it; English otherwise.
    static var systemLang: Lang {
        for code in Locale.preferredLanguages {
            let base = String(code.prefix(2)).lowercased()
            if let lang = Lang(rawValue: base) { return lang }
            if base != "" { break } // only the first language the Mac prefers counts
        }
        return .en
    }

    static var locale: Locale { lang.locale }

    /// TASKETA_LANG=en|it wins for a run (snapshots in both languages without touching the setting).
    private static var forced: Lang? {
        ProcessInfo.processInfo.environment["TASKETA_LANG"].flatMap { Lang(rawValue: $0.lowercased()) }
    }

    private static func initialLang() -> Lang { forced ?? savedChoice()?.resolved ?? systemLang }

    static func savedChoice() -> LangChoice? {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["choice"] as? String).flatMap(LangChoice.init(rawValue:))
    }

    /// The menu bar app: writes the resolved language for the hooks (System may have changed since),
    /// then looks at the file every few seconds (a stat) in case `task_eta.py language` changed it.
    @MainActor
    func start() {
        if Loc.forced == nil { save(choice) }
        stamp = Loc.modified()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followFile() }
        }
        timer?.tolerance = 2
    }

    /// From Settings.
    @MainActor
    func set(_ choice: LangChoice) {
        save(choice)
        stamp = Loc.modified()
        apply(choice)
    }

    /// For `--switch-snapshot`: a live switch, without writing the file (TASKETA_LANG or not).
    @MainActor
    func preview(_ lang: Lang) { apply(lang == .it ? .it : .en, lang: lang) }

    @MainActor
    private func followFile() {
        let now = Loc.modified()
        guard now != stamp else { return }
        stamp = now
        if let saved = Loc.savedChoice(), saved != choice || saved.resolved != current { apply(saved) }
    }

    @MainActor
    private func apply(_ choice: LangChoice, lang shown: Lang? = nil) {
        self.choice = choice
        let lang = shown ?? Loc.forced ?? choice.resolved
        guard lang != Loc.lang else { return }
        Loc.lang = lang
        current = lang
        NotificationCenter.default.post(name: Loc.changed, object: nil)
    }

    static let changed = Notification.Name("TaskETALanguageChanged")

    private func save(_ choice: LangChoice) {
        let json: [String: String] = ["choice": choice.rawValue, "language": choice.resolved.rawValue]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { return }
        let dir = Loc.file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        Loc.writePrivate(data, to: Loc.file)
    }

    /// A file shared with the hooks, written as task_eta.py's write_json does: a new temporary file
    /// next to it (0600, never through a link), then a rename over the name, so a link there is
    /// replaced, never followed. Also the Mine's pickaxe (Miniera.swift). False if not written.
    @discardableResult
    static func writePrivate(_ data: Data, to url: URL) -> Bool {
        let tmp = url.path + ".\(getpid()).tmp"
        unlink(tmp)  // a crashed run's leftover, or a link planted there: removed, never followed
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return false }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let written = (try? handle.write(contentsOf: data)) != nil
        try? handle.close()
        guard written, rename(tmp, url.path) == 0 else {
            unlink(tmp)
            return false
        }
        return true
    }

    private static func modified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    /// For the selftest: `body` in that language, then back.
    static func testing<T>(_ lang: Lang, _ body: () -> T) -> T {
        let was = Loc.lang
        Loc.lang = lang
        defer { Loc.lang = was }
        return body()
    }

    // MARK: numbers

    /// "2.5" or "2,5".
    static func decimal(_ x: Double, digits: Int = 1) -> String {
        let s = String(format: "%.\(digits)f", x)
        return lang == .it ? s.replacingOccurrences(of: ".", with: ",") : s
    }

    /// "12,345" or "12.345".
    static func integer(_ n: Int) -> String {
        n.formatted(.number.grouping(.automatic).locale(lang == .it ? Locale(identifier: "it_IT") : Locale(identifier: "en_US")))
    }
}

/// The text in the chosen language: English first (the base), then Italian.
func L(_ en: LText, _ it: @autoclosure () -> String) -> String {
    switch Loc.lang {
    case .en: return en.text
    case .it: return it()
    }
}

/// An English text that remembers its template, so another language's file can be keyed by it:
/// "\(n) running" is "{1} running" with "3" as {1}.
struct LText: ExpressibleByStringInterpolation {
    let template: String
    let args: [String]

    init(stringLiteral value: String) {
        template = value
        args = []
    }

    init(stringInterpolation i: StringInterpolation) {
        template = i.template
        args = i.args
    }

    var text: String { args.isEmpty ? template : fill(template) }

    /// The template (this one or a translation of it) with the values in place.
    func fill(_ pattern: String) -> String {
        var out = pattern
        for (n, arg) in args.enumerated().reversed() { out = out.replacingOccurrences(of: "{\(n + 1)}", with: arg) }
        return out
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var template = ""
        var args: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {
            template.reserveCapacity(literalCapacity + interpolationCount * 3)
        }

        mutating func appendLiteral(_ literal: String) { template += literal }

        mutating func appendInterpolation<T>(_ value: T) {
            args.append("\(value)")
            template += "{\(args.count)}"
        }
    }
}

/// Views that follow the language: the whole tree is drawn again when it changes.
struct FollowsLanguage: ViewModifier {
    @ObservedObject private var loc = Loc.shared

    func body(content: Content) -> some View {
        content
            .id(loc.current)
            .environment(\.locale, loc.current.locale)
    }
}

extension View {
    func followsLanguage() -> some View { modifier(FollowsLanguage()) }
}
