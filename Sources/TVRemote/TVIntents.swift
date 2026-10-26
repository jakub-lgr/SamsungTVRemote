import AppIntents

// Actions for the Shortcuts app and Siri. They run in the background and don't open the app.

public struct SetTVVolumeIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Set TV Volume"
    public static let description = IntentDescription("Sets the TV volume to a specific number from 0 to 100.")

    @Parameter(title: "Volume", inclusiveRange: (0, 100))
    var level: Int

    public static var parameterSummary: some ParameterSummary {
        Summary("Set TV volume to \(\.$level)")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await reachingTV { try await SamsungTVClient.shared.setVolume(level) }
        return .result(dialog: "The TV volume is \(level).")
    }
}

public enum TVVolumeDirection: String, AppEnum {
    case up, down

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    public static let caseDisplayRepresentations: [TVVolumeDirection: DisplayRepresentation] = [
        .up: "Turn Up",
        .down: "Turn Down",
    ]
}

public struct AdjustTVVolumeIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Turn TV Volume Up or Down"
    public static let description = IntentDescription("Changes the TV volume by the given number of steps.")

    @Parameter(title: "Direction", default: .up)
    var direction: TVVolumeDirection

    @Parameter(title: "Steps", default: 5, inclusiveRange: (1, 50))
    var amount: Int

    public static var parameterSummary: some ParameterSummary {
        Summary("\(\.$direction) the TV by \(\.$amount)")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let level = try await reachingTV {
            let current = try await TVVolume(host: TVConfig.host).current()
            let target = direction == .up ? current + amount : current - amount
            try await SamsungTVClient.shared.setVolume(target)
            return min(max(target, TVVolume.range.lowerBound), TVVolume.range.upperBound)
        }
        return .result(dialog: "The TV volume is \(level).")
    }
}

public enum TVMuteAction: String, AppEnum {
    case mute, unmute, toggle

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sound"
    public static let caseDisplayRepresentations: [TVMuteAction: DisplayRepresentation] = [
        .mute: "Mute",
        .unmute: "Unmute",
        .toggle: "Toggle",
    ]
}

public struct MuteTVIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Mute TV"
    public static let description = IntentDescription("Mutes the TV, unmutes it, or toggles mute.")

    @Parameter(title: "Action", default: .toggle)
    var action: TVMuteAction

    public static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) the TV sound")
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
        return .result(dialog: muted ? "The TV is muted." : "The TV sound is on.")
    }
}

public struct TurnOffTVIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Turn Off TV"
    public static let description = IntentDescription("Turns the TV off.")

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = SamsungTVClient.shared
        do {
            try await client.waitUntilConnected()
        } catch {
            // An unreachable TV is almost always simply off.
            return .result(dialog: "The TV is already off.")
        }
        try await client.sendWhenConnected(.power)
        return .result(dialog: "Turning off the TV.")
    }
}

public struct TurnOnTVIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Turn On TV"
    public static let description = IntentDescription("Turns the TV on via Wake-on-LAN. \"Power On with Mobile\" must be enabled on the TV.")

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // Repeat the packet a few times; in deep sleep the TV sometimes misses it.
        for attempt in 0..<4 {
            if attempt > 0 { try await Task.sleep(for: .seconds(1)) }
            try WakeOnLAN.wake(mac: TVConfig.mac, ip: TVConfig.host)
        }
        return .result(dialog: "Turning on the TV.")
    }
}

public struct OpenTVAppIntent: AppIntent {
    public init() {}

    public static let title: LocalizedStringResource = "Open App on TV"
    public static let description = IntentDescription("Opens the chosen app on the TV, such as Netflix or YouTube.")

    @Parameter(title: "App")
    public var app: TVAppEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$app) on the TV")
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await reachingTV {
            try await SamsungTVClient.shared.launchWhenConnected(TVApp(id: app.id, name: app.name, type: app.type))
        }
        return .result(dialog: "Opening \(app.name).")
    }
}

/// Turns any network error into a clear message for Siri.
private func reachingTV<T>(_ work: () async throws -> T) async throws -> T {
    do {
        return try await work()
    } catch {
        throw SamsungTVClient.Failure.unreachable
    }
}

// MARK: - App as a parameter

public struct TVAppEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "TV App"
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

/// Takes apps from the last list loaded from the TV; pinned ones are offered first.
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
