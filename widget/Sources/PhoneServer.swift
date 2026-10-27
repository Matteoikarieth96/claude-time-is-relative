import AppKit
import Network
import SystemConfiguration

/// The iPhone widget's source. With "Widget on the iPhone" on (off by default) a small HTTP
/// server answers `GET /status` on port 8765 with the menu bar's counts and the sessions of the
/// panel, row by row as the Mac shows them, for the Scriptable widget in widget/iphone/: the iPhone
/// as a window on the Mac's sessions, nothing more. Only devices on the subnet of this Mac's Wi-Fi or
/// Ethernet get an answer, and only with the code. Plain HTTP: the script tries the Mac's last IP and
/// `<name>.local` on whatever network the iPhone is on, sending the code each time, and prompts and
/// titles go out only if you allow them.
final class PhoneServer: ObservableObject {
    static let port: UInt16 = 8765
    /// What the settings show under the switch: the address, or why the server is not running.
    var note: String? { serverState?.text }
    @Published private(set) var listening = false
    /// Where the script for Scriptable stands in iCloud Drive (see syncScript).
    var scriptNote: String? { scriptState?.text }
    /// The two notes kept as what happened and put into words when shown: they follow the language.
    @Published private var serverState: ServerNote?
    @Published private var scriptState: ScriptNote?

