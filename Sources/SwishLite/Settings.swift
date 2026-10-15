import Foundation

/// Persisted settings, mirroring Swish's preferences.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin") } }
    @Published var animationDuration: Double { didSet { d.set(animationDuration, forKey: "animationDuration") } }
    @Published var gridSpacing: Double { didSet { d.set(gridSpacing, forKey: "gridSpacing") } }
    @Published var dragToUnsnap: Bool { didSet { d.set(dragToUnsnap, forKey: "dragToUnsnap") } }
    @Published var superModifierEnabled: Bool { didSet { d.set(superModifierEnabled, forKey: "superModifierEnabled") } }
    @Published var superModifier: String { didSet { d.set(superModifier, forKey: "superModifier") } }

    private init() {
        d.register(defaults: [
            "enabled": true, "launchAtLogin": false, "animationDuration": 0.25,
            "gridSpacing": 0.0, "dragToUnsnap": true,
            "superModifierEnabled": false, "superModifier": "fn",
        ])
        enabled = d.bool(forKey: "enabled")
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        animationDuration = d.double(forKey: "animationDuration")
        gridSpacing = d.double(forKey: "gridSpacing")
        dragToUnsnap = d.bool(forKey: "dragToUnsnap")
        superModifierEnabled = d.bool(forKey: "superModifierEnabled")
        superModifier = d.string(forKey: "superModifier") ?? "fn"
    }
}
