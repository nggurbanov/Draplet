import AppKit
import ApplicationServices
import Combine
import ServiceManagement

enum Constant {
    static var isUsingLTRLanguage: Bool { NSApp.userInterfaceLayoutDirection == .leftToRight }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let store: UserDefaults
    @Published var leftEnabled: Bool { didSet { save(leftEnabled, "leftEnabled") } }
    @Published var rightEnabled: Bool { didSet { save(rightEnabled, "rightEnabled") } }
    @Published var autoCollapse: Bool { didSet { save(autoCollapse, "autoCollapse") } }
    @Published var collapseDelay: Double { didSet { save(collapseDelay, "collapseDelay") } }
    @Published var sameIcons: Bool { didSet { save(sameIcons, "sameIcons") } }
    @Published var sharedIcon: IndicatorStyle { didSet { save(sharedIcon.rawValue, "sharedIcon") } }
    @Published var leftIcon: IndicatorStyle { didSet { save(leftIcon.rawValue, "leftIcon") } }
    @Published var rightIcon: IndicatorStyle { didSet { save(rightIcon.rawValue, "rightIcon") } }
    @Published var sharedCustomIcon: Data? { didSet { save(sharedCustomIcon, "sharedCustomIcon") } }
    @Published var leftCustomIcon: Data? { didSet { save(leftCustomIcon, "leftCustomIcon") } }
    @Published var rightCustomIcon: Data? { didSet { save(rightCustomIcon, "rightCustomIcon") } }
    @Published var sameTrigger: Bool { didSet { save(sameTrigger, "sameTrigger") } }
    @Published var sharedTrigger: RevealTrigger { didSet { save(sharedTrigger.rawValue, "sharedTrigger") } }
    @Published var leftTrigger: RevealTrigger { didSet { save(leftTrigger.rawValue, "leftTrigger") } }
    @Published var rightTrigger: RevealTrigger { didSet { save(rightTrigger.rawValue, "rightTrigger") } }
    @Published var alwaysHidden: Bool { didSet { save(alwaysHidden, "alwaysHidden") } }
    @Published var fullWidth: Bool { didSet { save(fullWidth, "fullWidth") } }
    @Published var shortcut: Int { didSet { save(shortcut, "shortcut") } }
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var permissionGranted = AXIsProcessTrusted()
    @Published var rightStatus = "Expanded"
    @Published var paused = false
    @Published var error = ""
    init(store: UserDefaults = .standard) {
        self.store = store
        store.register(defaults: ["leftEnabled": true, "rightEnabled": true, "autoCollapse": true,
                                 "collapseDelay": 5.0, "hoverRight": false, "alwaysHidden": false,
                                 "fullWidth": false, "shortcut": 0])
        leftEnabled = store.bool(forKey: "leftEnabled")
        rightEnabled = store.bool(forKey: "rightEnabled")
        autoCollapse = store.bool(forKey: "autoCollapse")
        collapseDelay = store.double(forKey: "collapseDelay")
        sameIcons = store.object(forKey: "sameIcons") as? Bool ?? true
        let initialIcon = IndicatorStyle(rawValue: store.string(forKey: "sharedIcon") ?? "") ?? .chevron
        sharedIcon = initialIcon
        leftIcon = IndicatorStyle(rawValue: store.string(forKey: "leftIcon") ?? "") ?? initialIcon
        rightIcon = IndicatorStyle(rawValue: store.string(forKey: "rightIcon") ?? "") ?? initialIcon
        sharedCustomIcon = store.data(forKey: "sharedCustomIcon")
        leftCustomIcon = store.data(forKey: "leftCustomIcon")
        rightCustomIcon = store.data(forKey: "rightCustomIcon")
        sameTrigger = store.object(forKey: "sameTrigger") as? Bool ?? true
        let initialTrigger = RevealTrigger(rawValue: store.string(forKey: "sharedTrigger") ?? "") ?? .hover
        sharedTrigger = initialTrigger
        leftTrigger = RevealTrigger(rawValue: store.string(forKey: "leftTrigger") ?? "") ?? initialTrigger
        rightTrigger = RevealTrigger(rawValue: store.string(forKey: "rightTrigger") ?? "") ?? initialTrigger
        alwaysHidden = store.bool(forKey: "alwaysHidden")
        fullWidth = store.bool(forKey: "fullWidth")
        shortcut = store.integer(forKey: "shortcut")
    }
    func icon(for side: BarSide) -> IndicatorStyle { sameIcons ? sharedIcon : (side == .left ? leftIcon : rightIcon) }
    func customIcon(for side: BarSide) -> Data? { sameIcons ? sharedCustomIcon : (side == .left ? leftCustomIcon : rightCustomIcon) }
    func trigger(for side: BarSide) -> RevealTrigger { sameTrigger ? sharedTrigger : (side == .left ? leftTrigger : rightTrigger) }
    func linkIcons(_ linked: Bool) {
        if linked { sharedIcon = leftIcon; sharedCustomIcon = leftCustomIcon }
        else { leftIcon = sharedIcon; rightIcon = sharedIcon; leftCustomIcon = sharedCustomIcon; rightCustomIcon = sharedCustomIcon }
        sameIcons = linked
    }
    func linkTriggers(_ linked: Bool) {
        if linked { sharedTrigger = leftTrigger }
        else { leftTrigger = sharedTrigger; rightTrigger = sharedTrigger }
        sameTrigger = linked
    }
    func setCustomIcon(_ data: Data, side: BarSide?) {
        if let side {
            if side == .left { leftCustomIcon = data; leftIcon = .custom }
            else { rightCustomIcon = data; rightIcon = .custom }
        } else { sharedCustomIcon = data; sharedIcon = .custom }
    }
    func removeCustomIcon(side: BarSide?) {
        if let side {
            if side == .left { if leftIcon == .custom { leftIcon = .chevron }; leftCustomIcon = nil }
            else { if rightIcon == .custom { rightIcon = .chevron }; rightCustomIcon = nil }
        } else { if sharedIcon == .custom { sharedIcon = .chevron }; sharedCustomIcon = nil }
    }
    private func save(_ value: Any?, _ key: String) {
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
