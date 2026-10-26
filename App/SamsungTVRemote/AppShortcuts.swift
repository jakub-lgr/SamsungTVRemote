import AppIntents
import TVRemote

/// Ready-made Siri shortcuts. Xcode doesn't find them in a package, so they live in the app.
struct TVShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MuteTVIntent(),
            phrases: ["Mute the TV with \(.applicationName)", "Toggle TV sound with \(.applicationName)"],
            shortTitle: "Mute TV",
            systemImageName: "speaker.slash.fill"
        )
        AppShortcut(
            intent: SetTVVolumeIntent(),
            phrases: ["Set TV volume with \(.applicationName)"],
            shortTitle: "Set Volume",
            systemImageName: "speaker.wave.2.fill"
        )
        AppShortcut(
            intent: AdjustTVVolumeIntent(),
            phrases: ["Change TV volume with \(.applicationName)"],
            shortTitle: "Volume Up / Down",
            systemImageName: "plus.forwardslash.minus"
        )
        AppShortcut(
            intent: TurnOffTVIntent(),
            phrases: ["Turn off the TV with \(.applicationName)"],
            shortTitle: "Turn Off TV",
            systemImageName: "power"
        )
        AppShortcut(
            intent: TurnOnTVIntent(),
            phrases: ["Turn on the TV with \(.applicationName)"],
            shortTitle: "Turn On TV",
            systemImageName: "power"
        )
        AppShortcut(
            intent: OpenTVAppIntent(),
            phrases: ["Open \(\.$app) on the TV with \(.applicationName)", "Open an app on the TV with \(.applicationName)"],
            shortTitle: "Open App",
            systemImageName: "square.grid.2x2.fill"
        )
    }
}
