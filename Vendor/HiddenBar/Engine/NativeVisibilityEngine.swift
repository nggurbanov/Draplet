//
//  NativeVisibilityEngine.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// macOS 27 hiding for the direct (non-App Store) build. Instead of inflating the
// separator, which macOS 27 ejects from the layout once it is too wide (#360),
// this reads which apps the user placed in each section and asks macOS to show
// only the allowed ones through the menu-bar visibility restriction behind
// assessment mode. macOS then hides the rest and reflows the bar itself, so the
// result does not depend on display width, the notch or the frontmost app's menus.
//
// The arrow is the boundary: apps left of it (LTR) are hidden, apps right of it
// stay visible. The regular separator is not needed and is taken out of the
// bar; even at zero width macOS keeps a gap for it. The always-hidden
// separator, when enabled, marks the third section; it shows while expanded so
// it can be ⌘-dragged, and drops to zero width while collapsed, where macOS
// has already removed everything it would separate. It keeps its slot because
// its position is what defines that section.
//
// Limits, all from what macOS 27 exposes:
// - Hiding is per app: an app with several icons hides or shows them together
//   (the most visible section wins).
// - macOS's own items (clock, Wi-Fi, Control Center...) are always kept visible:
//   Accessibility cannot tell them apart, so they cannot be mapped to sections.
// - Sections are read only while nothing is hidden, because hidden items report
//   stale positions. They are re-read on the next collapse from an unrestricted
//   bar, so an app launched while collapsed stays hidden until then, the same
//   as a new icon landing in the hidden section under the old mechanism.
final class NativeVisibilityEngine: MenuBarEngine {
    // System item identifiers to keep visible. Unknown identifiers are ignored,
    // so the range covers items a given Mac does not have (0-63 checked on 27.0).
    static let systemItemsToKeep = Array(0..<64)

    private weak var items: MenuBarItemProvider?
    private let inventory: MenuBarInventoryProviding
    private let visibility: NativeVisibilityProviding
    private let ownBundleIdentifier: String?
    private let itemFrame: (NSStatusItem) -> CGRect?
    private let isLTR: () -> Bool

    private let expandedLength: CGFloat = 20

    // .calibrating stands for "an activation is in flight".
    private(set) var state: MenuBarEngineState = .expanded
    private(set) var layout: MenuBarLayout?
    private(set) var layoutInventory: [MenuBarInventoryItem] = []

    private var captureRestoreState: MenuBarEngineState?
    private var pocketOnlyBundles = Set<String>()
    private var pocketOwners: [String:[String]] = [:]
    private var placementRevision = 0
    private var placementWaiters: [() -> Void] = []
    private var assertion: NativeVisibilityAssertion?
    var hasVisibilityRestriction: Bool { assertion != nil }
    var pocketCaptureRestoresRestriction: Bool {
        if captureRestoreState == .collapsed { return true }
        return (!pocketOnlyBundles.isEmpty && !pocketOwners.isEmpty)
            || (alwaysHiddenEnabled && alwaysHiddenSeparatorHidden)
    }
    // Bumped whenever a pending activation must no longer win (an expand, a newer
    // activation); a late success is then invalidated straight away.
    private var generation = 0
    private var lastUnavailableReason: String?

    private var alwaysHiddenEnabled = false
    private var alwaysHiddenSeparatorHidden = false

    init(items: MenuBarItemProvider,
         inventory: MenuBarInventoryProviding = AccessibilityMenuBarInventory(),
         visibility: NativeVisibilityProviding = NativeVisibilityBridge(),
         ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
         itemFrame: ((NSStatusItem) -> CGRect?)? = nil,
         isLTR: @escaping () -> Bool = { Constant.isUsingLTRLanguage }) {
        self.items = items
        self.inventory = inventory
        self.visibility = visibility
        self.ownBundleIdentifier = ownBundleIdentifier
        self.itemFrame = itemFrame ?? { [weak items] in items?.statusItemFrame($0) }
        self.isLTR = isLTR
        items.separatorItem.isVisible = false
    }

