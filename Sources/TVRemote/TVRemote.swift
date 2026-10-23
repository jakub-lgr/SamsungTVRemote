import AppIntents
import SwiftUI

// Veřejné rozhraní balíčku. Všechno ostatní je interní, aplikace, která ovladač vkládá,
// potřebuje jen hlavní obrazovku, údaje pro rozcestník a registraci akcí pro Siri.

/// Údaje o ovladači pro rozcestník.
public enum TVRemote {
    public static let name = "TV Ovladač"
    public static let systemImage = "appletvremote.gen4.fill"
    public static let tint = Color(red: 0.2, green: 0.45, blue: 0.95)

    /// Volá se, když se změní seznam aplikací z televize, který Siri nabízí ve frázi „Open … on the TV“.
    ///
    /// Fráze pro Siri (`AppShortcutsProvider`) Xcode najde jen v targetu aplikace, ne v balíčku.
    /// Aplikace je proto definuje sama a sem dosadí `updateAppShortcutParameters()` svého providera.
    public static var appShortcutParametersChanged: () -> Void = {}
}

/// Celá obrazovka ovladače. Spojení s televizí naváže sama a při zmizení ho zase ukončí.
public struct TVRemoteView: View {
    public init() {}

    public var body: some View {
        ContentView()
            .environment(SamsungTVClient.shared)
            .preferredColorScheme(.dark)
    }
}

/// Akce pro Siri a Zkratky. Aplikace je musí zaregistrovat ve vlastním `AppIntentsPackage`
/// (`includedPackages`), jinak je systém v balíčku nenajde. Hotové fráze pro Siri
/// (akce `SetTVVolumeIntent`, `MuteTVIntent`…) si aplikace skládá ve svém `AppShortcutsProvider`.
public struct TVRemoteIntents: AppIntentsPackage {}
