import AppIntents
import Foundation
import Observation

/// Spojení s televizí přes zabezpečený WebSocket na portu 8002.
///
/// Při prvním připojení televize zobrazí dotaz na povolení a po potvrzení pošle token,
/// který si uložíme do `TVConfig.token`. Další připojení už se neptají.
@Observable
final class SamsungTVClient {
    /// Jediná instance sdílená aplikací i Zkratkami/Siri.
    static let shared = SamsungTVClient()

    enum State: Equatable {
        case disconnected
        case connecting
        case waitingForApproval
        case connected
        case failed(String)
    }

    enum Failure: LocalizedError {
        case unreachable

        var errorDescription: String? {
            "Televize není dostupná. Je zapnutá a ve stejné Wi-Fi?"
        }
    }

    private(set) var state: State = .disconnected
    private(set) var isWaking = false
    /// Poslední známá hlasitost televize (0–100), `nil` dokud ji neznáme.
    private(set) var volume: Int?
    private(set) var isMuted: Bool?
    /// Televize právě ukazuje klávesnici (třeba v hledání) a čeká na text.
    private(set) var isTVKeyboardActive = false
    private(set) var installedApps: [TVApp] = TVConfig.knownApps
    var favoriteApps: [TVApp] = TVConfig.favoriteApps {
        didSet {
            TVConfig.favoriteApps = favoriteApps
            TVShortcuts.updateAppShortcutParameters()
        }
    }

    /// Jméno, pod kterým se aplikace ukáže na televizi. Délka je násobek 3,
    /// aby base64 nemělo `=` a nebylo ho potřeba escapovat v URL.
    private let clientName = "SamsungTVRemote"

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var lastSend: Task<Void, Never>?
    private var volumeRefreshTask: Task<Void, Never>?
    /// Zprávy odeslané během navazování spojení. Odešlou se, jakmile je spojení hotové.
    private var pending: [String] = []

    /// Zrcadlí `TVConfig.token`, aby na změnu mohlo reagovat UI.
    private(set) var hasToken = TVConfig.token != nil

    /// Uložené televize a ta, kterou ovladač právě ovládá.
    private(set) var savedTVs: [SavedTV] = TVConfig.savedTVs
    private(set) var currentTVID: String? = TVConfig.currentTV?.id
    var currentTV: SavedTV? { savedTVs.first { $0.id == currentTVID } }

    // MARK: - Televize

    /// Přepne ovladač na jinou uloženou televizi a připojí se k ní jejím vlastním tokenem.
    func select(_ id: String) {
        guard id != currentTVID else {
            connectIfNeeded()
            return
        }
        disconnect()
        TVConfig.currentTVID = id
        loadCurrentTV()
        connect()
    }

    /// Uloží novou nebo upravenou televizi. Když se jí změní IP adresa, token už neplatí.
    func save(_ tv: SavedTV, select shouldSelect: Bool = true) {
        var tvs = TVConfig.savedTVs
        var stored = tv
        if let index = tvs.firstIndex(where: { $0.id == tv.id }) {
            if tvs[index].host != tv.host { stored.token = nil }
            tvs[index] = stored
        } else {
            tvs.append(stored)
        }
        TVConfig.savedTVs = tvs
        let affectsCurrent = tv.id == currentTVID
        if shouldSelect && !affectsCurrent {
            select(tv.id)
        } else if affectsCurrent {
            // Upravená aktuální televize: připojíme se znovu s novými údaji.
            disconnect()
            loadCurrentTV()
            connect()
        } else {
            savedTVs = tvs
        }
    }

    /// Přidá televizi nalezenou v síti (nebo aktualizuje už uloženou) a přepne se na ni.
    func add(_ found: DiscoveredTV) {
        let existing = TVConfig.savedTVs.first { $0.id == found.id || $0.host == found.host }
        var tv = existing ?? SavedTV(id: found.id, name: found.name, host: found.host, mac: found.mac)
        tv.name = found.name
        tv.mac = found.mac.isEmpty ? tv.mac : found.mac
        tv.host = found.host
        save(tv)
    }

    func remove(_ id: String) {
        TVConfig.savedTVs.removeAll { $0.id == id }
        if id == currentTVID {
            disconnect()
            TVConfig.currentTVID = TVConfig.savedTVs.first?.id
            loadCurrentTV()
            if currentTV != nil { connect() }
        } else {
            savedTVs = TVConfig.savedTVs
        }
    }

    /// Načte údaje aktuální televize do vlastností, které sleduje UI.
    private func loadCurrentTV() {
        volumeRefreshTask?.cancel()
        savedTVs = TVConfig.savedTVs
        currentTVID = TVConfig.currentTV?.id
        hasToken = TVConfig.token != nil
        installedApps = TVConfig.knownApps
        favoriteApps = TVConfig.favoriteApps
        volume = nil
        isMuted = nil
    }

    // MARK: - Spojení

    func connectIfNeeded() {
        switch state {
        case .connected, .connecting, .waitingForApproval: return
        case .disconnected, .failed: connect()
        }
    }

