import AppIntents
import TVRemote

/// Hotové zkratky. Xcode je v balíčku nenajde, proto jsou v aplikaci.
///
/// Siri česky neumí, proto jsou fráze anglicky; v aplikaci Zkratky jsou všechny akce česky
/// a dají se pojmenovat po svém.
struct TVShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MuteTVIntent(),
            phrases: ["Mute the TV with \(.applicationName)", "Toggle TV sound with \(.applicationName)"],
            shortTitle: "Ztlumit televizi",
            systemImageName: "speaker.slash.fill"
        )
        AppShortcut(
            intent: SetTVVolumeIntent(),
            phrases: ["Set TV volume with \(.applicationName)"],
            shortTitle: "Nastavit hlasitost",
            systemImageName: "speaker.wave.2.fill"
        )
        AppShortcut(
            intent: AdjustTVVolumeIntent(),
            phrases: ["Change TV volume with \(.applicationName)"],
            shortTitle: "Zesílit / zeslabit",
            systemImageName: "plus.forwardslash.minus"
        )
        AppShortcut(
            intent: TurnOffTVIntent(),
            phrases: ["Turn off the TV with \(.applicationName)"],
            shortTitle: "Vypnout televizi",
            systemImageName: "power"
        )
        AppShortcut(
            intent: TurnOnTVIntent(),
            phrases: ["Turn on the TV with \(.applicationName)"],
            shortTitle: "Zapnout televizi",
            systemImageName: "power"
        )
        AppShortcut(
            intent: OpenTVAppIntent(),
            phrases: ["Open \(\.$app) on the TV with \(.applicationName)", "Open an app on the TV with \(.applicationName)"],
            shortTitle: "Spustit aplikaci",
            systemImageName: "square.grid.2x2.fill"
        )
    }
}
