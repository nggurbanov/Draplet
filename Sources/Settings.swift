import SwiftUI
import AppKit
import ApplicationServices
import Combine

enum SettingsPage: String, CaseIterable {
    case general = "General", appearance = "Appearance", left = "Left", right = "Right", shortcuts = "Shortcuts"
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush.pointed"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .shortcuts: return "keyboard"
        }
    }
}

final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage = .appearance
    @Published var previewExpanded = false
}

enum SettingsPalette {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.94, green: 0.49, blue: 0.30, alpha: 1)
            : NSColor(srgbRed: 0.72, green: 0.25, blue: 0.10, alpha: 1)
    })
    // Filled native segments use white labels, so their tint stays darker than
    // the accent used for text and switch states in dark appearance.
    static let controlTint = Color(red: 0.62, green: 0.20, blue: 0.075)
    static let secondary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.69, green: 0.68, blue: 0.66, alpha: 1)
            : NSColor(srgbRed: 0.39, green: 0.38, blue: 0.36, alpha: 1)
    })
    static let background = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.125, green: 0.12, blue: 0.115, alpha: 1)
            : NSColor(srgbRed: 0.975, green: 0.965, blue: 0.945, alpha: 1)
    }
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.17, green: 0.165, blue: 0.16, alpha: 1)
            : NSColor(srgbRed: 0.95, green: 0.94, blue: 0.925, alpha: 1)
    })
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsPalette.secondary).padding(.leading, 2)
            VStack(spacing: 0) { content }
                .background(SettingsPalette.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.09), lineWidth: 1))
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let detail: String?
    let content: Content
    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.detail = detail; self.content = content()
    }
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            content
        }.padding(.horizontal, 16).padding(.vertical, detail == nil ? 11 : 13).frame(minHeight: 42)
    }
}

private struct GroupDivider: View {
    var body: some View { Divider().padding(.horizontal, 14) }
}

