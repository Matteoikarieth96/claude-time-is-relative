import AppKit
import ServiceManagement

/// Open at login through the system Login Items (System Settings > General > Login Items).
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

/// When the app announces a finished task or one that waits for you.
enum NotifyMode: String, CaseIterable, Identifiable {
    /// Only while the widget is in view: the list open, or the desktop panel on a screen and not
    /// covered by windows. You are watching it, waiting for the task.
    case watching
    case always
    case never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .watching: return L("With the widget in view", "Con il widget a vista")
        case .always: return L("Always", "Sempre")
        case .never: return L("Never", "Mai")
        }
    }
}

final class Prefs: ObservableObject {
    @Published var panelVisible: Bool {
        didSet {
            UserDefaults.standard.set(panelVisible, forKey: "panelVisible")
            onPanel?(panelVisible)
        }
    }
    /// Resting the pointer on the menu bar item opens the list.
    @Published var hoverOpen: Bool {
        didSet { UserDefaults.standard.set(hoverOpen, forKey: "hoverOpen") }
    }
    /// macOS notifications when a task finishes and when Claude waits for you.
    @Published var notifyDone: Bool {
        didSet { UserDefaults.standard.set(notifyDone, forKey: "notifyDone") }
    }
    @Published var notifyWaiting: Bool {
        didSet { UserDefaults.standard.set(notifyWaiting, forKey: "notifyWaiting") }
    }
    /// When to announce: while the widget is in view (the default), always, or never.
    @Published var notifyMode: NotifyMode {
        didSet { UserDefaults.standard.set(notifyMode.rawValue, forKey: "notifyMode") }
    }
    /// Hover to click (Hover.swift): the same "dwellClick" key the controls read.
    @Published var dwellClick: Bool {
        didSet { UserDefaults.standard.set(dwellClick, forKey: "dwellClick") }
    }
    /// The TaskETA button in the Touch Bar's Control Strip (TouchBar.swift), off until you turn it on.
    @Published var touchBarOn: Bool {
        didSet {
            UserDefaults.standard.set(touchBarOn, forKey: "touchBarOn")
            onTouchBar?(touchBarOn)
        }
    }
    /// The local server for the iPhone widget (PhoneServer), off until you turn it on.
    @Published var phoneOn: Bool {
        didSet {
            UserDefaults.standard.set(phoneOn, forKey: "phoneOn")
            onPhone?(phoneOn)
        }
    }
    /// The code the iPhone widget sends with each request; a new one locks out the old scripts.
    @Published var phoneToken: String {
        didSet { UserDefaults.standard.set(phoneToken, forKey: "phoneToken") }
    }
    @Published private(set) var loginOn = false
    /// What went wrong turning open at login on or off, and whether macOS wants an approval: kept as facts,
    /// put in words when shown, so a language switch reaches them too.
    @Published private var loginError: String?
    @Published private var loginNeedsApproval = false
    var loginNote: String? {
        if let loginError { return L("Failed: \(loginError)", "Non riuscito: \(loginError)") }
        return loginNeedsApproval
            ? L("Approve it in System Settings > General > Login Items.", "Approvalo in Impostazioni di Sistema > Generali > Elementi login.") : nil
    }
    var onPanel: ((Bool) -> Void)?
    var onPhone: ((Bool) -> Void)?
    var onTouchBar: ((Bool) -> Void)?

    init() {
        let defaults = UserDefaults.standard
        panelVisible = defaults.object(forKey: "panelVisible") as? Bool ?? false
        hoverOpen = defaults.object(forKey: "hoverOpen") as? Bool ?? true
        notifyDone = defaults.object(forKey: "notifyDone") as? Bool ?? true
        notifyWaiting = defaults.object(forKey: "notifyWaiting") as? Bool ?? true
        notifyMode = defaults.string(forKey: "notifyMode").flatMap(NotifyMode.init(rawValue:)) ?? .watching
        touchBarOn = defaults.object(forKey: "touchBarOn") as? Bool ?? false
        dwellClick = defaults.object(forKey: "dwellClick") as? Bool ?? true
        phoneOn = defaults.object(forKey: "phoneOn") as? Bool ?? false
        phoneToken = defaults.string(forKey: "phoneToken") ?? Prefs.newToken()
        defaults.set(phoneToken, forKey: "phoneToken")
        readLogin()
    }

    /// 20 random hex characters (80 bits, from the system's secure generator).
    static func newToken() -> String {
        String((0..<20).map { _ in "0123456789abcdef".randomElement()! })
    }

    func setLogin(_ on: Bool) {
        let error = LoginItem.set(on)
        readLogin()
        if let error { loginError = error }
        if LoginItem.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    private func readLogin() {
        let status = LoginItem.status
        loginOn = status == .enabled || status == .requiresApproval
        loginError = nil
        loginNeedsApproval = status == .requiresApproval
    }

    /// Shows the folder in the Finder. Never `open`: that would launch whatever sits at the path.
    func openLiveFolder(_ dir: URL) {
        let fm = FileManager.default
        let target = fm.fileExists(atPath: dir.path) ? dir : dir.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }
}
