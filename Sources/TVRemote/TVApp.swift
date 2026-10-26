import SwiftUI

/// An app installed on the TV (from the `ed.installedApp.get` event).
nonisolated struct TVApp: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    /// Tizen type: 2 = a regular Smart Hub app, others (browser, Gallery…) are system apps.
    let type: Int

    /// Launch method the TV expects for the given app type.
    var launchAction: String { type == 2 ? "DEEP_LINK" : "NATIVE_LAUNCH" }

    /// Stable tile colour derived from the name so apps are recognisable even without an icon.
    var tint: Color {
        let hue = Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }

    var initial: String { String(name.prefix(1)).uppercased() }
}
