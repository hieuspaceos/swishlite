---
title: "SwishLite — Performance & Smoothness Audit"
description: "Audit SwishLite trackpad window manager: gesture latency, idle CPU, RAM footprint, and animation smoothness."
status: pending
priority: P1
effort: "4-6h"
tags: [performance, macos, trackpad, appkit, gestures]
created: 2026-10-16
---

# SwishLite — Performance & Smoothness Audit

## Overview

SwishLite (~1,200 LOC, `pet/swish-clone/`) is a menubar trackpad-gesture
window manager. Baseline idle footprint: **34 MB**. Goal: gesture-to-window
latency imperceptible (<16ms/frame), zero idle CPU, smallest feasible
footprint.

## Goals

| # | Goal | Priority |
|---|------|----------|
| 1 | Idle CPU 0% — no polling/timer churn | P1 |
| 2 | Gesture → window move < 16ms frame budget | P1 |
| 3 | No per-event allocations in the gesture hot path | P1 |
| 4 | Idle footprint < 30MB, no leaks over a work session | P2 |

## Baseline (measured 2026-10-16)

| Metric | Value |
|--------|-------|
| Idle footprint | 34 MB (pid 49281) |
| RSS (ps) | ~55 MB |
| Code size | ~1,195 LOC across 9 files |
| Key files | `GestureEngine.swift` (506), `Multitouch.swift`, `WindowControl.swift`, `Bezel.swift` |

## Phases

| # | Phase | Status |
|---|-------|--------|
| 2 | [Baseline Measurement](./phase-02-baseline-measurement.md) | Pending |
| 3 | [Gesture CPU Audit](./phase-03-gesture-cpu-audit.md) | Pending |
| 4 | [Memory & Alloc Audit](./phase-04-memory-alloc-audit.md) | Pending |
| 5 | [Apply Fixes](./phase-05-apply-fixes.md) | Pending |
| 6 | [Verify & Regression](./phase-06-verify-regression.md) | Pending |

## Known suspects (from file inventory)

- `GestureEngine` (506 LOC) — per-touch event processing; check for
  per-event allocations, timer polling, unnecessary AX calls.
- `Multitouch` — private MultitouchSupport framework callback; verify
  callback does minimal work on its thread.
- `WindowControl` — AXUIElement window moves: each call is an IPC to the
  target app — the main latency source; check batching/throttling.
- `Bezel` — overlay UI; check for opaque windows / continuous redraw.
- `SettingsView` SwiftUI — only alive when open; verify released on close.

## Success Criteria

- [ ] `sample`/`top` shows 0% CPU while idle for 30s
- [ ] Gesture → first AX move call < 16ms (timestamped)
- [ ] `leaks` clean; footprint stable after 5min gesture-heavy use
- [ ] All gestures still work: snap halves/quarters, maximize, move/resize

<!-- slug: swishlite-perf-audit -->