struct SettingsView: View {
    @ObservedObject private var updates = AppUpdater.shared
    @ObservedObject var prefs: Preferences
    @ObservedObject var navigation: SettingsNavigation
    let requestPermission: () -> Void
    let replaceHiddenBar: () -> Void
    let revealBoth: () -> Void
    let pause: () -> Void
    let previewAnimations: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(navigation.page.rawValue).font(.system(size: 25, weight: .bold)).padding(.bottom, 1)
                    if let version = updates.updateVersion {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down.circle").font(.title2).foregroundStyle(SettingsPalette.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(updates.readyVersion != nil ? "Draplet \(version) is ready" : "Draplet \(version) is available").fontWeight(.semibold)
                                Text(updates.readyVersion != nil ? "Installs when you quit Draplet. Update now to get the latest fixes." : "Review the update to download and install the latest fixes.")
                                    .font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary)
                            }
                            Spacer()
                            Button(updates.actionTitle) { updates.performUpdateAction() }
                        }.padding(16).background(SettingsPalette.surface, in: RoundedRectangle(cornerRadius: 9))
                    }
                    if prefs.paused {
                        HStack(spacing: 12) {
                            Image(systemName: "pause.circle").font(.title2).foregroundStyle(SettingsPalette.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hiding is paused").fontWeight(.semibold)
                                Text("Both sides stay visible until you resume hiding.").font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary)
                            }
                            Spacer()
                            Button("Resume Hiding", action: pause)
                        }.padding(16).background(SettingsPalette.surface, in: RoundedRectangle(cornerRadius: 9))
                    }
                    if navigation.page == .appearance || navigation.page == .left || navigation.page == .right {
                        MenuBarPreview(prefs: prefs, expanded: $navigation.previewExpanded)
                    }
                    if prefs.requiresSetup || (prefs.needsBackground && !prefs.backgroundReady) {
                        permissionNotice
                    }
                    switch navigation.page {
                    case .general: general
                    case .appearance: appearance
                    case .left: left
                    case .right: right
                    case .shortcuts: shortcuts
                    }
                    if !prefs.error.isEmpty {
                        Text(prefs.error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text("Free and open source").font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary)
                Spacer()
                Button("Reveal Both Sides", action: revealBoth)
            }.padding(.horizontal, 24).padding(.vertical, 11)
        }
        .background(Color(nsColor: SettingsPalette.background))
        .font(.system(size: 14)).tint(SettingsPalette.accent)
        .frame(minWidth: 830, minHeight: 620)
    }

    private var appearance: some View {
        VStack(spacing: 20) {
            SettingsGroup("Menu-bar icons") {
                toggleRow("Use the same icon on both sides", binding: Binding(get: { prefs.sameIcons }, set: prefs.linkIcons))
                GroupDivider()
                if prefs.sameIcons { iconRow("Icon", side: nil) }
                else {
                    iconRow("Left icon", side: .left)
                    GroupDivider()
                    iconRow("Right icon", side: .right)
                }
            }
            SettingsGroup("Animations") {
                toggleRow("Use the same animation on both sides", binding: Binding(get: { prefs.sameAnimation }, set: prefs.linkAnimations))
                GroupDivider()
                if prefs.sameAnimation {
                    animationRow("Animation", selection: $prefs.sharedAnimation, side: .left)
                } else {
                    animationRow("Left animation", selection: $prefs.leftAnimation, side: .left)
                    GroupDivider()
                    animationRow("Right animation", selection: $prefs.rightAnimation, side: .right)
                }
                GroupDivider()
                SettingsRow("Speed", detail: prefs.animationPace == .originalLeft ? "180 ms reveal · 160 ms hide" : "550 ms reveal · 250 ms hide") {
                    Picker("Animation speed", selection: $prefs.animationPace) {
                        Text("Quick").tag(AnimationPace.originalLeft)
                        Text("Relaxed").tag(AnimationPace.originalRight)
                    }.labelsHidden().pickerStyle(.segmented).tint(SettingsPalette.controlTint).frame(width: 240)
                    Button("Preview Both Sides") { navigation.previewExpanded = true; previewAnimations() }
                }
            }
            SettingsGroup("Menu-bar background") {
                SettingsRow("Update", detail: prefs.backgroundMode == .cached ? "Refreshes when the wallpaper, nearby windows or appearance changes." : "Follows animated wallpapers. Uses more energy than Cached.") {
                    Picker("Background update", selection: $prefs.backgroundMode) {
                        ForEach(BackgroundMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().pickerStyle(.segmented).tint(SettingsPalette.controlTint).frame(width: 200)
                    Button("Refresh Background") { MenuBarBackdrop.shared.refreshAppearance() }
                        .disabled(!prefs.backgroundPermission)
                }
            }
            Text("The Hidden Bar icon preset uses the original artwork, with thanks. Custom icons are stored in Draplet.")
                .font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var general: some View {
        VStack(spacing: 20) {
            SettingsGroup("Behavior") {
                toggleRow("Launch Draplet at login", binding: Binding(get: { prefs.loginEnabled }, set: prefs.setLogin))
                GroupDivider()
                toggleRow("Use the same reveal action on both sides", binding: Binding(get: { prefs.sameTrigger }, set: prefs.linkTriggers))
                GroupDivider()
                if prefs.sameTrigger {
                    SettingsRow("Reveal on", detail: "Click an arrow to toggle, or hover to reveal automatically.") {
                        triggerPicker("Reveal action", selection: $prefs.sharedTrigger)
                    }
                } else {
                    SettingsRow("Reveal actions", detail: "Each side has its own action. Configure them in Left and Right.") {
                        Button("Left…") { navigation.page = .left }
                        Button("Right…") { navigation.page = .right }
                    }
                }
            }
            SettingsGroup("Updates") {
                SettingsRow("Draplet \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")", detail: updates.status) {
                    Button(updates.actionTitle) { updates.performUpdateAction() }
                        .disabled(updates.updateVersion == nil && !updates.canCheck)
                }
                GroupDivider()
                toggleRow("Automatically check for updates", detail: "Checks at launch and every hour.",
                          binding: Binding(get: { updates.automaticChecks }, set: updates.setAutomaticChecks))
                GroupDivider()
                toggleRow("Download updates in the background", detail: "Downloaded updates install when you quit Draplet. You can also update and relaunch immediately.",
                          binding: Binding(get: { updates.automaticDownloads }, set: updates.setAutomaticDownloads))
                    .disabled(!updates.automaticChecks)
            }
            permissions
            SettingsGroup("About Draplet") {
                SettingsRow("Draplet \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")", detail: "Your menu bar, on demand. Free and open source under the MIT license.") {
                    Button("Quit Draplet") { NSApp.terminate(nil) }
                }
                GroupDivider()
                Text("Right-side hiding and the Hidden Bar icons include work by Dwarves Foundation, under the MIT license.")
                    .font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
        }
    }

    private var left: some View {
        VStack(spacing: 20) {
            SettingsGroup("Application menus") {
                toggleRow("Hide application menus", detail: "Keep the Apple logo and application name visible.", binding: $prefs.leftEnabled)
                GroupDivider()
                sideTriggerRow(.left)
            }
            SettingsGroup("How it works") {
                SettingsRow("Your real menus stay available", detail: "Reveal the left side to use File, Edit and the rest as usual. The arrow moves after the last menu so you can click it again to collapse.") { EmptyView() }
                GroupDivider()
                SettingsRow("Icons and animations", detail: "Choose a shared style or configure each side independently in Appearance.") {
                    Button("Appearance…") { navigation.page = .appearance }
                }
            }
        }
    }

    private var right: some View {
        VStack(spacing: 20) {
            SettingsGroup("Status icons") {
                toggleRow("Manage status icons", binding: $prefs.rightEnabled)
                GroupDivider()
                SettingsRow("Status", detail: "⌘-drag icons left of Draplet’s arrow to hide them, or right to keep them visible.") {
                    Text(prefs.rightStatus).foregroundStyle(SettingsPalette.secondary)
                    if prefs.rightStatus.contains("Hidden Bar") { Button("Use Draplet", action: replaceHiddenBar) }
                }
                GroupDivider()
                sideTriggerRow(.right)
            }
            SettingsGroup("Auto-hide") {
                toggleRow("Automatically hide after leaving", binding: $prefs.autoCollapse)
                if prefs.autoCollapse {
                    GroupDivider()
                    SettingsRow("Hide after") {
                        Slider(value: $prefs.collapseDelay, in: 1...30, step: 1).frame(width: 260).accessibilityLabel("Auto-hide delay")
                        Text("\(Int(prefs.collapseDelay)) s").monospacedDigit().frame(width: 36, alignment: .trailing)
                    }
                }
            }
            SettingsGroup("Advanced") {
                toggleRow("Enable an always-hidden section", detail: "⌘-drag the dotted separator left of the arrow. ⌥-click the arrow to reveal everything.", binding: $prefs.alwaysHidden)
                GroupDivider()
                toggleRow("Make room for icons while expanded", detail: "Temporarily brings Draplet to the front for a shorter application menu.", binding: $prefs.fullWidth)
            }
        }
    }

    private var shortcuts: some View {
        VStack(spacing: 20) {
            SettingsGroup("Keyboard shortcut") {
                SettingsRow("Reveal both sides", detail: "Open application menus and hidden status icons together.") {
                    Picker("Reveal both sides shortcut", selection: $prefs.shortcut) {
                        Text("⌃⌥Space").tag(0); Text("⌃⌥D").tag(1); Text("⌃⌥B").tag(2); Text("Disabled").tag(3)
                    }.labelsHidden().frame(width: 200)
                }
            }
            SettingsGroup("Menu-bar controls") {
                SettingsRow("Arrange icons", detail: "Hold Command and drag a status icon across Draplet’s arrow.") { Text("⌘ Drag").foregroundStyle(SettingsPalette.secondary) }
                GroupDivider()
                SettingsRow("Reveal every section", detail: "Option-click the right arrow, including the always-hidden section.") { Text("⌥ Click").foregroundStyle(SettingsPalette.secondary) }
                GroupDivider()
                SettingsRow("Open Settings", detail: "Right-click either Draplet arrow.") { Image(systemName: "computermouse").foregroundStyle(SettingsPalette.secondary) }
            }
        }
    }

    private var permissions: some View {
        SettingsGroup("Permissions") {
            SettingsRow("Accessibility", detail: "Reads menu and icon positions so Draplet knows what to hide.") {
                if prefs.permissionGranted { Label("Allowed", systemImage: "checkmark").foregroundStyle(SettingsPalette.secondary) }
                else { Button("Grant Access…", action: requestPermission) }
            }
            GroupDivider()
            SettingsRow("Background matching", detail: "Reads only the menu-bar strip locally in memory. No audio is captured.") {
                if prefs.backgroundPermission { Label("Allowed", systemImage: "checkmark").foregroundStyle(SettingsPalette.secondary) }
                else { Button("Enable…") { MenuBarBackdrop.shared.requestPermission() } }
            }
        }
    }
    private var permissionNotice: some View {
        SettingsGroup("Setup") {
            if !prefs.permissionGranted {
                SettingsRow("Accessibility access needed", detail: "Allow Draplet to read menu positions. It will activate when you return.") { Button("Grant Access…", action: requestPermission) }
            } else if !prefs.backgroundPermission {
                SettingsRow("Enable background matching", detail: "macOS calls this Screen & System Audio Recording. Draplet captures no audio.") { Button("Enable…") { MenuBarBackdrop.shared.requestPermission() } }
            } else {
                SettingsRow(prefs.backgroundError.isEmpty ? "Preparing the menu-bar background…" : "Background matching is unavailable", detail: prefs.backgroundError.isEmpty ? nil : prefs.backgroundError) {
                    if prefs.backgroundError.isEmpty { ProgressView().controlSize(.small) }
                    else {
                        Button("Check Access…") { MenuBarBackdrop.shared.requestPermission() }
                        Button("Retry") { MenuBarBackdrop.shared.restart() }
                    }
                }
            }
        }
    }
    private func toggleRow(_ title: String, detail: String? = nil, binding: Binding<Bool>) -> some View {
        SettingsRow(title, detail: detail) { Toggle(title, isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.regular) }
    }
    private func sideTriggerRow(_ side: BarSide) -> some View {
        SettingsRow("Reveal on", detail: prefs.sameTrigger ? "Linked to both sides in General." : nil) {
            if prefs.sameTrigger {
                Text(prefs.trigger(for: side).title).foregroundStyle(SettingsPalette.secondary)
                Button("Change…") { navigation.page = .general }
            } else { triggerPicker("Reveal action", selection: side == .left ? $prefs.leftTrigger : $prefs.rightTrigger) }
        }
    }
    private func triggerPicker(_ title: String, selection: Binding<RevealTrigger>) -> some View {
        Picker(title, selection: selection) {
            ForEach(RevealTrigger.allCases, id: \.self) { Text($0.title).tag($0) }
        }.labelsHidden().pickerStyle(.segmented).tint(SettingsPalette.controlTint).frame(width: 240)
    }
    private func animationRow(_ title: String, selection: Binding<BarAnimation>, side: BarSide) -> some View {
        SettingsRow(title) {
            Picker(title, selection: selection) {
                ForEach(BarAnimation.choices(for: side), id: \.self) { Text($0.title).tag($0) }
            }.labelsHidden().pickerStyle(.segmented).tint(SettingsPalette.controlTint).frame(width: side == .right ? 330 : 240)
        }
    }
    private func iconRow(_ title: String, side: BarSide?) -> some View {
        let selection = side == nil ? $prefs.sharedIcon : (side == .left ? $prefs.leftIcon : $prefs.rightIcon)
        let data = side == nil ? prefs.sharedCustomIcon : prefs.customIcon(for: side!)
        return SettingsRow(title) {
            IconPicker(title: title, selection: selection, data: data, side: side ?? .left).frame(width: 190)
            HStack(spacing: 18) {
                Image(nsImage: IndicatorIcons.image(style: selection.wrappedValue, data: data, side: .left))
                Image(nsImage: IndicatorIcons.image(style: selection.wrappedValue, data: data, side: .right))
            }.frame(width: 70, height: 28).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5)).accessibilityLabel("Selected icon preview")
            Button("Import Custom…") { IndicatorIcons.importIcon(prefs: prefs, side: side) }
            if data != nil { Button { prefs.removeCustomIcon(side: side) } label: { Image(systemName: "trash") }.help("Remove custom icon").accessibilityLabel("Remove custom icon") }
        }
    }
}

