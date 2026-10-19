---
title: "SwishLite perf optimization"
status: todo
goal: "Idle footprint ≤ 25 MB, event-tap callback < 1 ms"
---

# SwishLite — Performance Optimization

Baseline: ~36 MB idle footprint, 0.6 MB bundle. Already light; remaining
cost is the always-on `CGEventTap` — every scroll/gesture system-wide runs
our callback.

## Hot paths

1. **Event tap callback** (`GestureEngine.handle`) runs for *every*
   scrollWheel/magnify/gesture event on the system. Must stay < ~1 ms or
   macOS flags the tap as slow and may disable it.
   - Early-out before any AX calls when `settings.enabled == false`.
   - Skip hit-test (`WindowControl.windowAtPoint`) on momentum/zero-delta
      events — already partially done; verify the guard runs *before* AX
      query.
   - Precompute title-bar hit-test rectangles? AX calls are the expensive
      part (~2-5 ms each); only run on phase `.began`.
2. **Bezel HUD** — ensure the bezel window is created lazily, hidden after
      fade, and doesn't keep a strong image ref.
3. **Settings window** — SwiftUI `SettingsView` allocated at launch?
      Construct on first open, release on close.
4. **Drag tracking** — `scrollAcc`/drag state mutated per event; make sure
      there's no allocation inside the gesture loop (String concat, array
      append).

## Actions

- [x] Move all `AXUIElement` queries behind `phase == .began` guard.
- [x] Cache `settings` reads — don't hit `UserDefaults` in the event loop
      (Settings already uses in-memory props; verify no `d.bool(forKey:)`
      calls inside gesture paths).
- [x] Lazy-init `SettingsView` window; `window.delegate` → close releases.
- [x] Audit allocations in `handleScrollDelta`/`resolve` — no String/Array
      work per event.
- [ ] Measure tap callback cost: `instruments -t "Time Profiler"` filtered
      to `GestureEngine` while scrolling continuously 30 s. Target p99 < 1 ms.
- [x] **Bound `lastFrames` restore map** — `[Int: CGRect]` written on every
      non-restore `apply()`, never pruned; `windowKey()` (pid XOR AXWindowID)
      can collide and dead-window entries persist for process lifetime. Add
      LRU bound or clear on window close.

## Verify

```sh
PID=$(pgrep -x SwishLite | head -1)
leaks -nostacks $PID
# scroll a trackpad hard for 30s, confirm tap never gets disabled:
log show --last 1m --predicate 'eventMessage CONTAINS "event tap"' 
```
