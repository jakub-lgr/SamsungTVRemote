import Foundation

/// Uložená televize. Každá má vlastní adresu, token a oblíbené aplikace.
nonisolated struct SavedTV: Codable, Hashable, Identifiable, Sendable {
    /// ID zařízení z hledání v síti (`uuid:…`), u ručně přidaných náhodné UUID.
    var id: String
    var name: String
    var host: String
    var mac: String
    var token: String?
    var favoriteApps: [TVApp] = []
    var knownApps: [TVApp] = []
}

/// Nastavení uložené v UserDefaults.
///
/// `host`, `mac`, `token`, `favoriteApps` a `knownApps` patří vždy **aktuálně vybrané** televizi,
/// takže s nimi zbytek aplikace (i Zkratky) pracuje stejně, ať je televizí kolik chce.
nonisolated enum TVConfig {
    static let savedTVsKey = "tv.saved"
    static let currentTVKey = "tv.current"
    static let hardwareVolumeKey = "tv.hardwareVolume"

    // MARK: - Seznam televizí

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

    /// Upraví aktuální televizi a uloží změnu.
    private static func updateCurrent(_ change: (inout SavedTV) -> Void) {
        var tvs = savedTVs
        guard let id = currentTV?.id, let index = tvs.firstIndex(where: { $0.id == id }) else { return }
        change(&tvs[index])
        savedTVs = tvs
    }

    // MARK: - Aktuální televize

    static var host: String { currentTV?.host ?? "" }
    static var mac: String { currentTV?.mac ?? "" }

    /// Token, který televize vydá po potvrzení připojení. Bez něj se ptá znovu.
    static var token: String? {
        get { currentTV?.token }
        set { updateCurrent { $0.token = newValue } }
    }

    /// Aplikace připnuté na ovladači, v pořadí, v jakém se zobrazují.
    static var favoriteApps: [TVApp] {
        get { currentTV?.favoriteApps ?? [] }
        set { updateCurrent { $0.favoriteApps = newValue } }
    }

    /// Poslední načtený seznam aplikací z televize, aby ho měly i Zkratky bez připojení.
    static var knownApps: [TVApp] {
        get { currentTV?.knownApps ?? [] }
        set { updateCurrent { $0.knownApps = newValue } }
    }

    /// Ovládání hlasitosti televize bočními tlačítky iPhonu. Ve výchozím stavu zapnuté.
    static var hardwareVolumeEnabled: Bool {
        UserDefaults.standard.object(forKey: hardwareVolumeKey) as? Bool ?? true
    }

    // MARK: - Převod ze staršího nastavení

    /// Dřívější verze si pamatovala jen jednu televizi v samostatných klíčích.
    /// Převedeme ji do seznamu i s tokenem, aby se nemusela párovat znovu.
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

    // MARK: - Kontroly

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
