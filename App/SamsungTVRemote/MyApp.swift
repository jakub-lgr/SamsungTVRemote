import AppIntents
import SwiftUI
import TVRemote

@main struct MyApp: App {
    init() {
        TVRemote.appShortcutParametersChanged = { TVShortcuts.updateAppShortcutParameters() }
    }

    var body: some Scene {
        WindowGroup {
            TVRemoteView()
        }
    }
}

/// Akce pro Siri a Zkratky jsou v balíčku. Bez této registrace by je systém nenašel.
struct TVAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [TVRemoteIntents.self]
    }
}
