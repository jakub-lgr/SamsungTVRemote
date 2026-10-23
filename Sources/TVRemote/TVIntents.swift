import AppIntents

// Akce pro aplikaci Zkratky a Siri. Běží na pozadí, aplikaci neotevírají.

public struct SetTVVolumeIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Nastavit hlasitost televize"
    public static let description = IntentDescription("Nastaví hlasitost televize na konkrétní číslo od 0 do 100.")

    @Parameter(title: "Hlasitost", inclusiveRange: (0, 100))
    var level: Int

    public static var parameterSummary: some ParameterSummary {
        Summary("Nastavit hlasitost televize na \(\.$level)")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await reachingTV { try await SamsungTVClient.shared.setVolume(level) }
        return .result(dialog: "Hlasitost televize je \(level).")
    }
}

public enum TVVolumeDirection: String, AppEnum {
    case up, down

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Směr"
    public static let caseDisplayRepresentations: [TVVolumeDirection: DisplayRepresentation] = [
        .up: "Zesílit",
        .down: "Zeslabit",
    ]
}

public struct AdjustTVVolumeIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Zesílit nebo zeslabit televizi"
    public static let description = IntentDescription("Změní hlasitost televize o zadaný počet stupňů.")

    @Parameter(title: "Směr", default: .up)
    var direction: TVVolumeDirection

    @Parameter(title: "O kolik", default: 5, inclusiveRange: (1, 50))
    var amount: Int

    public static var parameterSummary: some ParameterSummary {
        Summary("\(\.$direction) televizi o \(\.$amount)")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let level = try await reachingTV {
            let current = try await TVVolume(host: TVConfig.host).current()
            let target = direction == .up ? current + amount : current - amount
            try await SamsungTVClient.shared.setVolume(target)
            return min(max(target, TVVolume.range.lowerBound), TVVolume.range.upperBound)
        }
        return .result(dialog: "Hlasitost televize je \(level).")
    }
}

public enum TVMuteAction: String, AppEnum {
    case mute, unmute, toggle

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Zvuk"
    public static let caseDisplayRepresentations: [TVMuteAction: DisplayRepresentation] = [
        .mute: "Ztlumit",
        .unmute: "Zapnout zvuk",
        .toggle: "Přepnout",
    ]
}

public struct MuteTVIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Ztlumit televizi"
    public static let description = IntentDescription("Ztlumí televizi, zapne zvuk, nebo ztlumení přepne.")

    @Parameter(title: "Akce", default: .toggle)
    var action: TVMuteAction

    public static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) zvuk televize")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
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

public struct TurnOffTVIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Vypnout televizi"
    public static let description = IntentDescription("Vypne televizi.")

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
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

public struct TurnOnTVIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Zapnout televizi"
    public static let description = IntentDescription("Zapne televizi přes Wake-on-LAN. Na televizi musí být zapnuté „Zapnutí přes mobil“.")

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // Paket několikrát zopakujeme, televize ho v hlubokém spánku občas přeslechne.
        for attempt in 0..<4 {
            if attempt > 0 { try await Task.sleep(for: .seconds(1)) }
            try WakeOnLAN.wake(mac: TVConfig.mac, ip: TVConfig.host)
        }
        return .result(dialog: "Zapínám televizi.")
    }
}

public struct OpenTVAppIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Spustit aplikaci na televizi"
    public static let description = IntentDescription("Spustí na televizi vybranou aplikaci, třeba Netflix nebo YouTube.")

    @Parameter(title: "Aplikace")
    public var app: TVAppEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("Spustit \(\.$app) na televizi")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
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

public struct TVAppEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Aplikace na televizi"
    public static let defaultQuery = TVAppQuery()

    public let id: String
    let name: String
    let type: Int

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ app: TVApp) {
        id = app.id
        name = app.name
        type = app.type
    }
}

/// Aplikace bere z posledního seznamu načteného z televize; připnuté nabízí jako první.
public struct TVAppQuery: EntityStringQuery {
    public init() {}

    private var allApps: [TVApp] {
        let favorites = TVConfig.favoriteApps
        let others = TVConfig.knownApps.filter { app in !favorites.contains { $0.id == app.id } }
        return favorites + others
    }

    public func entities(for identifiers: [String]) async throws -> [TVAppEntity] {
        allApps.filter { identifiers.contains($0.id) }.map(TVAppEntity.init)
    }

    public func entities(matching string: String) async throws -> [TVAppEntity] {
        allApps.filter { $0.name.localizedStandardContains(string) }.map(TVAppEntity.init)
    }

    public func suggestedEntities() async throws -> [TVAppEntity] {
        allApps.map(TVAppEntity.init)
    }
}
