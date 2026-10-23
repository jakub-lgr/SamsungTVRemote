import AppIntents

// Akce pro aplikaci Zkratky a Siri. Běží na pozadí, aplikaci neotevírají.

struct SetTVVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Nastavit hlasitost televize"
    static let description = IntentDescription("Nastaví hlasitost televize na konkrétní číslo od 0 do 100.")

    @Parameter(title: "Hlasitost", inclusiveRange: (0, 100))
    var level: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Nastavit hlasitost televize na \(\.$level)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await reachingTV { try await SamsungTVClient.shared.setVolume(level) }
        return .result(dialog: "Hlasitost televize je \(level).")
    }
}

enum TVVolumeDirection: String, AppEnum {
    case up, down

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Směr"
    static let caseDisplayRepresentations: [TVVolumeDirection: DisplayRepresentation] = [
        .up: "Zesílit",
        .down: "Zeslabit",
    ]
}

struct AdjustTVVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Zesílit nebo zeslabit televizi"
    static let description = IntentDescription("Změní hlasitost televize o zadaný počet stupňů.")

    @Parameter(title: "Směr", default: .up)
    var direction: TVVolumeDirection

    @Parameter(title: "O kolik", default: 5, inclusiveRange: (1, 50))
    var amount: Int

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$direction) televizi o \(\.$amount)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let level = try await reachingTV {
            let current = try await TVVolume(host: TVConfig.host).current()
            let target = direction == .up ? current + amount : current - amount
            try await SamsungTVClient.shared.setVolume(target)
            return min(max(target, TVVolume.range.lowerBound), TVVolume.range.upperBound)
        }
        return .result(dialog: "Hlasitost televize je \(level).")
    }
}

enum TVMuteAction: String, AppEnum {
    case mute, unmute, toggle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Zvuk"
    static let caseDisplayRepresentations: [TVMuteAction: DisplayRepresentation] = [
        .mute: "Ztlumit",
        .unmute: "Zapnout zvuk",
        .toggle: "Přepnout",
    ]
}

struct MuteTVIntent: AppIntent {
    static let title: LocalizedStringResource = "Ztlumit televizi"
    static let description = IntentDescription("Ztlumí televizi, zapne zvuk, nebo ztlumení přepne.")

    @Parameter(title: "Akce", default: .toggle)
    var action: TVMuteAction

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) zvuk televize")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let muted = try await reachingTV {
            let target: Bool
            switch action {
            case .mute: target = true
            case .unmute: target = false
            case .toggle: target = !(try await TVVolume(host: TVConfig.host).isMuted())
            }
            try await SamsungTVClient.shared.setMuted(target)
            return target
        }
        return .result(dialog: muted ? "Televize je ztlumená." : "Zvuk televize je zapnutý.")
    }
}

struct TurnOffTVIntent: AppIntent {
    static let title: LocalizedStringResource = "Vypnout televizi"
    static let description = IntentDescription("Vypne televizi.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = SamsungTVClient.shared
        do {
            try await client.waitUntilConnected()
        } catch {
            // Nedostupná televize je skoro vždycky prostě vypnutá.
            return .result(dialog: "Televize už je vypnutá.")
        }
        try await client.sendWhenConnected(.power)
        return .result(dialog: "Vypínám televizi.")
    }
}

struct TurnOnTVIntent: AppIntent {
    static let title: LocalizedStringResource = "Zapnout televizi"
    static let description = IntentDescription("Zapne televizi přes Wake-on-LAN. Na televizi musí být zapnuté „Zapnutí přes mobil“.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Paket několikrát zopakujeme, televize ho v hlubokém spánku občas přeslechne.
        for attempt in 0..<4 {
            if attempt > 0 { try await Task.sleep(for: .seconds(1)) }
            try WakeOnLAN.wake(mac: TVConfig.mac, ip: TVConfig.host)
        }
        return .result(dialog: "Zapínám televizi.")
    }
}

struct OpenTVAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Spustit aplikaci na televizi"
    static let description = IntentDescription("Spustí na televizi vybranou aplikaci, třeba Netflix nebo YouTube.")

    @Parameter(title: "Aplikace")
    var app: TVAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Spustit \(\.$app) na televizi")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await reachingTV {
            try await SamsungTVClient.shared.launchWhenConnected(TVApp(id: app.id, name: app.name, type: app.type))
        }
        return .result(dialog: "Spouštím \(app.name).")
    }
}

/// Jakoukoli síťovou chybu převede na srozumitelné hlášení pro Siri.
private func reachingTV<T>(_ work: () async throws -> T) async throws -> T {
    do {
        return try await work()
    } catch {
        throw SamsungTVClient.Failure.unreachable
    }
}

// MARK: - Aplikace jako parametr

struct TVAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Aplikace na televizi"
    static let defaultQuery = TVAppQuery()

    let id: String
    let name: String
    let type: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ app: TVApp) {
        id = app.id
        name = app.name
        type = app.type
    }
}

/// Aplikace bere z posledního seznamu načteného z televize; připnuté nabízí jako první.
struct TVAppQuery: EntityStringQuery {
    private var allApps: [TVApp] {
        let favorites = TVConfig.favoriteApps
        let others = TVConfig.knownApps.filter { app in !favorites.contains { $0.id == app.id } }
        return favorites + others
    }

    func entities(for identifiers: [String]) async throws -> [TVAppEntity] {
        allApps.filter { identifiers.contains($0.id) }.map(TVAppEntity.init)
    }

    func entities(matching string: String) async throws -> [TVAppEntity] {
        allApps.filter { $0.name.localizedStandardContains(string) }.map(TVAppEntity.init)
    }

    func suggestedEntities() async throws -> [TVAppEntity] {
        allApps.map(TVAppEntity.init)
    }
}

// MARK: - Siri

/// Hotové zkratky. Siri česky neumí, proto jsou fráze anglicky; v aplikaci Zkratky
/// jsou všechny akce česky a dají se pojmenovat po svém.
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
