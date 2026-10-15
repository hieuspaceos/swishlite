import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case general = "General", windows = "Windows", snapping = "Snapping",
         apps = "Apps", menubar = "Menubar", advanced = "Advanced", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: "gearshape"
        case .windows: "macwindow"
        case .snapping: "square.grid.2x2"
        case .apps: "square.stack"
        case .menubar: "menubar.rectangle"
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        }
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var engine: GestureEngine
    @StateObject private var settings = Settings.shared
    @State private var pane: Pane = .snapping
    @State private var axGranted = AXIsProcessTrusted()

    var body: some View {
        HSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 2) {
                Text("SwishLite")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                ForEach(Pane.allCases) { p in
                    Button { pane = p } label: {
                        Label(p.rawValue, systemImage: p.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(pane == p ? Color.accentColor : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(pane == p ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
                Spacer()
            }
            .frame(minWidth: 200, maxWidth: 200)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))

            // Detail
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch pane {
                    case .general: general
                    case .windows: windows
                    case .snapping: snapping
                    case .apps: apps
                    case .menubar: menubar
                    case .advanced: advanced
                    case .about: about
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 460)
        }
        .frame(minWidth: 680, minHeight: 540)
        .task {
            while !Task.isCancelled {
                axGranted = AXIsProcessTrusted()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    // MARK: - Panes

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General").font(.largeTitle.bold())
            Text("SwishLite adds trackpad gestures for window management.")
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: axGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(axGranted ? .green : .orange)
                Text(axGranted ? "Accessibility permission granted"
                               : "Accessibility permission required")
                Spacer()
                if !axGranted {
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            Toggle("Enable SwishLite", isOn: $settings.enabled)
            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.launchAtLogin = $0; engine.setLaunchAtLogin($0) }))
            VStack(alignment: .leading) {
                Text("Animation duration: \(settings.animationDuration, specifier: "%.2f")s")
                Slider(value: $settings.animationDuration, in: 0...0.5)
            }
        }
    }

    private var windows: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Windows").font(.largeTitle.bold())
            Text("Control windows by gesturing on their title bar.")
                .foregroundStyle(.secondary)
            Toggle("Drag to unsnap / move", isOn: $settings.dragToUnsnap)
            Text("Drag a window by its title bar to move it. Dragging a snapped window unsnaps it.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            GestureRow(icon: "hand.point.up", name: "Drag", desc: "Move the window around freely.")
            GestureRow(icon: "arrow.up.and.down.and.arrow.left.and.right", name: "Scroll", desc: "Snap the window (see Snapping).")
        }
    }

    private var snapping: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Snapping").font(.largeTitle.bold())
            Text("Snap windows to a 2×2 or 3×2 grid. Unsnap by dragging or via the Center gesture.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading) {
                Text("Grid Spacing").font(.headline)
                Slider(value: $settings.gridSpacing, in: 0...24)
                Text("A small distance between windows and screen edges declutters the desktop.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Divider()
            GestureRow(icon: "circle", name: "Center & Unsnap", desc: "Double swipe down to unsnap and center a window.")
            GestureRow(icon: "arrow.up", name: "Maximize", desc: "Swipe up once to fill the desktop area.")
            GestureRow(icon: "arrow.left.arrow.right", name: "Halves", desc: "Swipe horizontally to snap to the left or right half.")
            GestureRow(icon: "arrow.up.arrow.down", name: "Vertical", desc: "Double-swipe vertically to snap to the top or bottom half.")
            GestureRow(icon: "square.grid.2x2", name: "Quarters", desc: "Swipe horizontally then vertically for a quarter.")
            GestureRow(icon: "rectangle.split.3x1", name: "Thirds", desc: "Double-swipe horizontally for thirds and two-thirds.")
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Apps").font(.largeTitle.bold())
            Text("Control running applications by gesturing on their dock icon.")
                .foregroundStyle(.secondary)
            GestureRow(icon: "arrow.left.arrow.right", name: "Cycle", desc: "Swipe left/right to cycle an app's windows.")
            GestureRow(icon: "arrow.down", name: "Minimize", desc: "Swipe down to minimize the frontmost window.")
            GestureRow(icon: "arrow.up", name: "Unminimize", desc: "Swipe up to unminimize the last window.")
            Text("Dock gestures require hovering the dock icon — coming next release.")
                .font(.callout).foregroundStyle(.orange)
        }
    }

    private var menubar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Menubar").font(.largeTitle.bold())
            Text("Invoke global convenience functions on the empty menubar area.")
                .foregroundStyle(.secondary)
            GestureRow(icon: "arrow.down", name: "Minimize", desc: "Swipe down on the menubar to minimize all windows.")
            GestureRow(icon: "arrow.up", name: "Unminimize", desc: "Swipe up to unminimize all windows.")
            Text("Menubar gestures — coming next release.")
                .font(.callout).foregroundStyle(.orange)
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Advanced").font(.largeTitle.bold())
            Section2("Keyboard") {
                Toggle("Super modifier (fn)", isOn: $settings.superModifierEnabled)
                Text("Hold the super modifier to gesture over the entire window area instead of the title bar only.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section2("Reset") {
                Button("Restore All Settings") { restoreDefaults() }
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SwishLite").font(.system(size: 44, weight: .bold))
            Text("A Swish-inspired window gesture tool.")
                .foregroundStyle(.secondary)
            Divider()
            Text("Version 0.1").font(.headline)
            Text("Built with Swift + AppKit/AX APIs. No private APIs.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func restoreDefaults() {
        let d = UserDefaults.standard
        ["enabled","launchAtLogin","animationDuration","gridSpacing","dragToUnsnap","superModifierEnabled","superModifier"]
            .forEach { d.removeObject(forKey: $0) }
        settings.enabled = true; settings.animationDuration = 0.25
        settings.gridSpacing = 0; settings.dragToUnsnap = true
        settings.superModifierEnabled = false
    }
}

struct Section2<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            content
        }
        .padding(.top, 4)
    }
}

struct GestureRow: View {
    let icon: String
    let name: String
    let desc: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            Text(name).font(.headline).frame(width: 140, alignment: .leading)
            Text(desc).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
