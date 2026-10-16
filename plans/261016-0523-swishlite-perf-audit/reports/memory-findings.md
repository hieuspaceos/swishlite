# Memory Findings — SwishLite 2026-10-16

## Confirmed

| # | Finding | File | Fix |
|---|---------|------|-----|
| M1 | Settings window + whole SwiftUI `NSHostingController` graph retained forever after close (`isReleasedWhenClosed=false`, strong ref in AppDelegate) | `AppDelegate.swift:34` | `isReleasedWhenClosed=true` + nil out `settingsWindow` in `windowWillClose` |

## Verified non-issues

- `leaks`: 417 framework noise entries (~20KB), zero SwishLite/AXUIElement leaks
- Bezel window: transient, `orderOut` + nil after 380ms
- `lastFrames` dict: small CGRect per snapped window — negligible
- `live` touch dict: cleared on touch-end (`n == 0` branch)
- AXUIElement refs: bridged correctly (no Unmanaged leaks found)

## Post-fix measurement

Footprint after relaunch: **12 MB** (fresh process; will settle ~25-35MB
under normal use — SwiftUI runtime loads lazily).