    func connect() {
        let host = TVConfig.host
        guard TVConfig.isValidIPv4(host) else {
            state = .failed("Vyber v nastavení televizi.")
            return
        }
        teardown()

        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.port = 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        components.queryItems = [URLQueryItem(name: "name", value: Data(clientName.utf8).base64EncodedString())]
        if let token = TVConfig.token {
            components.queryItems?.append(URLQueryItem(name: "token", value: token))
        }
        guard let url = components.url else {
            state = .failed("Nepodařilo se sestavit adresu televize.")
            return
        }

        let session = URLSession(configuration: .ephemeral, delegate: TVCertificateTrust(host: host), delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        state = hasToken ? .connecting : .waitingForApproval
        task.resume()

        receiveTask = Task { await receiveLoop(task) }
        // Bez tokenu čeká televize na potvrzení uživatelem (sama to vzdá zhruba po 30 s).
        let timeout: Duration = hasToken ? .seconds(8) : .seconds(45)
        timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, task === self.task, state != .connected else { return }
            fail("Televize neodpovídá. Je zapnutá a ve stejné Wi-Fi?")
        }
    }

    func disconnect() {
        wakeTask?.cancel()
        wakeTask = nil
        isWaking = false
        teardown()
        pending.removeAll()
        isTVKeyboardActive = false
        state = .disconnected
    }

    /// Zapomene token, takže televize se při dalším připojení znovu zeptá.
    func forgetPairing() {
        storeToken(nil)
        disconnect()
    }

    /// Počká, než je spojení hotové, a když se to nepovede, vyhodí chybu. Pro Zkratky a Siri.
    func waitUntilConnected(timeout: Duration = .seconds(10)) async throws {
        connectIfNeeded()
        let deadline = ContinuousClock.now + timeout
        while state != .connected {
            if case .failed = state { throw Failure.unreachable }
            guard ContinuousClock.now < deadline else { throw Failure.unreachable }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func storeToken(_ token: String?) {
        TVConfig.token = token
        hasToken = token != nil
        savedTVs = TVConfig.savedTVs
    }

    private func teardown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        lastSend = nil
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func fail(_ message: String) {
        teardown()
        pending.removeAll()
        isTVKeyboardActive = false
        state = .failed(message)
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                guard task === self.task else { return }
                handle(message)
            }
        } catch {
            guard task === self.task else { return }
            fail(Self.describe(error))
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: return
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = json["event"] as? String else { return }

        switch event {
        case "ms.channel.connect":
            if let payload = json["data"] as? [String: Any], let token = payload["token"] {
                storeToken("\(token)")
            }
            timeoutTask?.cancel()
            state = .connected
            refreshVolume()
            let messages = pending
            pending.removeAll()
            messages.forEach(transmit)
        case "ms.channel.unauthorized":
            storeToken(nil)
            fail("Televize připojení odmítla. Zkus to znovu a na televizi zvol Povolit.")
        case "ms.channel.timeOut":
            fail("Připojení nebylo na televizi včas potvrzeno.")
        case "ms.remote.imeStart":
            isTVKeyboardActive = true
        case "ms.remote.imeEnd":
            isTVKeyboardActive = false
        case "ed.installedApp.get":
            if let payload = json["data"] as? [String: Any], let list = payload["data"] as? [[String: Any]] {
                updateInstalledApps(list)
            }
        default:
            break
        }
    }

    // MARK: - Odesílání

    private func emit(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        switch state {
        case .connected:
            transmit(text)
        case .connecting, .waitingForApproval:
            enqueue(text)
        case .disconnected, .failed:
            enqueue(text)
            connect()
        }
    }

    private func enqueue(_ text: String) {
        pending.append(text)
        if pending.count > 5 { pending.removeFirst() }
    }

    private func transmit(_ text: String) {
        guard let task else { return }
        // Každé odeslání čeká na předchozí, aby zprávy dorazily ve stejném pořadí, v jakém vznikly.
        let previous = lastSend
        lastSend = Task {
            await previous?.value
            do {
                try await task.send(.string(text))
            } catch {
                guard task === self.task else { return }
                // Spojení mezitím spadlo (třeba po uspání telefonu): připoj se znovu a zprávu pošli potom.
                pending = [text]
                connect()
            }
        }
    }

    /// Počká, až odejdou všechny dosud zařazené zprávy.
    private func flush() async {
        await lastSend?.value
    }

    // MARK: - Klávesy

    func send(_ key: TVKey) {
        if key == .volumeUp || key == .volumeDown || key == .mute {
            // Televize hlasitost změní až chvíli po klávese, stav proto načteme se zpožděním.
            refreshVolume(after: .milliseconds(500))
        }
        emit([
            "method": "ms.remote.control",
            "params": [
                "Cmd": "Click",
                "DataOfCmd": key.rawValue,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey",
            ],
        ])
    }

    /// Vypínač: zapnutou televizi vypne klávesou, nedostupnou zkusí probudit přes Wake-on-LAN.
    func power() {
        switch state {
        case .connected, .connecting, .waitingForApproval:
            send(.power)
        case .disconnected, .failed:
            wakeUp()
        }
    }

    /// Připojí se, pošle klávesu a počká na odeslání. Pro Zkratky a Siri.
    func sendWhenConnected(_ key: TVKey) async throws {
        try await waitUntilConnected()
        send(key)
        await flush()
    }

    // MARK: - Psaní textu

    /// Vloží text do pole, které je na televizi právě otevřené (hledání, přihlášení…), a potvrdí ho.
    func sendText(_ text: String) {
        emit([
            "method": "ms.remote.control",
            "params": [
                "Cmd": Data(text.utf8).base64EncodedString(),
                "DataOfCmd": "base64",
                "TypeOfRemote": "SendInputString",
            ],
        ])
        emit([
            "method": "ms.remote.control",
            "params": ["TypeOfRemote": "SendInputEnd"],
        ])
    }

    // MARK: - Aplikace

    func requestInstalledApps() {
        emit([
            "method": "ms.channel.emit",
            "params": ["event": "ed.installedApp.get", "to": "host"],
        ])
    }

    func launch(_ app: TVApp) {
        emit([
            "method": "ms.channel.emit",
            "params": [
                "event": "ed.apps.launch",
                "to": "host",
                "data": ["appId": app.id, "action_type": app.launchAction],
            ],
        ])
    }

    func launchWhenConnected(_ app: TVApp) async throws {
        try await waitUntilConnected()
        launch(app)
        await flush()
    }

    func isFavorite(_ app: TVApp) -> Bool {
        favoriteApps.contains { $0.id == app.id }
    }

    func toggleFavorite(_ app: TVApp) {
        if let index = favoriteApps.firstIndex(where: { $0.id == app.id }) {
            favoriteApps.remove(at: index)
        } else {
            favoriteApps.append(app)
        }
    }

    private func updateInstalledApps(_ list: [[String: Any]]) {
        let apps = list.compactMap { item -> TVApp? in
            guard let id = item["appId"] as? String, let name = item["name"] as? String else { return nil }
            return TVApp(id: id, name: name, type: (item["app_type"] as? Int) ?? 2)
        }
        installedApps = apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        TVConfig.knownApps = installedApps
        // Siri si tak obnoví seznam aplikací pro frázi „Open … on the TV“.
        TVShortcuts.updateAppShortcutParameters()
    }

    // MARK: - Hlasitost

    func refreshVolume(after delay: Duration = .zero) {
        let host = TVConfig.host
        guard TVConfig.isValidIPv4(host) else { return }
        volumeRefreshTask?.cancel()
        volumeRefreshTask = Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            let control = TVVolume(host: host)
            // Mezitím se mohla přepnout televize – stará hodnota by patřila jiné.
            guard !Task.isCancelled, let value = try? await control.current(), host == TVConfig.host else { return }
            volume = value
            if let muted = try? await control.isMuted(), !Task.isCancelled { isMuted = muted }
        }
    }

