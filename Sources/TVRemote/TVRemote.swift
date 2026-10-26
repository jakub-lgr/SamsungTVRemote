import AppIntents
import SwiftUI

// The package's public interface. Everything else is internal: an app embedding the remote
// only needs the main screen, metadata for a launcher and the Siri action registration.

/// Remote metadata for a launcher.
public enum TVRemote {
    public static let name = "TV Remote"
    public static let systemImage = "appletvremote.gen4.fill"
    public static let tint = Color(red: 0.2, green: 0.45, blue: 0.95)

    /// Called when the TV's app list changes, which Siri offers in the phrase "Open … on the TV".
    ///
    /// Xcode only finds Siri phrases (`AppShortcutsProvider`) in the app target, not in a package.
    /// The app therefore defines them itself and plugs its provider's `updateAppShortcutParameters()` in here.
    public static var appShortcutParametersChanged: () -> Void = {}
}

/// The full remote screen. It connects to the TV by itself and disconnects when it disappears.
public struct TVRemoteView: View {
    public init() {}

    public var body: some View {
        ContentView()
            .environment(SamsungTVClient.shared)
            .preferredColorScheme(.dark)
    }
}

/// Actions for Siri and Shortcuts. The app must register them in its own `AppIntentsPackage`
/// (`includedPackages`), otherwise the system won't find them in the package. The app builds
/// ready-made Siri phrases (actions `SetTVVolumeIntent`, `MuteTVIntent`…) in its `AppShortcutsProvider`.
public struct TVRemoteIntents: AppIntentsPackage {}
