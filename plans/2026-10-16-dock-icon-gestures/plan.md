# Dock-icon gestures (Swish parity)

## Swish RE findings (binary strings + structure)

- Swish has a **Gesture Origin enum** containing: `titlebar`, `dockItem`,
  `minDockItem` (+ `originMissionControl`, "Origin blocked" path).
- Dock items it distinguishes by AX role: `AXApplicationDockItem`,
  `AXMinimizedWindowDockItem`, `AXFolderDockItem`, `AXSeparatorDockItem`,
  `AXTrashDockItem` → models `Swish.DockItem` vs `Swish.MinDockItem`.
- Behaviors advertised in strings: pinch-in on dock icon → quit app;
  "pinch in twice → minimize all windows" (chained gesture); swipe on
  minimized dock item → restore; pinch out on dock icon → enter fullscreen/
  unminimize.
- Known caveat (their help string): right-clicking dock icons can clash with
  gesture sensitivity.

## Goal
Two-finger gestures over Dock icons act on that icon's app:

| Gesture on Dock icon | Action |
|---|---|
| Swipe up | activate app + unminimize all windows |
| Swipe down | minimize all of app's windows |
| Pinch in | terminate app |
| Pinch out | unminimize all / activate |
| Double-tap | (leave for later) |

Non-goal: don't change titlebar gesture behavior at all.

## Implementation

### 1. `DockIcon.swift` (new file)
- `dockItemAt(_ p: CGPoint) -> (element: AXUIElement, role: DockRole, pid: pid_t)?`
  - Get `AXUIElementCreateSystemWide` → `AXUIElementCopyElementAtPosition`
  - walk AXParent chain; hit `AXDockItem` with subrole
    `AXApplicationDockItem`/`AXMinimizedWindowDockItem`.
  - Resolve pid: dock item → `AXTitle` = app name → match
    `NSWorkspace.runningApplications` by `localizedName` (fallback bundle id).
- `windows(of pid:) -> [AXUIElement]` — AXApplication → `AXWindows`.
- `activate(pid:)` / `minimizeAll(pid:)` / `unminimizeAll(pid:)` helpers.

### 2. GestureEngine wiring (additive, titlebar path untouched)
- `nonisolated(unsafe) private var dockPID: pid_t = 0` + `dockMode: Bool`
- In case-22 handler: `if let item = DockIcon.dockItemAt(loc) { dockMode = true; dockPID = pid }`
  → route to `handleDockScrollDelta` (accumulate same way, threshold 90).
- Type-29 magnify: same dock check → `handleDockPinch`.
- On `endScrollGesture` clear dock state.
- Keep `gestureCommitted` consume semantics identical.

### 3. Actions
- up → `NSRunningApplication(pid:).activate(options:.activateAllWindows)` +
  set `AXMinimized=false` on each window.
- down → for each AXWindow: `AXMinimized=true`.
- pinch in → bezel `.closeApp` + `app.terminate()`.

### 4. Verification
- Safari window open → Dock icon swipe down → minimizes; swipe up → restores.
- Finder (no windows) → pinch on icon → quits.
- Regression: titlebar gestures still work exactly as now (all 4 directions,
  pinch close, minimize→up restore).

## Risks / notes
- Name-match pid resolution ambiguous if two apps share name — rare; use
  `AXURL` on dock item if present for exact match.
- Dock autohide: AXDockItem frames exist even when hidden — still hit-tests.
- Don't regress `lastMinimizedWindow` restore path (titlebar up after minimize).
