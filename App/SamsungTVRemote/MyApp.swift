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

/// The Siri and Shortcuts actions live in the package. Without this registration the system wouldn't find them.
struct TVAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [TVRemoteIntents.self]
    }
}