    private let store: TaskStore
    private let prefs: Prefs
    private var listener: NWListener?
    private var syncTimer: Timer?
    private var languageObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "io.github.matteoikarieth96.TaskETA.phone")
    /// Connections open, and those still waiting for their request (both only touched on `queue`).
    private var clients = Set<ObjectIdentifier>()
    private var awaiting = Set<ObjectIdentifier>()
    static let maxClients = 8

    init(store: TaskStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
        // The script carries the language: written again at once, so the iPhone has it at its next refresh.
        languageObserver = NotificationCenter.default.addObserver(forName: Loc.changed, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.listener != nil else { return }
            self.syncScript()
        }
    }

    private enum ServerNote {
        case portFailed(String), listening, stopped(String)

        var text: String {
            switch self {
            case .portFailed(let error):
                return L("Can't open port \(PhoneServer.port): \(error)", "Non riesco ad aprire la porta \(PhoneServer.port): \(error)")
            case .listening: return L("Listening on \(PhoneServer.address)", "In ascolto su \(PhoneServer.address)")
            case .stopped(let error): return L("Server stopped: \(error)", "Server fermo: \(error)")
            }
        }
    }

    private enum ScriptNote {
        case noFolder, upToDate, written(Date), failed(String)

        var text: String {
            switch self {
            case .noFolder:
                return L("Scriptable's folder not found in iCloud: on the iPhone, turn on iCloud Drive for Scriptable.",
                         "Cartella di Scriptable in iCloud non trovata: sull'iPhone attiva iCloud Drive per Scriptable.")
            case .upToDate: return L("Script in iCloud Drive > Scriptable, up to date.", "Script in iCloud Drive > Scriptable, aggiornato.")
            case .written(let date):
                let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Loc.locale))
                return L("Script updated in iCloud Drive > Scriptable at \(time).", "Script aggiornato in iCloud Drive > Scriptable alle \(time).")
            case .failed(let error):
                return L("Can't write the script to iCloud: \(error)", "Non riesco a scrivere lo script in iCloud: \(error)")
            }
        }
    }

    /// The address the widget calls: this Mac's Bonjour name, which follows it when its IP changes.
    static var address: String {
        let name = SCDynamicStoreCopyLocalHostName(nil) as String? ?? "localhost"
        return "http://\(name).local:\(port)"
    }

    /// This Mac's IPv4 address on the Wi-Fi or Ethernet: the script tries it first, with no name to look up.
    static var ipAddress: String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  String(cString: entry.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            return String(cString: host)
        }
        return nil
    }

    func apply(_ on: Bool) { on ? start() : stop() }

    private func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: port)
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async { self?.update(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
            self.listener = listener
            syncScript()
            syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.syncScript() }
        } catch {
            serverState = .portFailed(error.localizedDescription)
        }
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        syncTimer?.invalidate()
        syncTimer = nil
        scriptState = nil
        listening = false
        serverState = nil
        removeScript()
    }

    /// With the server off the code does not stay in iCloud Drive: TaskETA.js goes if it is ours
    /// (a plain file with the current code in it). syncScript writes it again when the server is back on.
    private func removeScript() {
        let url = PhoneScript.iCloudFolder.appendingPathComponent("TaskETA.js")
        guard isRegularFile(url.path), let text = try? String(contentsOf: url, encoding: .utf8),
              text.contains("\"\(prefs.phoneToken)\"") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func update(_ state: NWListener.State) {
        switch state {
        case .ready:
            listening = true
            serverState = .listening
        case .failed(let error):
            listening = false
            serverState = .stopped(error.localizedDescription)
            listener?.cancel()
            listener = nil
        case .cancelled:
            listening = false
        default:
            break
        }
    }

    /// Keeps iCloud Drive > Scriptable > TaskETA.js the same as this app's script, with the
    /// address, the IP and the code in it: on the iPhone it just shows up in Scriptable, nothing to
    /// copy. Checked every minute (a new build, a new code, a new IP) and when the language changes
    /// (the script speaks it); written only when different.
    func syncScript() {
        let folder = PhoneScript.iCloudFolder
        guard FileManager.default.fileExists(atPath: folder.path) else {
            scriptState = .noFolder
            return
        }
        guard let text = PhoneScript.text(token: prefs.phoneToken) else { return }
        let url = folder.appendingPathComponent("TaskETA.js")
        // Written again only when the app's own script changes (or the file is gone): an edit or a
        // save made on the iPhone is never fought over.
        // FNV-1a of the text: the same from one launch to the next (hashValue is not).
        let stamp = String(text.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }, radix: 36)
        let written = UserDefaults.standard.string(forKey: "phoneScriptWritten")
        // A script emptied or cut short on the iPhone (no code in it any more) is put back.
        let current = try? String(contentsOf: url, encoding: .utf8)
        if let current, current.contains("\"\(prefs.phoneToken)\""), written == stamp || current == text {
            UserDefaults.standard.set(stamp, forKey: "phoneScriptWritten")
            switch scriptState {
            case .upToDate?, .written?: break
            default: scriptState = .upToDate
            }
            return
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            UserDefaults.standard.set(stamp, forKey: "phoneScriptWritten")
            scriptState = .written(Date())
        } catch {
            scriptState = .failed(error.localizedDescription)
        }
    }

    // MARK: - HTTP

    private func accept(_ connection: NWConnection) {
        guard clients.count < Self.maxClients, Self.onOwnNetwork(connection.endpoint) else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        clients.insert(id)
        awaiting.insert(id)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.clients.remove(id)
                self?.awaiting.remove(id)
            default: break
            }
        }
        connection.start(queue: queue)
        // A client that has not sent its request within 2 s is dropped, any client after 5 s
        // (cancelling twice is harmless). Both keep the connection alive: no new one gets its id meanwhile.
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.awaiting.contains(id) != false { connection.cancel() }
        }
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        receive(connection, Data())
    }

    private func receive(_ connection: NWConnection, _ buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.awaiting.remove(ObjectIdentifier(connection))
                self.respond(connection, head: String(decoding: buffer[..<end.lowerBound], as: UTF8.self))
            } else if done || error != nil || buffer.count > 16_384 {
                connection.cancel()
            } else {
                self.receive(connection, buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let request = lines.first?.split(separator: " ") ?? []
        guard request.count >= 2, request[0] == "GET" else {
            return send(connection, 405, ["error": "solo GET"])
        }
        let path = request[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        guard path == "/status" else { return send(connection, 404, ["error": "non trovato"]) }
        let auth = lines.dropFirst().first { $0.lowercased().hasPrefix("authorization:") }
            .map { $0.dropFirst("authorization:".count).trimmingCharacters(in: .whitespaces) } ?? ""
        // The store, the token and the gems (one cache with the Touch Bar) live on the main thread.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return connection.cancel() }
            guard auth == "Bearer \(self.prefs.phoneToken)" else {
                return self.queue.async { self.send(connection, 401, ["error": "codice sbagliato"]) }
            }
            var body = self.status()
            let styles = self.styles()
            body.themes = styles.themes
            body.themeHints = styles.hints.isEmpty ? nil : styles.hints
            body.theme = PhoneTheme.current(won: styles.themes)
            self.queue.async { self.send(connection, 200, body) }
        }
    }

    private func send<T: Encodable>(_ connection: NWConnection, _ code: Int, _ value: T) {
        let body = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        let reason = [200: "OK", 401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed"][code] ?? "Error"
        let head = "HTTP/1.1 \(code) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - what the widget gets

    /// The widget's three styles are won with the estimates (Gems.swift, WidgetTheme): which ones
    /// are, and how to win the others. The index is read again only when it changes.
    private func styles() -> PhoneStyles {
        let mood = GameMood.current
        let won = WidgetTheme.won(gems: GemStats.current(store.indexURL), mine: MineStats.current(store.indexURL))
        return PhoneStyles(themes: won.map(\.rawValue),
                                 hints: Dictionary(uniqueKeysWithValues: WidgetTheme.allCases.filter { !won.contains($0) }
                                     .map { ($0.rawValue, $0.how(mood)) }))
    }

    /// The menu bar's numbers (waiting, running, finished in the last hour) and the panel's
    /// sessions in its order, up to 8, each as its row on the Mac: names hidden like the list's,
    /// and always unless prompts may go to the iPhone (they cross the Wi-Fi unencrypted).
    func status() -> PhoneStatus {
        let now = store.now
        let hide = store.hidePrompts || !prefs.phoneShowPrompts
        let visible = store.visible
        let task = { (item: TaskItem) in
            PhoneTask(name: item.shownName(hidePrompts: hide), folder: item.folderText,
                      model: item.modelText, state: "\(item.state)", elapsed: item.elapsed(at: now),
                      estimate: item.estimate, low: item.range?.low, high: item.range?.high,
                      pace: item.pace(at: now).name, over: item.overrunText(at: now, short: true),
                      note: Self.note(item, now: now, hidePrompts: hide))
        }
        return PhoneStatus(mac: SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac", now: now,
                           running: store.runningCount, waiting: store.waitingCount, done: store.doneCount,
                           tasks: visible.prefix(8).map(task))
    }

    /// The words under a row of the panel (TaskRow in Views.swift), the same on the iPhone: what the
    /// session waits for, how far past the estimate, the job in background, how long it has been
    /// still, when it ended.
    static func note(_ item: TaskItem, now: Double, hidePrompts: Bool) -> String? {
        switch item.state {
        case .waiting:
            return item.waitingText(hidePrompts: hidePrompts)
        case .running:
            return item.overrunText(at: now)
        case .background:
            if let over = item.overrunText(at: now) { return over }
            let jobs = item.data.bgJobs ?? []
            guard !hidePrompts, let first = jobs.first, !first.isEmpty else { return L("background jobs", "job in background") }
            return jobs.count == 1 ? first : L("\(jobs.count) jobs: \(first)…", "\(jobs.count) job: \(first)…")
        case .stale:
            return L("stalled for \(clock(item.quiet ?? 0))", "fermo da \(clock(item.quiet ?? 0))")
        case .done:
            let end = Date(timeIntervalSince1970: item.data.endTs ?? item.data.startTs)
            let time = end.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Loc.locale))
            let at = L("at \(time)", "alle " + time)
            return item.overrunText(at: now, short: true).map { "\($0), \(at)" } ?? at
        }
    }

    // MARK: - same network

    /// True for a client on one of this Mac's networks: its address inside the subnet of the Mac's
    /// Wi-Fi or Ethernet (the `en` interfaces, as `ipAddress`). VPN tunnels, the loopback and
    /// anything farther get no answer.
    static func onOwnNetwork(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            return inOwnSubnet([UInt8](address.rawValue))
        case .ipv6(let address):
            if let v4 = address.asIPv4 { return inOwnSubnet([UInt8](v4.rawValue)) }
            return inOwnSubnet([UInt8](address.rawValue))
        default:
            return false
        }
    }

    static func inOwnSubnet(_ remote: [UInt8]) -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard entry.ifa_flags & UInt32(IFF_UP) != 0, String(cString: entry.ifa_name).hasPrefix("en"),
                  let addr = entry.ifa_addr, let mask = entry.ifa_netmask
            else { continue }
            let family = Int32(addr.pointee.sa_family)
            let own, bits: [UInt8]
            if family == AF_INET, remote.count == 4 {
                own = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin_addr) { Array($0) } }
                bits = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin_addr) { Array($0) } }
            } else if family == AF_INET6, remote.count == 16 {
                own = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) } }
                bits = mask.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) } }
            } else {
                continue
            }
            if sameSubnet(withoutScope(remote), withoutScope(own), mask: bits) { return true }
        }
        return false
    }

    /// An IPv6 link-local address (fe80::/10) without the interface index macOS keeps in bytes 2-3
    /// of its own: with it, the Mac's address never matched an iPhone's.
    static func withoutScope(_ address: [UInt8]) -> [UInt8] {
        guard address.count == 16, address[0] == 0xfe, address[1] & 0xc0 == 0x80 else { return address }
        var out = address
        out[2] = 0
        out[3] = 0
        return out
    }

    /// The two addresses agree on every bit of the mask. A mask wider than a /16 (or /64 for
    /// IPv6), like a big company network's, lets too many in, so it never counts.
    static func sameSubnet(_ a: [UInt8], _ b: [UInt8], mask: [UInt8]) -> Bool {
        guard a.count == b.count, mask.count == a.count else { return false }
        let prefix = mask.reduce(0) { $0 + $1.nonzeroBitCount }
        guard prefix >= (a.count == 4 ? 16 : 64) else { return false }
        return zip(zip(a, b), mask).allSatisfy { pair, m in pair.0 & m == pair.1 & m }
    }
}

