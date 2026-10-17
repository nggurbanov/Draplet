import AppKit
import ApplicationServices
import Combine
import ServiceManagement

enum Constant {
    static var isUsingLTRLanguage: Bool { NSApp.userInterfaceLayoutDirection == .leftToRight }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let store = UserDefaults.standard
    @Published var leftEnabled: Bool { didSet { save(leftEnabled, "leftEnabled") } }
    @Published var rightEnabled: Bool { didSet { save(rightEnabled, "rightEnabled") } }
    @Published var autoCollapse: Bool { didSet { save(autoCollapse, "autoCollapse") } }
    @Published var collapseDelay: Double { didSet { save(collapseDelay, "collapseDelay") } }
    @Published var hoverRight: Bool { didSet { save(hoverRight, "hoverRight") } }
    @Published var alwaysHidden: Bool { didSet { save(alwaysHidden, "alwaysHidden") } }
    @Published var fullWidth: Bool { didSet { save(fullWidth, "fullWidth") } }
    @Published var shortcut: Int { didSet { save(shortcut, "shortcut") } }
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var permissionGranted = AXIsProcessTrusted()
    @Published var rightStatus = "Expanded"
    @Published var paused = false
    @Published var error = ""
    init() {
        store.register(defaults: ["leftEnabled": true, "rightEnabled": true, "autoCollapse": true,
                                 "collapseDelay": 5.0, "hoverRight": false, "alwaysHidden": false,
                                 "fullWidth": false, "shortcut": 0])
        leftEnabled = store.bool(forKey: "leftEnabled")
        rightEnabled = store.bool(forKey: "rightEnabled")
        autoCollapse = store.bool(forKey: "autoCollapse")
        collapseDelay = store.double(forKey: "collapseDelay")
        hoverRight = store.bool(forKey: "hoverRight")
        alwaysHidden = store.bool(forKey: "alwaysHidden")
        fullWidth = store.bool(forKey: "fullWidth")
        shortcut = store.integer(forKey: "shortcut")
    }
    private func save(_ value: Any, _ key: String) {
        store.set(value, forKey: key)
        NotificationCenter.default.post(name: .drapletPreferencesChanged, object: nil)
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            error = ""
        } catch { self.error = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
    }
}

extension Notification.Name {
    static let drapletPreferencesChanged = Notification.Name("DrapletPreferencesChanged")
}
