import Cocoa
import ApplicationServices
import ServiceManagement
import Combine

enum SnapZone: Equatable {
    case left, right, maximize, center, minimize, closeApp
    case topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, midThird, rightThird, leftTwoThirds, rightTwoThirds
    case restore
}

/// Window-snapping engine modeled on the real Swish architecture:
/// one CGEventTap at the HID level consumes system gesture events
/// (swipe / magnify / smart-zoom) when the cursor sits on a title bar,
/// then a two-stage resolver maps swipe sequences to snap zones
/// (halves → thirds/quarters), exactly like Swish's gesture model.
@MainActor
final class GestureEngine: ObservableObject {
    let settings = Settings.shared

    /// Mirror of `settings.enabled` readable on the event-tap thread —
    /// lets the tap callback early-out before any AX work without
    /// touching UserDefaults or hopping to main.
    nonisolated(unsafe) private var enabledFlag = true
    private var settingsObserver: AnyCancellable?

    // CGEventTap state
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // swipe-sequence state (halves → thirds/quarters)
    private enum Axis { case none, x, y }
    private var stage = 0            // 0 idle, 1 one axis resolved
    private var stageAxis: Axis = .none
    private var stageSign = 0
    private var resetTask: Task<Void, Never>?

    // pinch accumulation

    // unsnap memory — bounded LRU: windowKey() can collide and dead-window
    // entries would otherwise accumulate for the process lifetime.
    private var lastFrames: [Int: CGRect] = [:]
    private var lastFramesOrder: [Int] = []   // oldest → newest
    private static let lastFramesLimit = 64

    // drag-on-titlebar state
    private var dragWindow: AXUIElement?
    private var dragOrigin = CGPoint.zero
    private var windowOrigin = CGPoint.zero
    private var dragging = false
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var magMonitor: Any?

    // MARK: - Lifecycle