    /// Nastaví hlasitost přesně na zadané číslo (ořízne se na 0–100).
    func setVolume(_ value: Int) async throws {
        let clamped = min(max(value, TVVolume.range.lowerBound), TVVolume.range.upperBound)
        volumeRefreshTask?.cancel()
        try await TVVolume(host: TVConfig.host).set(clamped)
        volume = clamped
    }

    func setMuted(_ muted: Bool) async throws {
        volumeRefreshTask?.cancel()
        try await TVVolume(host: TVConfig.host).setMuted(muted)
        isMuted = muted
    }

    // MARK: - Wake-on-LAN

    func wakeUp() {
        guard !isWaking else { return }
        let host = TVConfig.host
        let mac = TVConfig.mac
        guard TVConfig.isValidMAC(mac) else {
            state = .failed("Pro zapnutí televize doplň v nastavení její MAC adresu.")
            return
        }
        do {
            try WakeOnLAN.wake(mac: mac, ip: host)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        isWaking = true
        wakeTask = Task {
            defer { isWaking = false }
            // Televizi chvíli trvá, než nahodí síť. Paket opakujeme a průběžně se zkoušíme připojit.
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled || state == .connected { return }
                try? WakeOnLAN.wake(mac: mac, ip: host)
                if state != .connecting && state != .waitingForApproval { connect() }
            }
            if state != .connected {
                state = .failed("Televize se nezapnula. Je na ní zapnuté „Zapnutí přes mobil“?")
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                return "Televize není dostupná. Je zapnutá a ve stejné Wi-Fi?"
            default:
                break
            }
        }
        if (error as NSError).domain == NSPOSIXErrorDomain {
            return "Televize není dostupná. Je zapnutá a ve stejné Wi-Fi?"
        }
        return "Spojení s televizí selhalo: \(error.localizedDescription)"
    }
}

/// Televize používá vlastní certifikát, kterému iOS nevěří. Přijmeme ho, ale jen pro IP adresu naší televize.
nonisolated final class TVCertificateTrust: NSObject, URLSessionDelegate {
    private let host: String

    init(host: String) {
        self.host = host
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host == host,
              let trust = space.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
