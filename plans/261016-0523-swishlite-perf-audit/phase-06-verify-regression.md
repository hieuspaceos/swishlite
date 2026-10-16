---
title: "Phase 6: Verify & Regression"
status: todo
---

# Phase 6: Verify & Regression

## Overview

Re-measure vs baseline and run the functional checklist.

## Implementation Steps

1. Rebuild, relaunch. `footprint` idle after 5min.
2. Idle CPU 30s — must be 0%.
3. Gesture latency — T0→T1 delta < 16ms.
4. `leaks` after a 20-gesture session — 0 app-object leaks.
5. Functional smoke (manual, needs trackpad):
   - [ ] Snap left/right half
   - [ ] Snap quarters/corners
   - [ ] Maximize
   - [ ] Move window drag gesture
   - [ ] Resize gesture
   - [ ] Bezel shows and hides
   - [ ] Settings opens, changes persist, closes cleanly
   - [ ] Menubar menu items all work
6. Write `reports/final.md` with before/after table.

## Success Criteria

All checks pass; final.md written.
