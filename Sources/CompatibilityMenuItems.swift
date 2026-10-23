import AppKit
import CryptoKit

// A returned extra which assessment mode refuses to render can use our own
// native slot. Its ink comes from Pocket's existing cache; its actions still
// belong to the publisher. No application files or signatures are changed.
enum CompatibilityMenuPolicy {
    static func validated(_ saved: [String: Int]) -> [String: Int] {
        var result: [String: Int] = [:]
        for key in saved.keys.sorted().prefix(128) {
            guard key.count <= 1024, let separator = key.firstIndex(of: "|"),
                  Preferences.canPinPocketBundle(String(key[..<separator])),
                  let raw = saved[key], MenuBarSection(rawValue: raw) != nil else { continue }
            result[key] = raw
        }
        return result
    }
    static func identifier(_ key: String) -> String {
        "Draplet.Compatibility." + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func frames(bindings: [String: String], host: PocketInventory.HostSnapshot?, owner: pid_t) -> [String: CGRect] {
        guard let host else { return [:] }
        var result: [String: CGRect] = [:]
        for (source, identifier) in bindings {
            // Native hit rectangles may overlap a neighbour's padding by 3.5pt
            // while their ink is disjoint. Unique owned identifiers let us
            // tolerate that padding without accepting parked/duplicate slots.
            let matches = host.items.enumerated().filter { index,item in
                guard item.owner == owner,item.identifier == identifier,
                      host.overflow.map({ item.frame.intersection($0).width <= 4 }) ?? true else { return false }
                return !host.items.enumerated().contains { other,peer in
                    other != index && item.frame.intersection(peer.frame).width > 4
                        && item.frame.intersection(peer.frame).height > 1
                }
            }.map(\.element)
            if matches.count == 1 { result[source] = matches[0].frame }
        }
        return result
    }
}

final class CompatibilityMenuItems: NSObject {
    private final class Entry {
        var source: PocketItem
        let status: NSStatusItem
        var image: NSImage
        var section: MenuBarSection
        var placing = false
        init(source: PocketItem, image: NSImage, section: MenuBarSection) {
            self.source = source; self.image = image; self.section = section
            status = NSStatusBar.system.statusItem(withLength: max(24, image.size.width + 12))
            status.behavior = []
            status.autosaveName = CompatibilityMenuPolicy.identifier(source.imageIdentity)
            status.button?.imageScaling = .scaleNone
            status.button?.image = image
            status.button?.setAccessibilityIdentifier(CompatibilityMenuPolicy.identifier(source.imageIdentity))
            status.button?.setAccessibilityLabel(source.name)
            status.button?.toolTip = "\(source.name) · ⌘-drag to rearrange or keep in Pocket"
        }
    }
    private var entries: [String: Entry] = [:]
    private var observed: [String: CGRect] = [:]
    private var observedAt = Date.distantPast
    var onActivate: ((PocketItem, CGMouseButton) -> Void)?
    var captureSuspended = false
    var sources: [PocketItem] { entries.values.map(\.source) }
    var hasItems: Bool { !entries.isEmpty }
    var isPlacing: Bool { entries.values.contains { $0.placing } }
    var visibleBindings: [String: String] {
        Dictionary(uniqueKeysWithValues: entries.values.filter { $0.status.isVisible }.map { ($0.source.id, CompatibilityMenuPolicy.identifier($0.source.imageIdentity)) })
    }
    var bindings: [String: String] {
        Dictionary(uniqueKeysWithValues: entries.values.map { ($0.source.id, CompatibilityMenuPolicy.identifier($0.source.imageIdentity)) })
    }
    var diagnostics: [[String: Any]] {
        entries.values.map { ["name": $0.source.name, "bundle": $0.source.bundle,
                              "key": $0.source.imageIdentity, "identifier": CompatibilityMenuPolicy.identifier($0.source.imageIdentity),
                              "visible": $0.status.isVisible] }
    }
    @discardableResult func install(_ source: PocketItem, image: NSImage, section: MenuBarSection = .hidden, placing: Bool = false) -> Bool {
        guard Preferences.canPinPocketBundle(source.bundle), image.size.width > 0, image.size.width <= 600,
              image.size.height > 0, image.size.height <= 80 else { return false }
        if let entry = entries[source.imageIdentity] { entry.source = source; entry.placing = placing; return true }
        let entry = Entry(source: source, image: image, section: section)
        entry.placing = placing
        entry.status.button?.target = self; entry.status.button?.action = #selector(clicked(_:))
        entry.status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        entries[source.imageIdentity] = entry
        return true
    }
    func synchronize(_ sources: [PocketItem], saved: [String: Int]) {
        let wanted = sources.filter { saved[$0.imageIdentity] != nil }
        let available = Set(wanted.map(\.imageIdentity))
        for key in Array(entries.keys) where !available.contains(key) { remove(key) }
        for source in wanted {
            guard let image = PocketImageCache.shared.image(source.imageIdentity),
                  let section = MenuBarSection(rawValue: saved[source.imageIdentity]!) else { continue }
            _ = install(source, image: image, section: section)
            if let entry = entries[source.imageIdentity] {
                entry.source = source; entry.section = section
                if entry.image !== image {
                    entry.image = image; entry.status.button?.image = image
                    entry.status.length = max(24, image.size.width + 12)
                }
            }
        }
    }
    func present(active: Bool, expanded: Bool, all: Bool) {
        for entry in entries.values {
            let show = active && !captureSuspended && (entry.section == .visible || (expanded && (entry.section != .alwaysHidden || all)))
            if entry.status.isVisible != show { entry.status.isVisible = show }
        }
    }
    func rememberSections(arrow: CGRect, alwaysHidden: CGRect?, isLTR: Bool) -> [String: Int] {
        var result: [String: Int] = [:]
        for (key, entry) in entries where entry.status.isVisible && !entry.placing {
            // Backing windows can keep their original insertion position after
            // the hosted slot moves. Retain the last section if native geometry
            // is unavailable; never turn that stale window into a user drag.
            guard Date().timeIntervalSince(observedAt) < 2.5,let frame = observed[entry.source.id] else { continue }
            entry.section = MenuBarLayoutResolver.section(of: frame, separatorFrame: arrow, alwaysHiddenSeparatorFrame: alwaysHidden, isLTR: isLTR)
            result[key] = entry.section.rawValue
        }
        return result
    }
    func observe(_ frames: [String: CGRect]) { observed = frames; observedAt = Date() }
    func remove(_ key: String) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        observed[entry.source.id] = nil
        NSStatusBar.system.removeStatusItem(entry.status)
    }
    func finishPlacement(_ key: String) { entries[key]?.placing = false }
    func remove(bundle: String) { for (key, entry) in entries where entry.source.bundle == bundle { remove(key) } }
    func stop() { for key in Array(entries.keys) { remove(key) } }
    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let entry = entries.values.first(where: { $0.status.button === sender }),!entry.placing else { return }
        onActivate?(entry.source, NSApp.currentEvent?.type == .rightMouseUp ? .right : .left)
    }
    func testClickFixture() {
        guard CommandLine.arguments.contains("--test-controls") else { return }
        entries.values.first(where: { $0.source.bundle == "org.drapletqa.native" })?.status.button?.performClick(nil)
    }
    deinit { stop() }
}