// NSMenuItem.image keeps the artwork visible both in the open menu and in the
// selected item. SwiftUI's macOS Picker drops images from some custom labels.
private struct IconPicker: NSViewRepresentable {
    let title: String
    @Binding var selection: IndicatorStyle
    let data: Data?
    let side: BarSide
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.target = context.coordinator; button.action = #selector(Coordinator.select(_:))
        button.setAccessibilityLabel(title)
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.selection = $selection
        let styles = IndicatorStyle.allCases.filter { $0 != .custom || data != nil }
        // Background and right-side status changes also refresh this view.
        // Leave a menu being tracked intact when its artwork has not changed.
        if button.numberOfItems != styles.count || coordinator.data != data || coordinator.side != side {
            button.removeAllItems()
            for style in styles {
                let item = NSMenuItem(title: style.title, action: nil, keyEquivalent: "")
                item.representedObject = style.rawValue
                item.image = IndicatorIcons.image(style: style, data: data, side: side)
                button.menu?.addItem(item)
            }
            coordinator.data = data; coordinator.side = side
        }
        if let item = button.itemArray.first(where: { $0.representedObject as? String == selection.rawValue }),
           button.selectedItem !== item {
            button.select(item)
        }
    }
    final class Coordinator: NSObject {
        var selection: Binding<IndicatorStyle>?
        var data: Data?
        var side: BarSide?
        @objc func select(_ sender: NSPopUpButton) {
            guard let raw = sender.selectedItem?.representedObject as? String,
                  let style = IndicatorStyle(rawValue: raw) else { return }
            selection?.wrappedValue = style
        }
    }
}

