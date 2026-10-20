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

final class Prefs: ObservableObject {
    @Published var panelVisible: Bool {
        didSet {
            UserDefaults.standard.set(panelVisible, forKey: "panelVisible")
            onPanel?(panelVisible)
        }
    }
    @Published private(set) var loginOn = false
    @Published private(set) var loginNote: String?
    var onPanel: ((Bool) -> Void)?

    init() {
        panelVisible = UserDefaults.standard.object(forKey: "panelVisible") as? Bool ?? false
        readLogin()
    }

    func setLogin(_ on: Bool) {
        let error = LoginItem.set(on)
        readLogin()
        if let error { loginNote = "Failed: \(error)" }
        if LoginItem.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    private func readLogin() {
        let status = LoginItem.status
        loginOn = status == .enabled || status == .requiresApproval
        loginNote = status == .requiresApproval
            ? "Approve it in System Settings > General > Login Items." : nil
    }

    /// Shows the folder in the Finder. Never `open`: that would launch whatever sits at the path.
    func openLiveFolder(_ dir: URL) {
        let fm = FileManager.default
        let target = fm.fileExists(atPath: dir.path) ? dir : dir.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }
}
