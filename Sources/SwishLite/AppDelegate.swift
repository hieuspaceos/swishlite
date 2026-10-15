import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let engine = GestureEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1.fill", accessibilityDescription: "SwishLite")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        Permissions.ensureAccessibility()
        engine.start()
        fputs("[swishlite] AXIsProcessTrusted=\(AXIsProcessTrusted())\n", stderr)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(engine: engine)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "SwishLite Settings"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.setContentSize(NSSize(width: 780, height: 560))
            win.center()
            win.isReleasedWhenClosed = false
            win.delegate = self
            settingsWindow = win
        }
        NSApp.setActivationPolicy(.regular)
        guard let win = settingsWindow else { return }
        win.makeKeyAndOrderFront(nil)
        win.makeMain()
        // Activate after ordering so AppKit treats this window as the key target.
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
