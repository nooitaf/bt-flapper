import AppKit
import BTFlapperCore
import os
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let askedLaunchAtLoginKey = "bt-flapper.askedLaunchAtLogin"

    private let logger = Logger(subsystem: "com.github.nooitaf.bt-flapper", category: "app")
    private let controller = FlapperController()
    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        controller.onEnabledChanged = { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateUI()
            }
        }
        controller.start()
        updateUI()

        // Trigger the macOS Bluetooth permission prompt on launch rather than waiting for the first lid close.
        controller.requestBluetoothPermission { [weak self] in
            DispatchQueue.main.async {
                self?.promptForLaunchAtLoginIfNeeded()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateUI()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        let menu = NSMenu()
        menu.delegate = self

        let toggleItem = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        toggleMenuItem = toggleItem

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        launchAtLoginMenuItem = launchAtLoginItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit bt-flapper",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    private func updateUI() {
        let enabled = controller.isEnabled
        toggleMenuItem?.state = enabled ? .on : .off
        launchAtLoginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off

        guard let button = statusItem?.button else { return }

        let symbolName = enabled
            ? "antenna.radiowaves.left.and.right"
            : "antenna.radiowaves.left.and.right.slash"
        let description = enabled ? "bt-flapper enabled" : "bt-flapper disabled"

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description) {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = enabled ? "BT" : "BT×"
        }

        button.toolTip = enabled ? "bt-flapper: Enabled" : "bt-flapper: Disabled"
    }

    private func promptForLaunchAtLoginIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.askedLaunchAtLoginKey) else { return }
        defaults.set(true, forKey: Self.askedLaunchAtLoginKey)

        guard SMAppService.mainApp.status != .enabled else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Start bt-flapper at login?"
        alert.informativeText = "Would you like bt-flapper to start automatically when you log in? You can change this anytime from the menu bar."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Yes, Start at Login")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            setLaunchAtLogin(enabled: true)
        }
    }

    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            logger.info("Launch at login set to \(enabled)")
        } catch {
            logger.error("Failed to update Launch at Login: \(error.localizedDescription, privacy: .public)")
        }
        updateUI()
    }

    @objc private func toggleEnabled() {
        controller.isEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        let currentlyEnabled = SMAppService.mainApp.status == .enabled
        setLaunchAtLogin(enabled: !currentlyEnabled)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
