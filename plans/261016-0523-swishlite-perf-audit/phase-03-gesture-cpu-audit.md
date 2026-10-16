---
title: "Phase 3: Gesture & CPU Audit"
status: done
---

# Phase 3: Gesture & CPU Audit

## Overview

The hot path is: MultitouchSupport callback → GestureEngine → AXUIElement
setAttribute on the target window. Every ms and every allocation here is
per-frame at up to ~125Hz touch report rate.

## Suspects to verify

| # | Suspect | Where | Check |
|---|---------|-------|-------|
| G1 | Per-event allocation (arrays, closures, NSPoint conversions) in touch callback | `Multitouch.swift`, `GestureEngine.swift` | Allocations inside callback |
| G2 | Polling timers for gesture state/velocity | `GestureEngine.swift` | Timer/CADisplayLink/CFRunLoop sources |
| G3 | AX calls issued per touch event without throttling/coalescing | `WindowControl.swift` | Every move event → AX write? |
| G4 | `AXUIElementCopyAttributeValue` per gesture to find window under cursor — synchronous IPC, ~1-5ms | `WindowControl.swift` | Cache per gesture session? |
| G5 | Bezel overlay redraw or hide timers | `Bezel.swift` | Timer churn |
| G6 | Settings view never released | `SettingsView.swift`, `AppDelegate.swift` | NSHostingView lifecycle |

## Implementation Steps

1. Read Multitouch callback: is it a C callback on a private thread? Does it
   hop to main? Any allocation per contact?
2. Read GestureEngine state machine: per-event work, timers, dead zones,
   velocity math. Flag any `Timer`/`RunLoop` polling.
3. Read WindowControl: count AX calls per gesture tick; check for
   coalescing (e.g., only write on 16ms boundary or on settle).
4. Read Bezel: when shown/hidden; any repeat timers.
5. Instruments-lite: `sample <pid> 5` during a gesture to catch hot stacks.
6. Write `reports/gesture-findings.md` with file:line.

## Success Criteria

Each suspect marked confirmed/refuted with evidence.
