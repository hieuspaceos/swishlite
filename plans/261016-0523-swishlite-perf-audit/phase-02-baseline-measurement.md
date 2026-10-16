---
title: "Phase 2: Baseline Measurement"
status: todo
---

# Phase 2: Baseline Measurement

## Overview

Quantify idle CPU, gesture latency, and memory before any change.

## Requirements

- [x] Idle CPU over 30s
- [x] Footprint idle + during gestures + after
- [x] Gesture→AX-call latency (timestamps)
- [x] leaks after gesture-heavy session

## Implementation Steps

1. Find PID: `pgrep -f SwishLite`.
2. Idle CPU:
   ```sh
   top -pid <pid> -l 30 -s 1 -stats cpu | awk 'NR>8 {s+=$1} END {print s/30"% avg"}'
   ```
3. Footprint: `footprint <pid>` at idle; repeat while performing ~20
   gestures (snap windows); repeat 60s after.
4. Latency: add `NSLog("T0 gesture")` at Multitouch callback entry and
   `NSLog("T1 axmove")` before the AX position/size call in WindowControl;
   measure delta via `log stream --process SwishLite`.
5. `leaks <pid>` after the gesture session.
6. Write `reports/baseline.md`.

## Success Criteria

`reports/baseline.md` contains numbers for all four metrics.
