import Cocoa
@preconcurrency import ApplicationServices

/// Dock-icon hit-testing + per-app actions, mirroring Swish's
/// DockItem/MinDockItem origin handling.
enum DockIcon {

    /// Dock item under a global point (AX top-left coords), if any.
    /// Returns the item element plus the owning app's pid.
    static func dockItemAt(_ p: CGPoint) -> (element: AXUIElement, pid: pid_t)? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &element) == .success,
              var node = element else { return nil }

        // Walk up the AX hierarchy looking for an AXDockItem.
        while true {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &role)
            if (role as? String) == "AXDockItem" {
                // Only application & minimized-window dock items respond to gestures.
                var sub: AnyObject?
                AXUIElementCopyAttributeValue(node, kAXSubroleAttribute as CFString, &sub)
                let s = sub as? String
                guard s == "AXApplicationDockItem" || s == "AXMinimizedWindowDockItem"
                else { return nil }
                guard let pid = pidFor(item: node) else { return nil }
                return (node, pid)
            }
            var parent: AnyObject?
            guard AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parent) == .success,
                  let p = parent else { return nil }
            node = unsafeDowncast(p, to: AXUIElement.self)
        }
    }

    /// Dock items expose the app name via AXTitle; resolve to a pid.
    private static func pidFor(item: AXUIElement) -> pid_t? {
        var title: AnyObject?
        var url: AnyObject?
        AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &title)
        AXUIElementCopyAttributeValue(item, "AXURL" as CFString, &url)

        // Exact URL match first (unambiguous), then localized name.
        if let u = url as? URL {
            if let app = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleURL?.path == u.path }) {
                return app.processIdentifier
            }
        }
        if let name = title as? String,
           let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == name }) {
            return app.processIdentifier
        }
        return nil
    }

    /// All AX windows belonging to a pid.
    static func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success,
              let arr = raw as? [AXUIElement] else { return [] }
        return arr
    }

    /// Minimize every window of the app (swipe-down on its dock icon).
    static func minimizeAll(pid: pid_t) {
        for w in windows(of: pid) {
            AXUIElementSetAttributeValue(w, "AXMinimized" as CFString, kCFBooleanTrue)
        }
    }

    /// Restore + raise the app (swipe-up on its dock icon).
    static func unminimizeAll(pid: pid_t) {
        for w in windows(of: pid) {
            AXUIElementSetAttributeValue(w, "AXMinimized" as CFString, kCFBooleanFalse)
        }
        NSRunningApplication(processIdentifier: pid)?
            .activate(options: .activateAllWindows)
    }

    /// Quit the app owning this dock icon (pinch-in).
    static func terminate(pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }
}
