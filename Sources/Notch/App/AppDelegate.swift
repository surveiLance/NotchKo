import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var power: PowerMonitor!
    private var bluetooth: BluetoothMonitor!
    private var rebuildWork: DispatchWorkItem?

    let services = Services()
    /// One panel per display: the real notch on the MacBook, a virtual one elsewhere.
    private(set) var panels: [NotchPanel] = []
    private var states: [NotchState] { panels.map(\.state) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupEditMenu()
        setupStatusItem()
        #if DEBUG
        setupDebugHooks()
        #endif
        rebuildPanels()

        // First run from /Applications: launch at login by default (menu can turn it off).
        let firstRun = "didRegisterLoginItem"
        if !UserDefaults.standard.bool(forKey: firstRun), Bundle.main.bundlePath.hasPrefix("/Applications/") {
            LoginItem.setEnabled(true)
            UserDefaults.standard.set(true, forKey: firstRun)
        }

        // Login "wake up" — give the desktop a beat to settle first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.states.forEach { $0.playGreeting() }
        }

        services.clock.onTimerFired = { [weak self] in self?.states.forEach { $0.timerFired() } }
        setupSystemNotices()

        // ⌃⌥N toggles the notch on whichever display the mouse is on.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.panelUnderMouse?.state.toggle()
        }

        // Switching Spaces / entering a fullscreen app: make sure panels come along.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panels.forEach { $0.reassert() } }
        }

        // Displays plugged/unplugged, lid closed, resolution changed → rebuild the set.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
    }

    // MARK: - Panels

    private func rebuildPanels() {
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map { screen in
            let panel = NotchPanel(state: NotchState(services: services), screen: screen)
            panel.show()
            return panel
        }
    }

    /// Screen changes arrive in bursts; settle before rebuilding. A second
    /// pass follows because AppKit can still report the previous frame and
    /// safe-area insets when the first one runs (resolution changes, see #1).
    private func scheduleRebuild() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let current = Set(self.panels.map(\.displayID))
            if current == Set(NSScreen.screens.map(\.displayID)) {
                self.panels.forEach { $0.relayout() }   // same displays, new geometry
            } else {
                self.rebuildPanels()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.panels.forEach { $0.relayout() }
            }
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private var panelUnderMouse: NotchPanel? {
        let p = NSEvent.mouseLocation
        return panels.first { NSMouseInRect(p, $0.currentScreen.frame, false) } ?? panels.first
    }

    // MARK: - System notices

    /// Charger and Bluetooth → pops in every pill.
    private func setupSystemNotices() {
        power = PowerMonitor()
        power.onCharging = { [weak self] charging, pct in
            self?.states.forEach { $0.show(.power(charging: charging, percent: pct)) }
            self?.services.devices.refresh()
        }
        power.onLowBattery = { [weak self] pct in
            self?.states.forEach { $0.show(.lowBattery(percent: pct)) }
            NSSound(named: "Sosumi")?.play()
        }

        bluetooth = BluetoothMonitor()
        bluetooth.onChange = { [weak self] name, connected, isAudio in
            self?.states.forEach { $0.show(.bluetooth(name: name, connected: connected, isAudio: isAudio)) }
            // system_profiler lags the connect event slightly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.services.devices.refresh() }
        }
    }

    // MARK: - Edit menu

    /// Never shown (we're a background app), but ⌘A/⌘C/⌘V/⌘X/⌘Z only work in
    /// text fields if an Edit menu with the standard items exists.
    private func setupEditMenu() {
        let main = NSMenu()
        let edit = NSMenuItem()
        main.addItem(edit)
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = menu
        NSApp.mainMenu = main
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "macbook.gen2", accessibilityDescription: "Notch")
        }
        let menu = NSMenu()
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        let toggle = NSMenuItem(title: "Toggle Notch", action: #selector(toggleNotch), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Notch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleNotch() { panelUnderMouse?.state.toggle() }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        sender.state = LoginItem.isEnabled ? .on : .off
    }

    // MARK: - Debug

    #if DEBUG
    /// Lets a script drive the UI without a cursor — see scripts/debug.sh.
    /// Acts on every panel; "add"/"preview" go through the shared services.
    private func setupDebugHooks() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.lance.notch.debug"), object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let action = note.userInfo?["action"] as? String else { return }
                let path = note.userInfo?["path"] as? String
                for state in self.states {
                    switch action {
                    case "expand":   if !state.isExpanded { state.toggle() }
                    case "collapse": state.collapseNow()
                    case "toggle":   state.toggle()
                    case "home":     state.tab = .home
                    case "music":    state.tab = .music
                    case "shelf":    state.tab = .shelf
                    case "clock":    state.tab = .clock
                    case "devices":  state.tab = .devices
                    case "prompter": state.tab = .prompter
                    case "tools":    state.tab = .tools
                    case "mirror":   state.tab = .mirror
                    case "prompt":   state.startPrompter()
                    case "unprompt": state.stopPrompter(toEditor: false)
                    case "drag":     state.setDragTargeted(.shelf)
                    case "undrag":   state.setDragTargeted(nil)
                    case "greet":    state.playGreeting()
                    case "power":    state.show(.power(charging: true, percent: 82))
                    case "bt":       state.show(.bluetooth(name: "Lance's AirPods Pro", connected: true, isAudio: true))
                    case "preview":  if let f = self.services.shelf.items.last { state.preview([f.url]) }
                    default: break
                    }
                }
                switch action {
                case "selectall": self.services.shelf.toggleSelectAll()
                case "sw":        self.services.clock.stopwatchToggle()
                case "timer":     self.services.clock.timerToggle()
                case "timerset":  if let p = path, let v = Double(p) { self.services.clock.timerSet(v) }
                case "add":       if let p = path { self.services.shelf.add([URL(fileURLWithPath: p)]) }
                case "script":    if let p = path { self.services.prompter.script = p }
                case "cutout", "topng":
                    if let p = path {
                        Task {
                            let url = URL(fileURLWithPath: p)
                            let out = action == "cutout" ? await ImageTools.removeBackground(url) : await ImageTools.convert(url, to: .png)
                            if let out { self.services.shelf.add([out]) }
                            NSLog("debug \(action): \(out?.path ?? "nil")")
                        }
                    }
                default: break
                }
            }
        }
    }
    #endif
}