    func collapse(completion: @escaping (CollapseResult) -> Void) {
        switch state {
        case .collapsed:
            return completion(.collapsed)
        case .calibrating:
            // The activation in flight answers the request that started it.
            return
        case .expanded, .unavailable:
            break
        }
        setSeparatorsVisible(true)

        guard visibility.isAvailable else {
            logUnavailableOnce("the native menu-bar visibility API is not available in this build or on this macOS")
            state = .unavailable
            return completion(.unavailable)
        }
        guard inventory.isAuthorized else {
            // Without Accessibility the sections cannot be read, and guessing would
            // hide icons the user kept visible. Not latched: it works as soon as
            // the permission is granted.
            inventory.requestAuthorization()
            logUnavailableOnce("Accessibility permission is needed to read the menu-bar sections")
            return completion(.unavailable)
        }
        state = .calibrating
        withLayout { [weak self] layout in
            guard let self = self else { return }
            guard let layout = layout else {
                self.logUnavailableOnce("the menu-bar sections could not be read; icons remain visible")
                self.state = .expanded
                return completion(.unavailable)
            }
            self.activate(allowing: layout.bundles(in: [.visible])) { [weak self] succeeded in
                guard let self = self else { return }
                self.state = succeeded ? .collapsed : .expanded
                if succeeded {
                    self.setSeparatorsVisible(false)
                }
                completion(succeeded ? .collapsed : .unavailable)
            }
        }
    }

    func expand() {
        expand { _ in }
    }

    func expand(completion: @escaping (Bool) -> Void) {
        captureRestoreState = nil
        setSeparatorsVisible(true)
        state = .expanded
        applyExpandedPresentation(completion:completion)
    }

    func updateAlwaysHiddenSection(enabled: Bool, separatorHidden: Bool) {
        guard enabled != alwaysHiddenEnabled || separatorHidden != alwaysHiddenSeparatorHidden else { return }
        alwaysHiddenEnabled = enabled
        alwaysHiddenSeparatorHidden = separatorHidden
        if state != .collapsed {
            setSeparatorsVisible(true)
        }
        if state == .expanded {
            applyExpandedPresentation()
        }
    }

    // Native hiding does not depend on display geometry, so only drop the cached
    // sections; the next read from an unrestricted bar replaces them.
    func invalidateLayout() {
        if assertion == nil {
            layout = nil
        }
    }

    // Expanded shows the hidden section; the always-hidden section stays hidden
    // while "hide separators" is on, otherwise everything is revealed by dropping
    // the restriction altogether.
    private func applyExpandedPresentation(completion: @escaping (Bool) -> Void = { _ in }) {
        if !pocketOnlyBundles.isEmpty, !pocketOwners.isEmpty, visibility.isAvailable, inventory.isAuthorized {
            // A display/backdrop restart can expand while placement is still
            // reading an unrestricted bar. Do not supersede that read with a
            // pin restriction and leave collapse with no original section map.
            if layout == nil {
                if assertion != nil { releaseAssertion() }
                withLayout { [weak self] layout in
                    guard let self else { completion(false); return }
                    guard layout != nil else {
                        self.releaseAssertion(); completion(false); return
                    }
                    self.applyExpandedPresentation(completion:completion)
                }
                return
            }
            let excluded = alwaysHiddenEnabled && alwaysHiddenSeparatorHidden ? Set(layout?.bundles(in: [.alwaysHidden]) ?? []) : []
            let allowed = pocketOwners.keys.filter { !excluded.contains($0) }.sorted()
            activate(allowing: allowed, onSuperseded:{ completion(false) }, completion:completion)
            return
        }
        guard alwaysHiddenEnabled && alwaysHiddenSeparatorHidden, visibility.isAvailable, inventory.isAuthorized else {
            releaseAssertion(); completion(true); return
        }
        withLayout { [weak self] layout in
            guard let self = self else { return }
            guard let layout = layout else {
                self.releaseAssertion(); completion(false); return
            }
            self.activate(allowing: layout.bundles(in: [.visible, .hidden]), onSuperseded:{ completion(false) }, completion:completion)
        }
    }