private struct MenuBarPreview: View {
    @ObservedObject var prefs: Preferences
    @Binding var expanded: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Menu-bar preview").font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsPalette.secondary)
                Spacer()
                Text(expanded ? "Expanded" : "Collapsed").font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary)
            }.padding(.horizontal, 2)
            HStack(spacing: 12) {
                Image(systemName: "apple.logo").font(.system(size: 17))
                Text("Finder").fontWeight(.semibold)
                if expanded || !prefs.leftEnabled {
                    Text("File   Edit   View   Go   Window   Help").font(.system(size: 11)).lineLimit(1)
                }
                previewButton(.left)
                Spacer(minLength: 72)
                if expanded || !prefs.rightEnabled {
                    Image(systemName: "magnifyingglass"); Image(systemName: "music.note")
                }
                previewButton(.right)
                Image(systemName: "wifi"); Image(systemName: "battery.100")
                Text("9:41").font(.system(size: 11)).monospacedDigit()
            }.frame(height: 38).padding(.horizontal, 14)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                        .fill(.black).frame(width: 58, height: 13).accessibilityHidden(true)
                }
                .background(SettingsPalette.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))
            Text("Click a preview arrow to see the layout. Preview Both Sides tests the real menu bar.")
                .font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary)
        }.accessibilityElement(children: .contain)
    }
    private func previewButton(_ side: BarSide) -> some View {
        Button { expanded.toggle() } label: {
            Image(nsImage: IndicatorIcons.image(for: side, expanded: expanded, prefs: prefs)).frame(width: 20, height: 28)
        }.buttonStyle(.plain).help(expanded ? "Collapse preview" : "Expand preview")
            .accessibilityLabel("\(side == .left ? "Left" : "Right") preview arrow")
    }
}

