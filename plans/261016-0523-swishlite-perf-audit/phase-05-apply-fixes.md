---
title: "Phase 5: Apply Fixes"
status: done
---

# Phase 5: Apply Fixes

## Overview

Apply only fixes confirmed by Phases 3–4. Keep `./build-app.sh` green.

## Candidate fixes (conditional)

| # | Fix | Apply if |
|---|-----|----------|
| 1 | Coalesce AX writes to ≤60/s (or write only on gesture settle) | G3 confirmed |
| 2 | Cache window-under-cursor AX element per gesture session | G4 confirmed |
| 3 | Remove/zero-cost touch allocations in callback | G1 confirmed |
| 4 | Remove polling timers → pure event-driven | G2/G5 confirmed |
| 5 | Release settings window on close / lazily create | M1 confirmed |
| 6 | Clear gesture state on touch-up | M4 confirmed |

## Implementation Steps

1. One fix per edit; rebuild between fixes.
2. For AX coalescing: keep `pendingFrame` + `isWriting` flag; flush on
   16ms timer or when gesture ends.
3. For window caching: resolve AXUIElement once at gesture start; clear on
   gesture end.
4. Rebuild: `./build-app.sh`; reinstall if needed.

## Success Criteria

Every applied fix maps to a confirmed finding; build clean.