    // The sections as the user arranged them. Read fresh only from an
    // unrestricted bar; while a restriction is active the cached ones stand in.
    // Superseded by any later expand or activation, like an activation is.
    private func withLayout(_ body: @escaping (MenuBarLayout?) -> Void) {
        if assertion != nil {
            return body(layout)
        }
        guard let arrow = items?.toggleItem else { return body(nil) }
        generation += 1
        let generation = self.generation
        inventory.snapshot { [weak self] inventory in
            guard let self = self, generation == self.generation else { return }
            // A timeout or transient AX failure can yield no items. An empty
            // allow-list would hide every third-party icon, including visible ones.
            guard !inventory.isEmpty else { self.layout = nil; body(nil); return }
            // Initial status-item hosting can finish while Accessibility walks
            // the other publishers. Compare that inventory with the settled
            // boundary, not the arrow's earlier placeholder/backing position.
            guard let boundary = self.itemFrame(arrow) else { self.layout = nil;body(nil);return }
            let alwaysHiddenFrame = self.alwaysHiddenEnabled ? self.items?.alwaysHiddenItem.flatMap(self.itemFrame) : nil
            let isLTR = self.isLTR()
            self.layoutInventory = inventory
            let layout = MenuBarLayoutResolver.resolve(inventory: inventory,
                                                       separatorFrame: boundary,
                                                       alwaysHiddenSeparatorFrame: alwaysHiddenFrame,
                                                       isLTR: isLTR,
                                                       excludingBundle: self.ownBundleIdentifier)
            NSLog("NativeVisibility: arrow at x=\(boundary.midX); visible \(layout.bundles(in: [.visible])), hidden \(layout.bundles(in: [.hidden])), always hidden \(layout.bundles(in: [.alwaysHidden]))")
            self.layout = layout
            body(layout)
        }
    }

    // Activates the new restriction before dropping the old one, so switching
    // between collapsed and expanded never flashes the whole bar visible.
    private func activate(allowing bundles: [String], includingPocket: Bool = false, preservingSystemItems: Bool = false, onSuperseded: @escaping () -> Void = {}, completion: @escaping (Bool) -> Void) {
        generation += 1
        let generation = self.generation
        let placement = placementRevision
        let pinnedIdentifiers = Set(pocketOnlyBundles.flatMap { pocketOwners[$0] ?? [$0] })
        let allowed = (ownBundleIdentifier.map { [$0] } ?? []) + Array(Set(bundles.flatMap { pocketOwners[$0] ?? [$0] })).filter {
            includingPocket || !pinnedIdentifiers.contains($0)
        }.sorted()
        // Capture exposes one app behind a frozen strip. Temporarily make room
        // by hiding system extras too; otherwise later siblings can be parked
        // under the native overflow button and get photographed as that button.
        visibility.activate(allowedSystemItems: includingPocket && !preservingSystemItems ? [] : Self.systemItemsToKeep,
                            allowedBundleIdentifiers: allowed) { [weak self] result in
            guard let self = self, generation == self.generation else {
                if case .success(let stale) = result { stale.invalidate() }
                onSuperseded()
                return
            }
            if placement != self.placementRevision {
                if case .success(let stale) = result { stale.invalidate() }
                self.activate(allowing: bundles, includingPocket: includingPocket, preservingSystemItems:preservingSystemItems, onSuperseded: onSuperseded, completion: completion)
                return
            }
            switch result {
            case .success(let newAssertion):
                let old = self.assertion
                self.assertion = newAssertion
                old?.invalidate()
                completion(true)
                if generation == self.generation { self.finishPlacementWaiters() }
            case .failure(let error):
                // Fail open: never leave icons hidden after an error.
                NSLog("NativeVisibility: activation failed: \(error.localizedDescription)")
                self.releaseAssertion()
                completion(false)
            }
        }
    }

    // Draplet addition (2026-10-18): a temporary per-bundle exposure for the
    // pocket. Keep the original layout and collapsed state; never classify the
    // temporary reflow as a user rearrangement. nil restores the visible section.
    func showPocketBundle(_ bundle: String?, completion: @escaping (Bool) -> Void) {
        guard state == .collapsed, layout != nil else { completion(false); return }
        showPocketBundles(bundle.map { [$0] } ?? [], completion: completion)
    }

    func showPocketBundles(_ selected: [String], completion: @escaping (Bool) -> Void) {
        guard state == .collapsed, let layout else { completion(false); return }
        let bundles = Array(Set(layout.bundles(in: [.visible]) + selected)).sorted()
        activate(allowing: bundles, onSuperseded: { completion(false) }) { [weak self] success in
            if !success { self?.state = .expanded }
            completion(success)
        }
    }

