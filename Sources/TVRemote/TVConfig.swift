import Foundation

/// A saved TV. Each has its own address, token and favourite apps.
nonisolated struct SavedTV: Codable, Hashable, Identifiable, Sendable {
    /// Device ID from network discovery (`uuid:…`), a random UUID for manually added ones.
    var id: String
    var name: String
    var host: String
    var mac: String
    var token: String?
    var favoriteApps: [TVApp] = []
    var knownApps: [TVApp] = []
}

/// Settings stored in UserDefaults.
///
/// `host`, `mac`, `token`, `favoriteApps` and `knownApps` always belong to the **currently selected** TV,
/// so the rest of the app (and Shortcuts) works with them the same way however many TVs there are.
nonisolated enum TVConfig {
    static let savedTVsKey = "tv.saved"
    static let currentTVKey = "tv.current"
    static let hardwareVolumeKey = "tv.hardwareVolume"
    /// The launch argument `-tv.testHost <ip>` temporarily points the app elsewhere, e.g. at `Tools/faketv.py`.
    /// It's never written to the stored settings.
    static let testHostKey = "tv.testHost"

    // MARK: - TV list

    static var savedTVs: [SavedTV] {
        get {
            guard let data = UserDefaults.standard.data(forKey: savedTVsKey) else { return migrateSingleTV() }
            return (try? JSONDecoder().decode([SavedTV].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: savedTVsKey) }
    }

    static var currentTVID: String? {
        get { UserDefaults.standard.string(forKey: currentTVKey) }
        set { UserDefaults.standard.set(newValue, forKey: currentTVKey) }
    }

    static var currentTV: SavedTV? {
        let tvs = savedTVs
        return tvs.first { $0.id == currentTVID } ?? tvs.first
    }

    /// Modifies the current TV and saves the change.
    private static func updateCurrent(_ change: (inout SavedTV) -> Void) {
        var tvs = savedTVs
        guard let id = currentTV?.id, let index = tvs.firstIndex(where: { $0.id == id }) else { return }
        change(&tvs[index])
        savedTVs = tvs
    }

    // MARK: - Current TV

    static var host: String { UserDefaults.standard.string(forKey: testHostKey) ?? currentTV?.host ?? "" }
    static var mac: String { currentTV?.mac ?? "" }

    /// Token the TV issues once the connection is allowed. Without it, the TV asks again.
    static var token: String? {
        get { currentTV?.token }
        set { updateCurrent { $0.token = newValue } }
    }

    /// Apps pinned on the remote, in display order.
    static var favoriteApps: [TVApp] {
        get { currentTV?.favoriteApps ?? [] }
        set { updateCurrent { $0.favoriteApps = newValue } }
    }

    /// Last app list loaded from the TV, so Shortcuts have it even without a connection.
    static var knownApps: [TVApp] {
        get { currentTV?.knownApps ?? [] }
        set { updateCurrent { $0.knownApps = newValue } }
    }

    /// Controlling the TV volume with the iPhone's side buttons. On by default.
    static var hardwareVolumeEnabled: Bool {
        UserDefaults.standard.object(forKey: hardwareVolumeKey) as? Bool ?? true
    }

    // MARK: - Migrating older settings

    /// Earlier versions remembered just one TV in separate keys.
    /// Move it into the list together with its token so it doesn't need pairing again.
    private static func migrateSingleTV() -> [SavedTV] {
        let defaults = UserDefaults.standard
        let legacyKeys = ["tv.host", "tv.mac", "tv.name", "tv.token", "tv.favoriteApps", "tv.knownApps"]
        defer { legacyKeys.forEach(defaults.removeObject(forKey:)) }

        guard let host = defaults.string(forKey: "tv.host"), isValidIPv4(host) else { return [] }
        let decodeApps = { (key: String) -> [TVApp] in
            defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([TVApp].self, from: $0) } ?? []
        }
        let name = defaults.string(forKey: "tv.name") ?? ""
        let tv = SavedTV(
            id: UUID().uuidString,
            name: name.isEmpty ? "Samsung TV" : name,
            host: host,
            mac: defaults.string(forKey: "tv.mac") ?? "",
            token: defaults.string(forKey: "tv.token"),
            favoriteApps: decodeApps("tv.favoriteApps"),
            knownApps: decodeApps("tv.knownApps")
        )
        savedTVs = [tv]
        currentTVID = tv.id
        return [tv]
    }

    // MARK: - Validation

    static func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy(\.isNumber) && (Int(part) ?? 256) <= 255
        }
    }

    static func isValidMAC(_ value: String) -> Bool {
        value.filter(\.isHexDigit).count == 12
    }
}
