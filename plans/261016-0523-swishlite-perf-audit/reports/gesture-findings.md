# Gesture & CPU Findings — 2026-10-16

## Confirmed

| # | Finding | File | Severity |
|---|---------|------|----------|
| G1 | `computePinch` allocated `Array(live.values)` + a `Task` hop per contact frame (~125Hz during pinch) | `Multitouch.swift` | medium — alloc churn |
| G3/G4 | `windowAtPoint` (AX element-at-position + parent-walk + frame fetch) ran **on the event-tap thread for every scroll event** during a swipe — synchronous IPC at ~125Hz; risks `tapDisabledByTimeout` and adds ms-level latency per event | `GestureEngine.swift` scroll case | high |
| G3b | `NSEvent(cgEvent:)` allocated per scroll event just to read `isDirectionInvertedFromDevice` | `GestureEngine.swift:150` | low |
| G3c | `handleDrag` ran `windowAtPoint` on **every leftMouseDragged in any app** (dragging files, text selection…) until a titlebar hit stuck | `GestureEngine.swift` | high |
| G3d | While dragging a window, `frame(of:)` (2 AX IPCs) ran per mouse event just to read size — window size can't change mid-drag | `GestureEngine.swift` | medium |
| G5 | Bezel creates a new NSWindow per gesture commit — acceptable (transient, orderOut after 380ms), no timers aside from the sleep task | `Bezel.swift` | OK — no fix |

## Refuted / acceptable

- G2: no polling timers — all event-driven (event tap + NSEvent monitors + MT callback). scheduleReset uses Task.sleep — fine.
- `usleep(150_000)` in minimized-restore path — intentional, rare path, left as-is (changing risks semantics).

## Fixes applied

- Per-gesture hit-test cache `scrollProbeHit` (reset on phase began/ended) — one AX probe per swipe instead of per event.
- `NSEvent` creation moved inside the on-titlebar branch.
- `dragProbed` flag — one probe per drag session, reset on mouse-up.
- Cached `dragWindowSize` at drag start; no per-event `frame(of:)`.
- Pinch: no per-event Array alloc; Task hops coalesced via pendingDelta flag.
