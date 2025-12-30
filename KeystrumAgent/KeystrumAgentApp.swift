//
//  KeystrumAgentApp.swift
//  KeystrumAgent
//
//  Created by Andrew Finke on 12/29/25.
//

import SwiftUI
import ServiceManagement
import KeystrumCore

@main
struct KeystrumAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let inputMonitor = InputMonitor.shared
    private var launchAtLoginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        checkPermissionsAndStart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush any pending events before quitting
        inputMonitor.flushPendingEvents()
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "keyboard.badge.eye", accessibilityDescription: "Keystrum Agent")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Keystrum Agent", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: "Status: Starting...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login toggle
        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.state = isLaunchAtLoginEnabled() ? .on : .off
        launchAtLoginMenuItem = launchAtLogin
        menu.addItem(launchAtLogin)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func checkPermissionsAndStart() {
        if inputMonitor.checkPermissions() {
            updateStatus("Status: Active")
            startMonitoring()
        } else {
            updateStatus("Status: Needs Permissions")
            showPermissionsAlert()
        }
    }

    private func startMonitoring() {
        Task {
            await DatabaseManager.shared.getStats()
        }

        inputMonitor.startMonitoring()
    }

    private func updateStatus(_ status: String) {
        if let menu = statusItem?.menu,
           let statusItem = menu.item(withTag: 100) {
            statusItem.title = status
        }
    }

    private func showPermissionsAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = "Keystrum Agent needs accessibility permissions to monitor keyboard and mouse input.\n\nPlease go to System Settings > Privacy & Security > Accessibility and enable Keystrum Agent."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Launch at Login

    private func isLaunchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled() {
                try SMAppService.mainApp.unregister()
                launchAtLoginMenuItem?.state = .off
            } else {
                try SMAppService.mainApp.register()
                launchAtLoginMenuItem?.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login Failed"
            alert.informativeText = "Could not change the launch at login setting: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
