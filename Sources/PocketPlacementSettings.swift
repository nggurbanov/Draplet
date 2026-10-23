import SwiftUI
import AppKit
import Combine

final class PocketPlacementModel: ObservableObject {
    @Published var items: [PocketItem] = []
    @Published var loading = false
    @Published var disallowed = Set<String>()
    func reload() {
        guard !loading else { return }; loading = true
        PocketInventory.read { [weak self] result in self?.items = result; self?.disallowed = MenuBarAvailability.currentDisallowed(); self?.loading = false }
    }
}

struct PocketPlacementSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: PocketPlacementModel
    private var items: [PocketItem] { model.items }
    private var loading: Bool { model.loading }
    private var bundles: [String] { Array(Set(items.map(\.bundle)).union(prefs.pinnedPocketBundles)).filter(Preferences.canPinPocketBundle).sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending } }
    private var supported: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 && HBNativeVisibilityIsAvailable() }
    private func name(_ bundle: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first { return app.localizedName ?? bundle }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
        return bundle
    }
    var body: some View {
        SettingsGroup("Pocket placement") {
            SettingsRow("Choose what stays in Pocket", detail: supported ? "Pinned apps stay in Pocket even when there’s room in the menu bar. On this macOS, all status icons from one app move together. Unpinned icons follow their original menu-bar section and available space." : "Pinning requires the native hiding backend on macOS 27. Existing saved pins can still be removed here.") {
                Button(loading ? "Reading…" : "Refresh List", action: model.reload).disabled(loading)
            }
            if bundles.isEmpty {
                GroupDivider()
                SettingsRow(loading ? "Reading status icons…" : "No status icons found", detail: "Open the apps you want to manage, then refresh this list.") { EmptyView() }
            }
            ForEach(bundles, id: \.self) { bundle in
                GroupDivider()
                let count = items.filter { $0.bundle == bundle }.count
                let pinned = prefs.pinnedPocketBundles.contains(bundle)
                let unavailable = model.disallowed.contains(bundle) ? "Disabled in macOS Menu Bar settings · pin saved"
                    : NSRunningApplication.runningApplications(withBundleIdentifier:bundle).isEmpty ? "Not running · saved for next launch" : "No active menu icon · pin saved"
                SettingsRow(name(bundle), detail: count == 0 ? unavailable : count > 1 ? "\(count) status icons · move together" : "1 status icon") {
                    Button(pinned ? "Return to Menu Bar" : "Keep in Pocket") { prefs.setPocketPin(bundle, pinned: !pinned) }
                        .disabled(!supported && !pinned)
                        .help(pinned ? "Restore the original menu-bar section. Icons that don’t fit remain in automatic overflow." : "Keep this app’s status icons in Pocket until you return them.")
                }
            }
        }.onAppear { model.reload() }
    }
}
