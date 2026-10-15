import Cocoa
import ApplicationServices

enum Permissions {
    static func ensureAccessibility() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
    }
}
