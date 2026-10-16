# Baseline — SwishLite, measured 2026-10-16 (pid 49281)

| Metric | Value |
|--------|-------|
| Idle CPU (5s sample) | **0.0%** — fully event-driven, no polling |
| Physical footprint | 34 MB |
| RSS | 55 MB |
| Leaks | 417 leaks / 20KB — all framework noise (XPC/AppIntents), zero SwishLite objects |

## Verdict

Idle is already optimal. The audit value is in the **gesture hot path**
(latency per touch event, AX IPC cost) and **allocations per gesture**.
Deferred: live latency numbers need interactive trackpad gestures.