private struct SettingsToolbarButton: View {
    @ObservedObject var navigation: SettingsNavigation
    let page: SettingsPage
    var body: some View {
        Button { navigation.page = page } label: {
            VStack(spacing: 5) {
                Image(systemName: page.symbol).font(.system(size: 20, weight: .regular)).frame(height: 22)
                Text(page.rawValue).font(.system(size: 12))
            }.frame(width: page == .appearance ? 88 : 64, height: 42)
                .foregroundStyle(navigation.page == page ? SettingsPalette.accent : Color.primary)
                .background(navigation.page == page ? SettingsPalette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(page.rawValue)
            .accessibilityAddTraits(navigation.page == page ? .isSelected : [])
            // The unified toolbar caps custom views at 54 points. Keep the
            // padding inside that height, otherwise AppKit clips it away.
            .padding(.vertical, 6)
    }
}

private struct SettingsPauseButton: View {
    @ObservedObject var prefs: Preferences
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label(prefs.paused ? "Resume Hiding" : "Pause Hiding", systemImage: prefs.paused ? "play.fill" : "pause.fill") }
            .labelStyle(.titleAndIcon).controlSize(.regular).tint(SettingsPalette.accent)
            .help(prefs.paused ? "Resume hiding menus and icons with your usual settings." : "Reveal both sides and keep them visible until you resume hiding.")
    }
}