    // Capture borrows visibility without changing the user's reveal state/layout.
    func stagePocketCapture(_ identifiers: [String], preservingVisible: Bool = false, completion: @escaping (Bool) -> Void) {
        guard state == .expanded || state == .collapsed else { completion(false); return }
        if captureRestoreState == nil { captureRestoreState = state }
        let visible = preservingVisible ? layout?.bundles(in:[.visible]) ?? [] : []
        activate(allowing: identifiers+visible, includingPocket: true, preservingSystemItems:preservingVisible, onSuperseded: { completion(false) }, completion: completion)
    }
    // Some third-party status providers disappear under an allow-list even
    // when their published identifiers are allowed. A bounded capture fallback
    // can borrow the unrestricted bar behind the existing one-shot shield.
    // Keep the original sections and restore state exactly as for staged capture.
    func stageUnrestrictedPocketCapture() -> Bool {
        guard state == .expanded || state == .collapsed, visibility.isAvailable, inventory.isAuthorized else { return false }
        if captureRestoreState == nil { captureRestoreState = state }
        releaseAssertion()
        return true
    }
    // The explicit Pocket destination is independent of the user's native
    // divider layout. Capture may borrow a pinned owner, then restores this policy.
    func updatePocketPlacement(pinned: Set<String>, owners: [String:[String]], completion: @escaping () -> Void = {}) {
        guard pinned != pocketOnlyBundles || owners != pocketOwners else {
            if placementWaiters.isEmpty { completion() }
            else { placementWaiters.append(completion) }
            return
        }
        placementWaiters.append(completion)
        pocketOnlyBundles = pinned; pocketOwners = owners
        placementRevision += 1
        // Capture owns a temporary layout until finishPocketCapture. An inventory
        // refresh must not replace that exposure halfway through a screenshot.
        guard captureRestoreState == nil else { return }
        switch state {
        case .expanded:
            if !pinned.isEmpty, layout == nil, assertion == nil {
                withLayout { [weak self] _ in self?.applyExpandedPresentation() }
            } else { applyExpandedPresentation() }
        case .collapsed:
            if let layout {
                activate(allowing: layout.bundles(in: [.visible])) { [weak self] success in
                    if !success { self?.state = .expanded }
                }
            } else { finishPlacementWaiters() }
        case .calibrating: break // The in-flight activation retries its placement revision.
        case .unavailable: finishPlacementWaiters()
        }
    }
    func finishPocketCapture(completion: @escaping (Bool) -> Void = { _ in }) {
        guard let previous = captureRestoreState else { completion(true); return }
        captureRestoreState = nil
        if previous == .expanded { applyExpandedPresentation(completion:completion) }
        else if let layout {
            activate(allowing: layout.bundles(in: [.visible]), onSuperseded:{ completion(false) }) { [weak self] success in
                if !success { self?.state = .expanded }
                completion(success)
            }
        } else { releaseAssertion(); state = .expanded; completion(false) }
    }

    // The always-hidden separator goes to zero width rather than isVisible =
    // false, which would make macOS forget where the user placed it.
    private func setSeparatorsVisible(_ visible: Bool) {
        items?.separatorItem.isVisible = false
        items?.alwaysHiddenItem?.length = visible && alwaysHiddenEnabled ? expandedLength : 0
    }

    // Any arrangement works: whatever sits left of the arrow is the hidden section.
    var isArrangementValid: Bool {
        return true
    }

    var isAlwaysHiddenSeparatorPlaced: Bool {
        return MenuBarOrder.isItem(items?.alwaysHiddenItem, onHiddenSideOf: items?.toggleItem)
    }

    private func releaseAssertion() {
        generation += 1
        assertion?.invalidate()
        assertion = nil
        finishPlacementWaiters()
    }
    private func finishPlacementWaiters() {
        let waiters = placementWaiters; placementWaiters = []
        waiters.forEach { $0() }
    }

    // Logged when the reason changes, so a retried collapse does not spam.
    private func logUnavailableOnce(_ reason: String) {
        guard reason != lastUnavailableReason else { return }
        lastUnavailableReason = reason
        NSLog("NativeVisibility: hiding unavailable: \(reason)")
    }
}
