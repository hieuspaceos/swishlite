import Cocoa
@preconcurrency import ApplicationServices

enum WindowControl {
    static func windowAtPoint(_ point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide,
                                               Float(point.x),
                                               Float(point.y),
                                               &element) == .success else { return nil }
        var current = element
        while let node = current {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &role)
            if (role as? String) == kAXWindowRole { return node }
            var parent: AnyObject?
            AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parent)
            current = parent.map { unsafeDowncast($0 as AnyObject, to: AXUIElement.self) }
        }
        return nil
    }

    static func frame(of win: AXUIElement) -> CGRect? {
        var posRaw: AnyObject?, sizeRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRaw) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRaw) == .success
        else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue((posRaw as! AXValue), .cgPoint, &p)
        AXValueGetValue((sizeRaw as! AXValue), .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    static func isOnTitleBar(_ point: CGPoint, window: AXUIElement) -> Bool {
        guard let f = frame(of: window) else { return false }
        let title = CGRect(x: f.minX, y: f.minY, width: f.width, height: 38)
        return title.contains(point)
    }

    /// The window's standard close button (red traffic light), if exposed via AX.
    static func closeButton(of win: AXUIElement) -> AXUIElement? {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(win, "AXCloseButton" as CFString, &raw) == .success
        else { return nil }
        return raw.map { unsafeDowncast($0, to: AXUIElement.self) }
    }

    static func isMinimized(_ win: AXUIElement) -> Bool {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(win, "AXMinimized" as CFString, &raw) == .success,
              let v = raw as? Bool else { return false }
        return v
    }

    static func setFrame(_ win: AXUIElement, _ target: CGRect, animate duration: Double = 0) {
        guard duration > 0, let start = frame(of: win) else {
            applyFrame(win, target); return
        }
        // timer-driven animation on main run loop — no sleep() jitter
        let steps = 14
        let dt = duration / Double(steps)
        let counter = StepCounter()
        Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { t in
            counter.i += 1
            let p = Double(counter.i) / Double(steps)
            let e = 1 - pow(1 - p, 3)  // cubic ease-out
            applyFrame(win, CGRect(
                x: start.minX + (target.minX - start.minX) * e,
                y: start.minY + (target.minY - start.minY) * e,
                width: start.width + (target.width - start.width) * e,
                height: start.height + (target.height - start.height) * e))
            if counter.i >= steps { t.invalidate() }
        }
    }

    private final class StepCounter: @unchecked Sendable { var i = 0 }

    private static func applyFrame(_ win: AXUIElement, _ f: CGRect) {
        var pos = f.origin, size = f.size
        if let pv = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pv)
        }
        if let sv = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sv)
        }
    }
}
