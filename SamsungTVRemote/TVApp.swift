import SwiftUI

/// Aplikace nainstalovaná na televizi (z události `ed.installedApp.get`).
nonisolated struct TVApp: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    /// Typ podle Tizenu: 2 = běžná aplikace ze Smart Hubu, ostatní (prohlížeč, Galerie…) jsou systémové.
    let type: Int

    /// Způsob spuštění, který televize u daného typu aplikace očekává.
    var launchAction: String { type == 2 ? "DEEP_LINK" : "NATIVE_LAUNCH" }

    /// Stálá barva dlaždice odvozená z názvu, ať se aplikace dají poznat i bez ikony.
    var tint: Color {
        let hue = Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }

    var initial: String { String(name.prefix(1)).uppercased() }
}
