import AppKit
import Combine
import Sparkle

// Sparkle owns archive verification, replacement, rollback and install-on-quit.
// This controller owns the visible reminder, never the installation mechanics.
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = AppUpdater()
    @Published private(set) var status = "Updates have not been checked yet."
    @Published private(set) var readyVersion: String?
    @Published private(set) var pendingVersion: String?
    var updateVersion: String? { readyVersion ?? pendingVersion }
    var actionTitle: String { readyVersion != nil ? "Update and Relaunch" : (pendingVersion != nil ? "Review Update…" : "Check for Updates…") }
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = true
    @Published private(set) var automaticDownloads = true
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []
    private var immediateInstall: (() -> Void)?
    private var reminderTimer: Timer?
    private var showingReminder = false
    private var reminder = UpdateReminderPolicy(
        version: UserDefaults.standard.string(forKey: "updateReminderVersion"),
        deferredUntil: UserDefaults.standard.object(forKey: "updateReminderDeferredUntil") as? Date)

    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                self?.canCheck = updater.canCheckForUpdates
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                self?.automaticChecks = updater.automaticallyChecksForUpdates
            },
            controller.updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                self?.automaticDownloads = updater.automaticallyDownloadsUpdates
            }
        ]
        controller.startUpdater()
        // One launch check; subsequent checks belong to Sparkle's scheduler.
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.showReminderIfDue() }
        reminderTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func setAutomaticChecks(_ value: Bool) { controller?.updater.automaticallyChecksForUpdates = value }
    func setAutomaticDownloads(_ value: Bool) { controller?.updater.automaticallyDownloadsUpdates = value }
    func check() {
        if readyVersion != nil { showReminderIfDue(force: true); return }
        guard let controller else { return }
        if pendingVersion != nil { controller.checkForUpdates(nil); return }
        guard canCheck else { return }
        status = "Checking for updates…"
        controller.checkForUpdates(nil)
    }
    func installNow() {
        guard let install = immediateInstall else { check(); return }
        status = "Installing and relaunching…"
        install()
    }
    func performUpdateAction() {
        if readyVersion != nil { installNow() } else { check() }
    }
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        pendingVersion = update.displayVersionString
        status = "An update is available. Review it to download and install."
        reminder.receive(update.versionString); saveReminder()
        DispatchQueue.main.async { [weak self] in self?.showReminderIfDue() }
    }
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { pendingVersion = nil }
    func standardUserDriverWillFinishUpdateSession() { pendingVersion = nil }
    private func saveReminder() {
        UserDefaults.standard.set(reminder.version, forKey: "updateReminderVersion")
        UserDefaults.standard.set(reminder.deferredUntil, forKey: "updateReminderDeferredUntil")
    }
    private func showReminderIfDue(force: Bool = false) {
        guard controller != nil, let version = updateVersion, !showingReminder,
              !SystemPresentation.current(), force || reminder.isDue(at: Date(), presentationSuppressed: false) else { return }
        // Don't steal focus from another modal sheet or run during termination.
        guard NSApp.modalWindow == nil else { return }
        showingReminder = true
        let alert = NSAlert()
        let downloaded = readyVersion != nil
        alert.messageText = downloaded ? "Draplet \(version) is ready to install" : "Draplet \(version) is available"
        alert.informativeText = downloaded
            ? "Update now for the latest fixes. You can keep working and install automatically when you quit Draplet."
            : "Review the update to download and install the latest fixes. Nothing will be installed until you choose to proceed."
        alert.addButton(withTitle: downloaded ? "Update and Relaunch" : "Review Update…")
        alert.addButton(withTitle: "Remind Me in an Hour")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        showingReminder = false
        if response == .alertFirstButtonReturn { performUpdateAction() }
        else { reminder.deferOneHour(from: Date()); saveReminder() }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = "Draplet \(item.displayVersionString) is available."
    }
    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        status = "Verifying Draplet \(item.displayVersionString)…"
    }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        immediateInstall = immediateInstallHandler
        NSLog("Draplet update staged: build %@; installs on normal quit", item.versionString)
        pendingVersion = nil
        readyVersion = item.displayVersionString
        status = "Ready. Installs when you quit Draplet, or update now."
        reminder.receive(item.versionString)
        saveReminder()
        DispatchQueue.main.async { [weak self] in self?.showReminderIfDue() }
        return true
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let error = error as NSError
        readyVersion = nil
        pendingVersion = nil
        immediateInstall = nil
        if error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue) {
            status = "Draplet is up to date."
        } else {
            if error.domain == SUSparkleErrorDomain && [Int(SUError.signatureError.rawValue), Int(SUError.validationError.rawValue)].contains(error.code) {
                status = "The update couldn’t be verified. Nothing was installed. Check again later."
            } else {
                status = "Couldn’t update: \(error.localizedDescription)"
            }
            NSLog("Draplet updater: %@", error)
        }
    }
}
