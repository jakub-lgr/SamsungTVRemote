import AppIntents
import Foundation
import Observation

/// Connection to the TV over a secure WebSocket on port 8002.
///
/// On the first connection the TV asks for permission and, once allowed, sends a token
/// that we store in `TVConfig.token`. Later connections no longer ask.
@Observable
final class SamsungTVClient {
    /// Single instance shared by the app and by Shortcuts/Siri.
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
            "The TV can't be reached. Is it on and on the same Wi-Fi?"
        }
    }

    private(set) var state: State = .disconnected
    private(set) var isWaking = false
    /// The connection dropped and the app is quietly restoring it. Instead of an error the UI only shows "Reconnecting…".
    private(set) var isReconnecting = false
    /// Last known TV volume (0–100), `nil` until we know it.
    private(set) var volume: Int?
    private(set) var isMuted: Bool?
    /// The TV is showing its keyboard (e.g. in search) and waiting for text.
    private(set) var isTVKeyboardActive = false
    private(set) var installedApps: [TVApp] = TVConfig.knownApps
    var favoriteApps: [TVApp] = TVConfig.favoriteApps {
        didSet {
            TVConfig.favoriteApps = favoriteApps
            TVRemote.appShortcutParametersChanged()
        }
    }

    /// Name the app shows up under on the TV. Its length is a multiple of 3
    /// so the base64 has no `=` that would need escaping in the URL.
    private let clientName = "SamsungTVRemote"

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var lastSend: Task<Void, Never>?
    private var volumeRefreshTask: Task<Void, Never>?
    /// Messages sent while connecting. They go out as soon as the connection is up.
    private var pending: [String] = []

    /// Mirrors `TVConfig.token` so the UI can react to changes.
    private(set) var hasToken = TVConfig.token != nil

    /// Saved TVs and the one the remote currently controls.
    private(set) var savedTVs: [SavedTV] = TVConfig.savedTVs
    private(set) var currentTVID: String? = TVConfig.currentTV?.id
    var currentTV: SavedTV? { savedTVs.first { $0.id == currentTVID } }

    // MARK: - TVs

    /// Switches the remote to another saved TV and connects with that TV's own token.
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

    /// Saves a new or edited TV. If its IP address changes, the token is no longer valid.
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
            // The current TV was edited: reconnect with the new details.
            disconnect()
            loadCurrentTV()
            connect()
        } else {
            savedTVs = tvs
        }
    }

    /// Adds a TV found on the network (or updates an already saved one) and switches to it.
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

    /// Loads the current TV's details into the properties the UI observes.
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

    // MARK: - Connection

    func connectIfNeeded() {
        switch state {
        case .connected, .connecting, .waitingForApproval: return
        case .disconnected, .failed: connect()
        }
    }

    func connect() {
        let host = TVConfig.host
        guard TVConfig.isValidIPv4(host) else {
            state = .failed("Choose a TV in Settings.")
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
            state = .failed("Couldn't build the TV's address.")
            return
        }

        let session = URLSession(configuration: .ephemeral, delegate: TVCertificateTrust(host: host), delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        state = hasToken ? .connecting : .waitingForApproval
        task.resume()

        receiveTask = Task { await receiveLoop(task) }
        // Without a token the TV waits for the user to allow it (it gives up after about 30 s).
        let timeout: Duration = hasToken ? .seconds(8) : .seconds(45)
        timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, task === self.task, state != .connected else { return }
            fail("The TV isn't responding. Is it on and on the same Wi-Fi?")
        }
    }

    func disconnect() {
        wakeTask?.cancel()
        wakeTask = nil
        isWaking = false
        stopReconnecting()
        teardown()
        pending.removeAll()
        isTVKeyboardActive = false
        state = .disconnected
    }

    /// Forgets the token, so the TV asks again on the next connection.
    func forgetPairing() {
        storeToken(nil)
        disconnect()
    }

    /// Waits until connected and throws if that fails. For Shortcuts and Siri.
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
        pingTask?.cancel()
        pingTask = nil
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
        // While reconnecting, pressed keys wait and go out once the connection is back.
        if !isReconnecting { pending.removeAll() }
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
            if state == .connected {
                connectionLost()
            } else {
                fail(Self.describe(error))
            }
        }
    }

    // MARK: - Reconnecting

    /// An established connection dropped (the TV closed it, Wi-Fi blinked…).
    /// Quietly retry with growing delays and only show an error if that fails.
    private func connectionLost() {
        guard !isReconnecting else { return }
        teardown()
        isTVKeyboardActive = false
        isReconnecting = true
        state = .connecting
        reconnectTask = Task {
            for delay in [0.3, 1, 2, 4, 8] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                if state != .connected { connect() }
                while state == .connecting || state == .waitingForApproval {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                }
                if state == .connected {
                    isReconnecting = false
                    return
                }
            }
            isReconnecting = false
            pending.removeAll()
            state = .failed("Lost the connection to the TV. Is it on and on the same Wi-Fi?")
        }
    }

    private func stopReconnecting() {
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
    }

    /// A regular ping keeps the connection alive and detects an outage before the next key press does.
    private func startPinging(_ task: URLSessionWebSocketTask) {
        pingTask?.cancel()
        let taskID = ObjectIdentifier(task)
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, task === self.task else { return }
                task.sendPing { error in
                    guard error != nil else { return }
                    Task { @MainActor in SamsungTVClient.shared.pingFailed(taskID) }
                }
            }
        }
    }

    private func pingFailed(_ taskID: ObjectIdentifier) {
        guard let task, ObjectIdentifier(task) == taskID, state == .connected else { return }
        connectionLost()
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
            if let task { startPinging(task) }
            refreshVolume()
            let messages = pending
            pending.removeAll()
            messages.forEach(transmit)
        case "ms.channel.unauthorized":
            storeToken(nil)
            fail("The TV refused the connection. Try again and choose Allow on the TV.")
        case "ms.channel.timeOut":
            fail("The connection wasn't allowed on the TV in time.")
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

    // MARK: - Sending

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
        // Each send waits for the previous one so messages arrive in the order they were created.
        let previous = lastSend
        lastSend = Task {
            await previous?.value
            do {
                try await task.send(.string(text))
            } catch {
                guard task === self.task else { return }
                // The connection dropped meanwhile (e.g. after the phone slept): restore it and send the message afterwards.
                pending.append(text)
                if state == .connected { connectionLost() } else { connect() }
            }
        }
    }

    /// Waits until all queued messages have gone out.
    private func flush() async {
        await lastSend?.value
    }

    // MARK: - Keys

    /// `Click` is a plain tap. `Press` and `Release` hold the key like a physical remote;
    /// the TV uses the hold length to detect a long press (e.g. OK opens programme info).
    enum KeyCommand: String {
        case click = "Click"
        case press = "Press"
        case release = "Release"
    }

    func send(_ key: TVKey, _ command: KeyCommand = .click) {
        if command != .press && (key == .volumeUp || key == .volumeDown || key == .mute) {
            // The TV changes the volume a moment after the key, so read the state with a delay.
            refreshVolume(after: .milliseconds(500))
        }
        emit([
            "method": "ms.remote.control",
            "params": [
                "Cmd": command.rawValue,
                "DataOfCmd": key.rawValue,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey",
            ],
        ])
    }

    /// Start (`true`) or end (`false`) of holding a key.
    func hold(_ key: TVKey, _ isDown: Bool) {
        send(key, isDown ? .press : .release)
    }

    /// Power button: turns a running TV off with the key, tries to wake an unreachable one via Wake-on-LAN.
    func power() {
        switch state {
        case .connected, .connecting, .waitingForApproval:
            send(.power)
        case .disconnected, .failed:
            wakeUp()
        }
    }

    /// Connects, sends the key and waits until it's sent. For Shortcuts and Siri.
    func sendWhenConnected(_ key: TVKey) async throws {
        try await waitUntilConnected()
        send(key)
        await flush()
    }

    // MARK: - Typing

    /// Puts text into the field currently open on the TV (search, sign-in…) and confirms it.
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

    // MARK: - Apps

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
        // Lets Siri refresh the app list for the phrase "Open … on the TV".
        TVRemote.appShortcutParametersChanged()
    }

    // MARK: - Volume

    func refreshVolume(after delay: Duration = .zero) {
        let host = TVConfig.host
        guard TVConfig.isValidIPv4(host) else { return }
        volumeRefreshTask?.cancel()
        volumeRefreshTask = Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            let control = TVVolume(host: host)
            // The TV may have been switched meanwhile – a stale value would belong to another one.
            guard !Task.isCancelled, let value = try? await control.current(), host == TVConfig.host else { return }
            volume = value
            if let muted = try? await control.isMuted(), !Task.isCancelled { isMuted = muted }
        }
    }

    /// Sets the volume to exactly the given number (clamped to 0–100).
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
            state = .failed("To turn the TV on, add its MAC address in Settings.")
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
            // The TV takes a while to bring up its network. Repeat the packet and keep trying to connect.
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled || state == .connected { return }
                try? WakeOnLAN.wake(mac: mac, ip: host)
                if state != .connecting && state != .waitingForApproval { connect() }
            }
            if state != .connected {
                state = .failed("The TV didn't turn on. Is \"Power On with Mobile\" enabled on it?")
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                return "The TV can't be reached. Is it on and on the same Wi-Fi?"
            default:
                break
            }
        }
        if (error as NSError).domain == NSPOSIXErrorDomain {
            return "The TV can't be reached. Is it on and on the same Wi-Fi?"
        }
        return "Connection to the TV failed: \(error.localizedDescription)"
    }
}

/// The TV uses its own certificate that iOS doesn't trust. Accept it, but only for our TV's IP address.
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
