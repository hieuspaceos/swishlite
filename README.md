# SwishLite

A [Swish](https://highlyopinionated.co/swish/)-inspired trackpad gesture tool
for macOS window management. Menubar agent app (no Dock icon), built with
Swift, AppKit, Accessibility APIs and a `CGEventTap`. No third-party
dependencies.

Snap windows by swiping on their **title bar** — the same two-stage gesture
model as Swish: halves → thirds/quarters.

## Gestures

All gestures are performed with **two fingers on the title bar** of a window
(hold the *Super modifier* — default `fn` — to gesture anywhere on the
window).

| Gesture | Action |
|---|---|
| Swipe ← / → | Snap left / right half |
| Swipe ← ← / → → | Snap left / right **two-thirds** |
| Swipe ← then → (or → then ←) | Snap **one-third** (in second direction) |
| Swipe → then ↑ (etc.) | Top-right quarter — all four corners likewise |
| Swipe ↑ | Maximize |
| Swipe ↓ | Minimize |
| Swipe ↑ then ↑ | Top half · Swipe ↓ then ↓ → bottom half |
| Swipe ↑ on a minimized window | Restore it from the Dock |
| Pinch in | Quit the app |
| Pinch out | Maximize |
| Double-tap title bar | Restore / unsnap |
| Drag title bar | Move window; dragging a snapped window unsnaps it |

A bezel overlay shows the target zone and haptic feedback fires on each
committed gesture.

### Dock-icon gestures

Performed while hovering an app's **Dock icon**:

| Gesture | Action |
|---|---|
| Swipe ↓ | Minimize all of that app's windows |
| Swipe ↑ | Restore all of that app's windows + activate |
| Pinch in | Quit the app |
| Pinch out | Restore all of that app's windows |

## Install

Prebuilt app (arm64, macOS 14+):

1. Download **SwishLite.zip** from the
   [latest release](https://github.com/hieuspaceos/swishlite/releases/latest).
2. Unzip and drag `SwishLite.app` into `/Applications`.
3. The app is ad-hoc signed — if Gatekeeper blocks it, right-click → Open,
   or run `xattr -dr com.apple.quarantine /Applications/SwishLite.app`.
4. Launch; grant **Accessibility** when prompted, then quit & relaunch.

## Build from source

```sh
./build-app.sh     # builds build/SwishLite.app (ad-hoc signed)
open build/SwishLite.app
```

Or via SwiftPM while developing:

```sh
swift build -c release
# binary lands in .build/release/SwishLite — run the .app for real use
```

Requires an Xcode/Swift toolchain, arm64, macOS 14+.

> **Note:** the binary links `MultitouchSupport.framework` via `unsafeFlags`
> in `Package.swift`, so a plain `swiftc` invocation won't resolve it — use
> `swift build` or `build-app.sh`.

## Permissions

**Accessibility** is required — SwishLite moves other apps' windows via the
AX API and reads system gesture events through a `CGEventTap`. On first
launch macOS prompts for it; grant under
*System Settings → Privacy & Security → Accessibility*, then quit & relaunch.

Because the app is ad-hoc signed, macOS may tie the grant to the binary —
if gestures stop working after a rebuild, remove and re-add SwishLite in
Accessibility settings.

## Settings

Menubar icon → **Settings…**:

- **Enable SwishLite**, **Launch at login**
- **Animation duration** (0–0.5 s) for snap moves
- **Grid spacing** — padding between windows and screen edges
- **Drag to unsnap / move**
- **Super modifier** — hold `fn` (configurable) to gesture over the whole
  window instead of just the title bar

## Notes / limitations

- Menubar-area gestures are listed in Settings but not yet implemented.
- Two-stage combos reset after ~1 s of inactivity.
- Zones apply to the screen containing the window.
## Security & trust

- **Open source** — every byte of the release binary is produced from the
  commit you can read, by GitHub Actions (see the workflow run linked in
  each release). No opaque build steps.
- **Checksums** — every release ships `SwishLite.dmg.sha256`. Verify:
  ```sh
  shasum -a 256 SwishLite.dmg
  ```
- **No telemetry, no account, no network calls** — the app works fully
  offline; nothing leaves your Mac.
- **Permissions** — SwishLite asks for Accessibility + Input Monitoring (System Settings → Privacy & Security)
  and nothing else.
- **Ad-hoc signed** — not yet notarized (needs a paid Apple Developer
  account). On first launch macOS shows "cannot be opened because the
  developer cannot be verified" — right-click → **Open** once, then it
  runs normally forever after.
- **Prefer building yourself?** `git clone`, `make`, `make run` —
  no external dependencies, readable in one sitting.