    func start() {
        enabledFlag = settings.enabled
        settingsObserver = settings.$enabled
            .sink { [weak self] v in self?.enabledFlag = v }
        startEventTap()
        // Swish-style: dragging a snapped window by its title bar restores it.
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] ev in
            Task { @MainActor in self?.handleDrag(ev) }
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in self?.endDrag() }
        }
        // Swish-style pinch: type-29 taps don't carry magnify on this OS,
        // so grab it via a global NSEvent monitor instead.
        magMonitor = NSEvent.addGlobalMonitorForEvents(matching: .magnify) { [weak self] ev in
            Task { @MainActor in
                self?.handleMagnifyGlobal(ev.magnification)
            }
        }

        // Raw-touch pinch recognizer (Swish uses MultitouchSupport for this too —
        // magnify CGEvents are not delivered to background taps on modern macOS).
        Multitouch.shared.onPinch = { [weak self] d in
            self?.handleMagnifyGlobal(d)
        }
        Multitouch.shared.onTouchEnd = { [weak self] in self?.pinchFired = false }
        Multitouch.shared.start()
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil; runLoopSource = nil
        if let m = dragMonitor { NSEvent.removeMonitor(m); dragMonitor = nil }
        if let m = upMonitor { NSEvent.removeMonitor(m); upMonitor = nil }
        if let m = magMonitor { NSEvent.removeMonitor(m); magMonitor = nil }
    }

    // MARK: - CGEventTap (the core input path, same as Swish)

    private func startEventTap() {
        // Gesture-bearing event types (CGEventType raw == NSEventType raw):
        //   22 scrollWheel (two-finger swipe), 30 magnify, 32 smart zoom
        var mask: CGEventMask = 0
        // bit 29 = NSEventType.gesture (magnify/swipe/smartZoom subtype live there —
        // Swish's tap mask 0x20401400 includes it); 30/31/32 for raw types.
        for raw in [22, 29, 30, 31, 32] { mask |= CGEventMask(1) << CGEventMask(UInt32(raw)) }

        let cb: CGEventTapCallBack = { proxy, type, event, refcon in
            // Re-enable if the system disabled the tap.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon {
                    let engine = Unmanaged<GestureEngine>.fromOpaque(refcon).takeUnretainedValue()
                    if let tap = engine.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                }
                return Unmanaged.passUnretained(event)
            }
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<GestureEngine>.fromOpaque(refcon).takeUnretainedValue()
            return engine.handleGestureEvent(type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,   // Swish uses tap=1 — sees synthetic gestures (magnify)
            place: .headInsertEventTap,
            options: .defaultTap,          // must be defaultTap — listenOnly cannot consume
            eventsOfInterest: mask,
            callback: cb,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap = eventTap else {
            print("[swishlite] event tap failed — grant Accessibility to this app")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[swishlite] gesture event tap active")
    }

    /// Returns nil to consume the event (stops space-switching etc.) or the event to pass through.
    /// Called on the event-tap thread; AX work hops to main.
    nonisolated private func handleGestureEvent(type: CGEventType, event: CGEvent)
        -> Unmanaged<CGEvent>? {
        // Early-out before any AX/IPC work when disabled — the tap still
        // sees every event system-wide, so this guard is the hot path.
        // Still clear per-gesture state on phase .ended/.cancelled so a
        // mid-swipe disable can't leave the recognizer stuck committed.
        guard enabledFlag else {
            if Int(type.rawValue) == 22 {
                let phase = event.getIntegerValueField(CGEventField(rawValue: 99)!)
                if phase == 4 || phase == 8 {
                    scrollProbeHit = nil
                    DispatchQueue.main.async { [weak self] in self?.endScrollGesture() }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        let raw = Int(type.rawValue)
        let loc = event.location

        switch raw {
        case 22: // scrollWheel — two-finger swipe arrives here (Swish's scrollDataX/Y path)
            let phase = event.getIntegerValueField(CGEventField(rawValue: 99)!)     // 1 began,2 changed,4 ended,8 cancelled
            let momentum = event.getIntegerValueField(CGEventField(rawValue: 123)!) // momentum wheel phase
            // momentum (coasting after fingers lifted) is never part of the swipe
            guard momentum == 0 else { return Unmanaged.passUnretained(event) }
            if phase == 4 || phase == 8 {
                scrollProbeHit = nil
                DispatchQueue.main.async { [weak self] in self?.endScrollGesture() }
                return gestureCommitted ? nil : Unmanaged.passUnretained(event)
            }
            let dy = event.getDoubleValueField(CGEventField(rawValue: 96)!)  // PointDeltaAxis1 = vertical
            let dx = event.getDoubleValueField(CGEventField(rawValue: 97)!)  // PointDeltaAxis2 = horizontal

            // Hit-test exactly once per gesture, at phase .began: the swipe is
            // anchored to where it started — re-testing per 125Hz event is a
            // synchronous AX IPC chain on the tap thread and risks
            // tapDisabledByTimeout. Phase-0 events (plain mouse wheels) and
            // mid-stream events never touch AX.
            if phase == 1 {
                let dockItem = DockIcon.dockItemAt(loc)
                let hit = dockItem != nil || lastMinimizedWindow != nil
                          || Self.pointOnAnyTitleBar(loc)
                // Swish honors Natural scrolling: non-inverted device → flip
                // deltas so a physical swipe maps the same way everywhere.
                // Sampled once at .began — avoids an NSEvent alloc per event.
                let inv = NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false
                scrollProbeHit = (hit, dockItem?.pid ?? 0, inv)
            }
            guard let (onTitleBar, dockPID, inv) = scrollProbeHit,
                  onTitleBar, dx != 0 || dy != 0
            else { return gestureCommitted ? nil : Unmanaged.passUnretained(event) }
            let fx = inv ? dx : -dx
            let fy = inv ? dy : -dy
            DispatchQueue.main.async { [weak self] in
                self?.handleScrollDelta(dx: fx, dy: fy, at: loc, dockPID: dockPID)
            }
            // consume only while a committed swipe is in progress (Swish's isSwiping flag)
            return gestureCommitted ? nil : Unmanaged.passUnretained(event)

        case 29: // NSEventType.gesture — magnify/swipe arrive with this type
            guard let ev = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
            guard ev.type == .magnify else { return Unmanaged.passUnretained(event) }
            // Same rule as scroll: pay for the AX hit-test once per gesture,
            // at phase .began — never per magnify event (~60-120Hz stream).
            let phase = event.getIntegerValueField(CGEventField(rawValue: 99)!)
            if phase == 4 || phase == 8 { magProbeHit = nil; return Unmanaged.passUnretained(event) }
            if phase == 1 {
                let dockPID = DockIcon.dockItemAt(loc)?.pid ?? 0
                magProbeHit = (dockPID != 0 || Self.pointOnAnyTitleBar(loc), dockPID)
            } else if magProbeHit == nil, phase == 0 {
                // Phaseless magnify stream (no .began): probe per event like before.
                let dockPID = DockIcon.dockItemAt(loc)?.pid ?? 0
                magProbeHit = (dockPID != 0 || Self.pointOnAnyTitleBar(loc), dockPID)
            }
            guard let (onTitleBar, dockPID) = magProbeHit, onTitleBar
            else { return Unmanaged.passUnretained(event) }
            let mag = ev.magnification
            DispatchQueue.main.async { [weak self] in
                self?.handleMagnify(mag, at: loc, dockPID: dockPID)
            }
            return nil

        case 32: // smart zoom = two-finger double-tap → unsnap/restore
            let onTitleBar = Self.pointOnAnyTitleBar(loc)
            if onTitleBar {
                DispatchQueue.main.async { [weak self] in
                    self?.handleDoubleTap(at: loc)
                }
            }
            return onTitleBar ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Hit-test helper usable off-main: is the point over any window's title bar?
    nonisolated private static func pointOnAnyTitleBar(_ p: CGPoint) -> Bool {
        guard let win = WindowControl.windowAtPoint(p) else { return false }
        return WindowControl.isOnTitleBar(p, window: win)
    }

    // MARK: - Scroll accumulation (two-finger swipe → snap, Swish's scrollDataX/Y path)

    private var scrollAcc = CGVector.zero
    private var scrollWindow: AXUIElement?
    private var scrollScreen: NSScreen?
    /// true while a snap gesture is in progress — tap consumes scroll events then
    nonisolated(unsafe) private var gestureCommitted = false
    /// Per-scroll-gesture hit-test cache — set at phase .began, cleared on
    /// .ended/.cancelled. (onTitleBar-or-dockItem, dockPID, directionInverted).
    /// Read/written on the event-tap thread only.
    nonisolated(unsafe) private var scrollProbeHit: (Bool, pid_t, Bool)?
    /// Same per-gesture hit-test cache for the magnify stream.
    nonisolated(unsafe) private var magProbeHit: (Bool, pid_t)?

    @MainActor
    private func handleScrollDelta(dx: Double, dy: Double, at loc: CGPoint, dockPID: pid_t = 0) {
        guard settings.enabled else { return }
        // one committed action per physical swipe — re-arms on phase end
        guard !didCommitThisGesture else { return }

        scrollAcc.dx += dx
        scrollAcc.dy += dy

        // Dock-icon gesture path: vertical swipes map to minimize/restore-all.
        if dockPID != 0 {
            let threshold: CGFloat = 90
            guard abs(scrollAcc.dy) > threshold, abs(scrollAcc.dy) >= abs(scrollAcc.dx) else { return }
            gestureCommitted = true
            didCommitThisGesture = true
            if scrollAcc.dy < 0 {                    // up → restore + activate
                DockIcon.unminimizeAll(pid: dockPID)
            } else {                                 // down → minimize all
                DockIcon.minimizeAll(pid: dockPID)
            }
            bezel.show(zone: scrollAcc.dy < 0 ? .maximize : .minimize,
                       at: NSEvent.mouseLocation)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            scrollAcc = .zero
            return
        }

        // capture target once so mid-gesture cursor drift doesn't switch windows;
        // a minimized window can't be hit-tested — fall back to the tracked one.
        if scrollWindow == nil {
            scrollWindow = lastMinimizedWindow ?? WindowControl.windowAtPoint(loc)
            scrollScreen = screenContaining(loc)
        }
        guard let win = scrollWindow, let screen = scrollScreen else { return }

        // Swish-style: swiping up on a minimized window restores it from the Dock.
        if WindowControl.isMinimized(win), scrollAcc.dy < -30 {
            AXUIElementSetAttributeValue(win, "AXMinimized" as CFString, kCFBooleanFalse)
            usleep(150_000)
        }

        // ~90 pt of travel commits a swipe; diagonal dominance ≥1.4× required
        let threshold: CGFloat = 90
        let ax = abs(scrollAcc.dx), ay = abs(scrollAcc.dy)
        guard ax > threshold || ay > threshold else { return }
        guard ax >= ay * 1.4 || ay >= ax * 1.4 else { return }

        gestureCommitted = true
        didCommitThisGesture = true
        let axis: Axis = ax >= ay ? .x : .y
        let v = axis == .x ? scrollAcc.dx : scrollAcc.dy
        if let zone = resolve(axis: axis, sign: v > 0 ? 1 : -1) {
            fputs("[swishlite] scroll swipe acc=\(scrollAcc) zone=\(zone)\n", stderr)
            apply(zone, to: win, screen: screen)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            lastMinimizedWindow = zone == .minimize ? win : nil
        }
        scrollAcc = .zero
    }

    /// Window the last down-swipe minimized — kept so a swipe-up restores it
    nonisolated(unsafe) private var lastMinimizedWindow: AXUIElement?
    private let bezel = Bezel()

    /// Called when the scroll phase reports .ended/.cancelled — re-arms the recognizer.
    private func endScrollGesture() {
        scrollAcc = .zero; scrollWindow = nil; scrollScreen = nil
        gestureCommitted = false
        didCommitThisGesture = false
    }

    private var didCommitThisGesture = false

    // MARK: - Pinch (magnify) → minimize/maximize

    private var magAcc: Double = 0
    /// true after a pinch committed once — re-arms when fingers lift.
    private var pinchFired = false

    @MainActor
    private func handleMagnify(_ mag: Double, at loc: CGPoint, dockPID: pid_t = 0) {
        guard settings.enabled else { return }
        magAcc += mag
        guard abs(magAcc) > 0.4 else { return }
        let pinchIn = magAcc < 0
        magAcc = 0
        if dockPID != 0 {                          // pinch on a Dock icon
            bezel.show(zone: pinchIn ? .closeApp : .maximize, at: NSEvent.mouseLocation)
            if pinchIn { DockIcon.terminate(pid: dockPID) }
            else { DockIcon.unminimizeAll(pid: dockPID) }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            return
        }
        guard let win = WindowControl.windowAtPoint(loc),
              let screen = screenContaining(loc) else { return }
        applyPinchTo(win, pinchIn: pinchIn, screen: screen)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Pinch in → terminate the app owning the window under the cursor;
    /// pinch out → maximize.
    func applyPinchTo(_ win: AXUIElement, pinchIn: Bool, screen: NSScreen) {
        if pinchIn {
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            bezel.show(zone: .closeApp, at: NSEvent.mouseLocation)
            app.terminate()
        } else {
            apply(.maximize, to: win, screen: screen)
        }
    }

    /// Same pinch logic but fed from the global NSEvent monitor — needed
    /// because type-29 tap events on this macOS don't carry magnification.
    @MainActor
    private func handleMagnifyGlobal(_ mag: Double) {
        guard settings.enabled else { return }
        let loc = NSEvent.mouseLocation
        let h = NSScreen.screens[0].frame.height
        let ax = CGPoint(x: loc.x, y: h - loc.y)
        magAcc += mag
        guard !pinchFired else { magAcc = 0; return }   // one commit per physical pinch
        guard abs(magAcc) > 0.025 else { return }
        let pinchIn = magAcc < 0
        magAcc = 0
        pinchFired = true
        guard let win = WindowControl.windowAtPoint(ax),
              WindowControl.isOnTitleBar(ax, window: win),
              let screen = screenContaining(ax) else { return }
        applyPinchTo(win, pinchIn: pinchIn, screen: screen)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }



    // MARK: - Swipe zone resolution
    /// Two-stage resolution, mirroring Swish's model (NSTouch-normalized coords:
    /// x → right positive, y → *up* positive):
    /// 1st horizontal → half; 2nd horizontal → third/two-thirds;
    /// horizontal then vertical → quarter; 1st vertical → maximize/center;
    /// 2nd vertical → top/bottom half.
    private func resolve(axis ax: Axis, sign: Int) -> SnapZone? {
        switch (stage, ax) {
        // measured on this machine: field97 (dx): <0=left, >0=right;
        // field96 (dy): sign of up/down measured below
        case (0, .x):
            stage = 1; stageAxis = .x; stageSign = sign; scheduleReset()
            return sign < 0 ? .left : .right
        case (0, .y):
            if sign < 0 { return .maximize }         // swipe up → fill screen
            stage = 1; stageAxis = .y; stageSign = sign; scheduleReset()
            return .minimize                          // swipe down → minimize
        case (1, .x) where stageAxis == .x:
            reset()
            if sign == stageSign { return sign < 0 ? .leftTwoThirds : .rightTwoThirds }
            return sign < 0 ? .leftThird : .rightThird
        case (1, .y) where stageAxis == .x:
            let wasLeft = stageSign < 0
            reset()
            switch (wasLeft, sign) {
            case (true, -1):  return .topLeft
            case (true, 1):   return .bottomLeft
            case (false, -1): return .topRight
            case (false, 1):  return .bottomRight
            default: return nil
            }
        case (1, .y) where stageAxis == .y:
            reset()
            return sign < 0 ? .topHalf : .bottomHalf
        default:
            reset()
            return nil
        }
    }

    private func scheduleReset() {
        resetTask?.cancel()
        resetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.reset()
        }
    }
    private func reset() { stage = 0; stageAxis = .none }


    // MARK: - Double tap → unsnap/restore

    private func handleDoubleTap(at loc: CGPoint) {
        guard settings.enabled else { return }
        guard let win = WindowControl.windowAtPoint(loc),
              WindowControl.isOnTitleBar(loc, window: win),
              let screen = screenContaining(loc) else { return }
        apply(.restore, to: win, screen: screen)
    }

    // MARK: - Title-bar drag → move/unsnap window

    private func handleDrag(_ ev: NSEvent) {
        guard settings.enabled, settings.dragToUnsnap else { return }
        guard let ax = Self.axPoint(NSEvent.mouseLocation) else { return }
        if !dragging {
            // Probe once per drag session: leftMouseDragged fires for every
            // drag in every app — only the first event after mouse-down should
            // pay for the AX IPC lookup.
            guard !dragProbed else { return }
            dragProbed = true
            guard let win = WindowControl.windowAtPoint(ax),
                  WindowControl.isOnTitleBar(ax, window: win),
                  let f = WindowControl.frame(of: win) else { return }
            dragWindow = win; dragOrigin = ax; windowOrigin = f.origin
            dragWindowSize = f.size; dragging = true
        }
        guard let win = dragWindow else { return }
        let nf = CGRect(origin: CGPoint(
            x: windowOrigin.x + (ax.x - dragOrigin.x),
            y: windowOrigin.y + (ax.y - dragOrigin.y)), size: dragWindowSize)
        WindowControl.setFrame(win, nf, animate: 0)
    }

    private var dragProbed = false
    private var dragWindowSize = CGSize.zero

    private func endDrag() { dragging = false; dragWindow = nil; dragProbed = false }

    // MARK: - Apply zones (AX coords, y-down from primary screen top)

    func apply(_ zone: SnapZone, to win: AXUIElement, screen: NSScreen) {
        let h = NSScreen.screens[0].frame.height
        var v = screen.visibleFrame
        v = CGRect(x: v.minX, y: h - v.maxY, width: v.width, height: v.height)
            .insetBy(dx: settings.gridSpacing, dy: settings.gridSpacing)

        let target: CGRect
        switch zone {
        case .left:           target = CGRect(x: v.minX, y: v.minY, width: v.width/2, height: v.height)
        case .right:          target = CGRect(x: v.midX, y: v.minY, width: v.width/2, height: v.height)
        case .maximize:       target = v
        case .topHalf:        target = CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height/2)
        case .bottomHalf:     target = CGRect(x: v.minX, y: v.midY, width: v.width, height: v.height/2)
        case .topLeft:        target = CGRect(x: v.minX, y: v.minY, width: v.width/2, height: v.height/2)
        case .topRight:       target = CGRect(x: v.midX, y: v.minY, width: v.width/2, height: v.height/2)
        case .bottomLeft:     target = CGRect(x: v.minX, y: v.midY, width: v.width/2, height: v.height/2)
        case .bottomRight:    target = CGRect(x: v.midX, y: v.midY, width: v.width/2, height: v.height/2)
        case .leftThird:      target = CGRect(x: v.minX, y: v.minY, width: v.width/3, height: v.height)
        case .midThird:       target = CGRect(x: v.minX+v.width/3, y: v.minY, width: v.width/3, height: v.height)
        case .rightThird:     target = CGRect(x: v.minX+2*v.width/3, y: v.minY, width: v.width/3, height: v.height)
        case .leftTwoThirds:  target = CGRect(x: v.minX, y: v.minY, width: 2*v.width/3, height: v.height)
        case .rightTwoThirds: target = CGRect(x: v.minX+v.width/3, y: v.minY, width: 2*v.width/3, height: v.height)
        case .center:
            let w = v.width*0.6, hh = v.height*0.6
            target = CGRect(x: v.midX-w/2, y: v.midY-hh/2, width: w, height: hh)
        case .minimize:
            bezel.show(zone: zone, at: NSEvent.mouseLocation)
            AXUIElementSetAttributeValue(win, "AXMinimized" as CFString, kCFBooleanTrue)
            return
        case .restore:
            guard let f = rememberedFrame(for: win) else { return }
            target = f
        case .closeApp:
            return   // handled in applyPinchTo, never reaches here
        }
        if zone != .restore, let cur = WindowControl.frame(of: win) {
            recordFrame(cur, for: win)
        }
        WindowControl.setFrame(win, target, animate: settings.animationDuration)
        bezel.show(zone: zone, at: NSEvent.mouseLocation)
    }

    private func windowKey(_ win: AXUIElement) -> Int {
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        var wid: AnyObject?
        _ = AXUIElementCopyAttributeValue(win, "AXWindowID" as CFString, &wid)
        return Int(pid) ^ ((wid as? Int) ?? 0)
    }

    /// LRU write — caps `lastFrames` so colliding/dead-window keys can't
    /// grow the map for the process lifetime. Commit path only; not per event.
    private func recordFrame(_ f: CGRect, for win: AXUIElement) {
        let key = windowKey(win)
        lastFrames[key] = f
        lastFramesOrder.removeAll { $0 == key }
        lastFramesOrder.append(key)
        while lastFramesOrder.count > Self.lastFramesLimit {
            let evicted = lastFramesOrder.removeFirst()
            lastFrames.removeValue(forKey: evicted)
        }
    }

    /// LRU read — restores and refreshes the entry's recency.
    private func rememberedFrame(for win: AXUIElement) -> CGRect? {
        let key = windowKey(win)
        guard let f = lastFrames[key] else { return nil }
        lastFramesOrder.removeAll { $0 == key }
        lastFramesOrder.append(key)
        return f
    }

    // MARK: - Coord helpers

    /// NSEvent.mouseLocation (y-up global) → AX point (y-down from primary top).
    private static func axPoint(_ p: CGPoint) -> CGPoint? {
        let h = NSScreen.screens[0].frame.height
        return CGPoint(x: p.x, y: h - p.y)
    }

    private func screenContaining(_ axPoint: CGPoint) -> NSScreen? {
        let h = NSScreen.screens[0].frame.height
        // convert back to Cocoa y-up for NSScreen.frame comparison
        let cocoa = CGPoint(x: axPoint.x, y: h - axPoint.y)
        return NSScreen.screens.first { $0.frame.contains(cocoa) } ?? NSScreen.main
    }

    // MARK: - Login item

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch { print("login item error: \(error)") }
    }
}
