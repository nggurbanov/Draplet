import AppKit
import Combine
import Sparkle

// Sparkle owns archive verification, replacement, rollback and install-on-quit.
// This controller owns the visible reminder, never the installation mechanics.
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()
    @Published private(set) var status = "Updates have not been checked yet."
    @Published private(set) var readyVersion: String?
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
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
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
        guard let controller, canCheck else { return }
        status = "Checking for updates…"
        controller.checkForUpdates(nil)
    }
    func installNow() {
        guard let install = immediateInstall else { check(); return }
        status = "Installing and relaunching…"
        install()
    }
    private func saveReminder() {
        UserDefaults.standard.set(reminder.version, forKey: "updateReminderVersion")
        UserDefaults.standard.set(reminder.deferredUntil, forKey: "updateReminderDeferredUntil")
    }
    private func showReminderIfDue() {
        guard readyVersion != nil, !showingReminder,
              reminder.isDue(at: Date(), presentationSuppressed: SystemPresentation.current()) else { return }
        // Don't steal focus from another modal sheet or run during termination.
        guard NSApp.modalWindow == nil else { return }
        showingReminder = true
        let alert = NSAlert()
        alert.messageText = "Draplet \(readyVersion!) is ready to install"
        alert.informativeText = "Update now for the latest fixes. You can keep working and install automatically when you quit Draplet."
        alert.addButton(withTitle: "Update and Relaunch")
        alert.addButton(withTitle: "Remind Me in an Hour")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        showingReminder = false
        if response == .alertFirstButtonReturn { installNow() }
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
