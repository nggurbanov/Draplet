import SwiftUI
import AppKit
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    let requestPermission: () -> Void
    let replaceHiddenBar: () -> Void
    let revealBoth: () -> Void
    let pause: () -> Void
    let previewAnimations: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "curtains.closed").font(.system(size: 30)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Draplet").font(.title2.bold())
                    Text("Your menu bar, on demand.").foregroundStyle(.secondary)
                }
                Spacer()
                Button(prefs.paused ? "Resume" : "Pause", action: pause)
            }.padding(24)
            Form {
                if !prefs.permissionGranted {
                    Section("Get started") {
                        Text("Draplet needs Accessibility access to read menu positions. Grant access, then return here; Draplet will pick it up automatically.")
                        Button("Grant Accessibility Access…", action: requestPermission)
                    }
                }
                if prefs.needsBackground && !prefs.backgroundPermission {
                    Section("Match your menu bar") {
                        Text("Allow screen capture so Draplet can match the actual menu-bar background and contrast. It uses only the narrow menu-bar strip, locally in memory.")
                            .font(.callout)
                        Button("Enable Background Matching…") { MenuBarBackdrop.shared.requestPermission() }
                        Text("macOS calls this Screen & System Audio Recording. Draplet does not capture audio. The left cover waits for access; native right-side hiding remains available.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if prefs.needsBackground && !prefs.backgroundReady {
                    if prefs.backgroundError.isEmpty {
                        Text("Preparing the menu-bar background…").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Background matching is unavailable. Check screen-capture access, then retry.").font(.callout)
                        HStack {
                            Button("Check Access…") { MenuBarBackdrop.shared.requestPermission() }
                            Button("Retry") { MenuBarBackdrop.shared.restart() }
                        }
                    }
                }
                Section("Animations") {
                    Toggle("Use the same animation on both sides", isOn: Binding(get: { prefs.sameAnimation }, set: { prefs.linkAnimations($0) }))
                    if prefs.sameAnimation {
                        animationPicker("Both sides", selection: $prefs.sharedAnimation, side: .left)
                    } else {
                        animationPicker("Left", selection: $prefs.leftAnimation, side: .left)
                        animationPicker("Right", selection: $prefs.rightAnimation, side: .right)
                    }
                    Picker("Timing · both sides", selection: $prefs.animationPace) {
                        ForEach(AnimationPace.allCases, id: \.self) { pace in Text(pace.title).tag(pace) }
                    }.pickerStyle(.segmented)
                    Text(prefs.animationPace == .originalLeft ? "A: 180 ms reveal · 160 ms hide. The original left-side timing." : "B: 550 ms reveal · 250 ms hide. Based on the native right-side motion measured on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Curtain opens inward toward the notch. Fade dissolves in place. The right-only Hidden Bar option keeps its native movement and timing.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Preview Both Sides", action: previewAnimations)
                }
                Section("Menu-bar background") {
                    Picker("Update", selection: $prefs.backgroundMode) {
                        ForEach(BackgroundMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                    }.pickerStyle(.segmented)
                    Text(prefs.backgroundMode == .cached
                         ? "Capture once, then refresh when the wallpaper, nearby windows or appearance changes. Best for still wallpapers."
                         : "Keep the cover moving with an animated wallpaper. Uses more energy than Cached.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Refresh Background") { MenuBarBackdrop.shared.refreshAppearance() }
                }
                Section("Icons") {
                    Toggle("Use the same icon on both sides", isOn: Binding(get: { prefs.sameIcons }, set: { prefs.linkIcons($0) }))
                    if prefs.sameIcons {
                        iconPicker("Both sides", selection: $prefs.sharedIcon, hasCustom: prefs.sharedCustomIcon != nil)
                        Button("Choose Custom Icon…") { IndicatorIcons.importIcon(prefs: prefs, side: nil) }
                        if prefs.sharedCustomIcon != nil { Button("Remove Custom Icon") { prefs.removeCustomIcon(side: nil) } }
                    } else {
                        iconPicker("Left", selection: $prefs.leftIcon, hasCustom: prefs.leftCustomIcon != nil)
                        Button("Choose Left Icon…") { IndicatorIcons.importIcon(prefs: prefs, side: .left) }
                        if prefs.leftCustomIcon != nil { Button("Remove Left Custom Icon") { prefs.removeCustomIcon(side: .left) } }
                        iconPicker("Right", selection: $prefs.rightIcon, hasCustom: prefs.rightCustomIcon != nil)
                        Button("Choose Right Icon…") { IndicatorIcons.importIcon(prefs: prefs, side: .right) }
                        if prefs.rightCustomIcon != nil { Button("Remove Right Custom Icon") { prefs.removeCustomIcon(side: .right) } }
                    }
                    Text("The Hidden Bar preset uses its original artwork, with thanks. Custom icons are saved in Draplet; a transparent PNG or PDF works best.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Reveal") {
                    Toggle("Use the same reveal action on both sides", isOn: Binding(get: { prefs.sameTrigger }, set: { prefs.linkTriggers($0) }))
                    if prefs.sameTrigger {
                        triggerPicker("Reveal on", selection: $prefs.sharedTrigger)
                    } else {
                        triggerPicker("Left", selection: $prefs.leftTrigger)
                        triggerPicker("Right", selection: $prefs.rightTrigger)
                    }
                    Text("Click an arrow to reveal or hide, or choose Hover for automatic reveal. The left arrow moves after the menus while open so every native menu stays clickable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Application menus · Left") {
                    Toggle("Hide application menus", isOn: $prefs.leftEnabled)
                    Text("The Apple logo and app name stay visible. Native menus remain fully clickable when revealed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Status icons · Right") {
                    Toggle("Manage status icons", isOn: $prefs.rightEnabled)
                    LabeledContent("Status", value: prefs.rightStatus)
                    if prefs.rightStatus.contains("Hidden Bar") {
                        Button("Quit Hidden Bar and Use Draplet", action: replaceHiddenBar)
                    }
                    Text("⌘-drag icons left of Draplet’s arrow to hide them, or right to keep them visible. Right-click the arrow for settings.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Automatically hide after leaving", isOn: $prefs.autoCollapse)
                    HStack {
                        Text("Hide after")
                        Slider(value: $prefs.collapseDelay, in: 1...30, step: 1)
                        Text("\(Int(prefs.collapseDelay)) s").monospacedDigit().frame(width: 36)
                    }.disabled(!prefs.autoCollapse)
                    Toggle("Enable an always-hidden section", isOn: $prefs.alwaysHidden)
                    if prefs.alwaysHidden {
                        Text("⌘-drag the dotted separator left of the arrow. Icons to its left stay hidden; ⌥-click the arrow to reveal everything.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Make room for icons while expanded", isOn: $prefs.fullWidth)
                    if prefs.fullWidth {
                        Text("Temporarily brings Draplet to the front for a shorter application menu.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("General") {
                    Picker("Reveal both sides", selection: $prefs.shortcut) {
                        Text("⌃⌥Space").tag(0)
                        Text("⌃⌥D").tag(1)
                        Text("⌃⌥B").tag(2)
                        Text("Disabled").tag(3)
                    }
                    Toggle("Launch Draplet at login", isOn: Binding(get: { prefs.loginEnabled }, set: { prefs.setLogin($0) }))
                    HStack {
                        Button("Reveal Both Sides", action: revealBoth)
                        Spacer()
                        Button("Quit Draplet") { NSApp.terminate(nil) }
                    }
                }
                if !prefs.error.isEmpty { Text(prefs.error).foregroundStyle(.red).font(.caption) }
                Section {
                    Text("Draplet 0.3.0 · Free and open source\nRight-side hiding and the Hidden Bar icons include work by Dwarves Foundation, under the MIT license.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        }.frame(width: 560, height: 740)
    }
    private func iconPicker(_ title: String, selection: Binding<IndicatorStyle>, hasCustom: Bool) -> some View {
        Picker(title, selection: selection) {
            ForEach(IndicatorStyle.allCases.filter { $0 != .custom || hasCustom }, id: \.self) { style in
                HStack {
                    if style != .custom { Image(nsImage: IndicatorIcons.image(style: style)).frame(width: 18) }
                    Text(style.title)
                }.tag(style)
            }
        }
    }
    private func triggerPicker(_ title: String, selection: Binding<RevealTrigger>) -> some View {
        Picker(title, selection: selection) {
            ForEach(RevealTrigger.allCases, id: \.self) { trigger in Text(trigger.title).tag(trigger) }
        }.pickerStyle(.segmented)
    }
    private func animationPicker(_ title: String, selection: Binding<BarAnimation>, side: BarSide) -> some View {
        Picker(title, selection: selection) {
            ForEach(BarAnimation.choices(for: side), id: \.self) { style in Text(style.title).tag(style) }
        }
    }
}

final class SettingsController: NSWindowController {
    init(prefs: Preferences, requestPermission: @escaping () -> Void,
         replaceHiddenBar: @escaping () -> Void, revealBoth: @escaping () -> Void, pause: @escaping () -> Void,
         previewAnimations: @escaping () -> Void) {
        let view = SettingsView(prefs: prefs, requestPermission: requestPermission,
                                replaceHiddenBar: replaceHiddenBar, revealBoth: revealBoth, pause: pause, previewAnimations: previewAnimations)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Draplet Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}