final class SettingsController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    let navigation = SettingsNavigation()
    private let prefs: Preferences
    private let pause: () -> Void
    private let requestPermission: () -> Void
    private let replaceHiddenBar: () -> Void
    private let revealBoth: () -> Void
    private let previewAnimations: () -> Void
    init(prefs: Preferences, requestPermission: @escaping () -> Void,
         replaceHiddenBar: @escaping () -> Void, revealBoth: @escaping () -> Void, pause: @escaping () -> Void,
         previewAnimations: @escaping () -> Void) {
        self.prefs = prefs; self.pause = pause
        self.requestPermission = requestPermission; self.replaceHiddenBar = replaceHiddenBar
        self.revealBoth = revealBoth; self.previewAnimations = previewAnimations
        super.init(window: nil)
    }
    // Ordinary background ticks may inspect `window`; they must not construct
    // an entire SwiftUI Settings hierarchy before the user opens it.
    override func loadWindow() {}
    func prepareWindow() {
        guard window == nil else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 710), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        self.window = window
        let view = SettingsView(prefs: prefs, navigation: navigation, requestPermission: requestPermission,
                                replaceHiddenBar: replaceHiddenBar, revealBoth: revealBoth, pause: pause, previewAnimations: previewAnimations)
        window.contentViewController = NSHostingController(rootView: view)
        window.title = "Draplet Settings"
        window.delegate = self
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.backgroundColor = SettingsPalette.background
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "Draplet.Settings")
        toolbar.delegate = self; toolbar.displayMode = .iconAndLabel; toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.minSize = NSSize(width: 850, height: 700)
        window.setContentSize(NSSize(width: 940, height: 710))
        window.isReleasedWhenClosed = false; window.center()
        window.setFrameAutosaveName("Draplet.Settings")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [NSToolbarItem.Identifier("brand"), .flexibleSpace] + SettingsPage.allCases.map { NSToolbarItem.Identifier($0.rawValue) } + [.flexibleSpace, NSToolbarItem.Identifier("pause")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        if identifier.rawValue == "brand" {
            let brand = HStack(spacing: 9) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage()).resizable().frame(width: 32, height: 32)
                Text("Draplet Settings").font(.system(size: 16, weight: .semibold))
            }.frame(width: 180, height: 54)
            item.view = NSHostingView(rootView: brand)
        } else if identifier.rawValue == "pause" {
            item.view = NSHostingView(rootView: SettingsPauseButton(prefs: prefs, action: pause).frame(width: 138, height: 54))
        } else if let page = SettingsPage(rawValue: identifier.rawValue) {
            item.view = NSHostingView(rootView: SettingsToolbarButton(navigation: navigation, page: page))
        } else { return nil }
        item.isBordered = false
        item.label = ""; item.paletteLabel = identifier.rawValue
        return item
    }
    func show() {
        prepareWindow()
        NSApp.setActivationPolicy(.regular)
        showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Keep navigation/preferences, release hidden hosting views and toolbar.
        if let closed = notification.object as? NSWindow {
            closed.contentViewController = nil; closed.toolbar = nil
        }
        window = nil
    }
}
