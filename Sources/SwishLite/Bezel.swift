import Cocoa

/// Tiny floating icon at the cursor that mirrors Swish's gesture glyphs:
/// a small arrow/maximize/minimize mark that flashes at the pointer when a
/// snap gesture commits.
@MainActor
final class Bezel {
    private var window: NSWindow?

    @MainActor
    func show(zone: SnapZone, at point: CGPoint) {
        hide()
        guard let name = Self.symbolName(for: zone) else { return }
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }

        let conf = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let tinted = img.withSymbolConfiguration(conf) ?? img

        let size = NSSize(width: 26, height: 26)
        let rect = NSRect(x: point.x - size.width / 2,
                          y: point.y - size.height / 2 - 10,   // sit just above the cursor
                          width: size.width, height: size.height)
        let w = NSWindow(contentRect: rect,
                         styleMask: [.borderless],
                         backing: .buffered,
                         defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let v = NSImageView(frame: NSRect(origin: .zero, size: size))
        v.image = tinted
        v.imageScaling = .scaleProportionallyUpOrDown
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        v.layer?.cornerRadius = 6
        v.layer?.borderWidth = 0.5
        v.layer?.borderColor = NSColor.separatorColor.cgColor
        w.contentView = v

        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.05
            w.animator().alphaValue = 1
        }
        Task { [weak self, weak w] in
            try? await Task.sleep(nanoseconds: 380_000_000)
            w?.orderOut(nil)          // plain dismiss — no fade dependency
            if self?.window === w { self?.window = nil }
        }
    }

    @MainActor
    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private static func symbolName(for zone: SnapZone) -> String? {
        switch zone {
        case .left:            return "rectangle.lefthalf.filled"
        case .right:           return "rectangle.righthalf.filled"
        case .topHalf:         return "rectangle.tophalf.filled"
        case .bottomHalf:      return "rectangle.bottomhalf.filled"
        case .maximize:        return "rectangle.inset.filled"
        case .minimize:        return "arrow.down.right.and.arrow.up.left"
        case .topLeft:         return "rectangle.inset.topleft.filled"
        case .topRight:        return "rectangle.inset.topright.filled"
        case .bottomLeft:      return "rectangle.inset.bottomleft.filled"
        case .bottomRight:     return "rectangle.inset.bottomright.filled"
        case .leftThird,
             .midThird,
             .rightThird,
             .leftTwoThirds,
             .rightTwoThirds:  return "rectangle.split.3x1.fill"
        case .center:          return "rectangle.center.inset.filled"
        case .closeApp:        return "xmark.circle.fill"
        case .restore:         return "arrow.uturn.backward"
        }
    }
}