struct PhoneStatus: Encodable {
    var v = 1
    var mac: String
    var now: Double
    var running: Int     // running and in background
    var waiting: Int
    var done: Int        // finished in the last hour, as in the menu bar
    var tasks: [PhoneTask]
    var themes: [String]? = nil              // the widget styles won so far (WidgetTheme)
    var themeHints: [String: String]? = nil  // how to win the others
    var theme: String? = nil                 // the style picked on the Mac (PhoneTheme), "auto" until one won is picked
    var lang = Loc.lang.rawValue             // the language of the texts above, which the script follows too
}

struct PhoneTask: Encodable {
    var name: String     // the session title or the prompt, "Task in <folder>" with prompts hidden
    var folder: String
    var model: String    // "opus-5-5 xhigh", as under the row on the Mac
    var state: String    // waiting, running, background, stale, done
    var elapsed: Double  // seconds, without the time the task waited for you
    var estimate: Double?
    var low: Double?
    var high: Double?
    var pace: String     // green, yellow, red, grey, neutral
    var over: String?    // "+10 min (×6)" once past the estimate
    var note: String?    // the words under the row on the Mac: "piano da approvare", "alle 16:20"…
}

struct PhoneStyles {
    var themes: [String]
    var hints: [String: String]
}

extension Pace {
    var name: String {
        switch self {
        case .green: return "green"
        case .yellow: return "yellow"
        case .red: return "red"
        case .grey: return "grey"
        case .neutral: return "neutral"
        }
    }
}

/// The Scriptable script with this Mac's address, token and language already in it.
enum PhoneScript {
    /// Scriptable's folder in iCloud Drive, there once Scriptable runs on the iPhone with iCloud on.
    static var iCloudFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents", isDirectory: true)
    }

    static func text(token: String) -> String? {
        guard let url = Bundle.main.url(forResource: "TaskETA", withExtension: "js"),
              let template = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return template.replacingOccurrences(of: "__TASKETA_URL__", with: PhoneServer.address)
            .replacingOccurrences(of: "__TASKETA_IP_URL__", with: PhoneServer.ipAddress.map { "http://\($0):\(PhoneServer.port)" } ?? "")
            .replacingOccurrences(of: "__TASKETA_TOKEN__", with: token)
            .replacingOccurrences(of: "__TASKETA_LANG__", with: Loc.lang.rawValue)
    }
}
