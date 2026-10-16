---
title: "Phase 4: Memory & Alloc Audit"
status: done
---

# Phase 4: Memory & Alloc Audit

## Overview

34MB idle is fine but worth checking: menubar app + SwiftUI settings +
bezel windows should be ~25MB. Main risks: retained windows, retained
gesture state, leaked AXUIElement refs (CF objects — leaks catches them).

## Suspects

| # | Suspect | Where |
|---|---------|-------|
| M1 | SettingsView window retained after close | `AppDelegate.swift`, `SettingsView.swift` |
| M2 | Bezel panel(s) pre-created and never released | `Bezel.swift` |
| M3 | AXUIElement refs retained per window without release | `WindowControl.swift` |
| M4 | Gesture state objects growing (touch history arrays) | `GestureEngine.swift` |
| M5 | Multitouch registration callback capturing self strongly | `Multitouch.swift` |

## Implementation Steps

1. `leaks <pid>` after opening+closing Settings 3×.
2. `vmmap -summary` before/after a bezel show/hide cycle.
3. Grep `AXUIElement`, `CFRelease` usage — CF objects need explicit release
   under manual semantics; Swift bridges usually handle it via Unmanaged —
   verify.
4. Check touch history arrays are cleared on gesture end.
5. Write `reports/memory-findings.md`.

## Success Criteria

Every suspect confirmed or refuted with evidence.
