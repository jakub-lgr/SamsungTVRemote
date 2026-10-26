import SwiftUI

struct ContentView: View {
    /// Panels that slide up over the remote.
    private enum Panel: String, Identifiable {
        case settings, volume, numbers, text, apps
        var id: String { rawValue }
    }

    @Environment(SamsungTVClient.self) private var tv
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(TVConfig.hardwareVolumeKey) private var hardwareVolume = true
    @State private var panel: Panel?
    @State private var volumeButtons = VolumeButtonObserver()

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                if !tv.favoriteApps.isEmpty {
                    FavoriteAppsStrip(apps: tv.favoriteApps) { tv.launch($0) }
                        .padding(.top, 14)
                }
                Spacer(minLength: 12)
                // On smaller iPhones the pad shrinks so everything else fits.
                DirectionPad(
                    size: min(260, max(190, proxy.size.height - 522)),
                    onPress: { tv.send($0) },
                    onHold: { tv.hold($0, $1) }
                )
                Spacer(minLength: 12)
                HStack(spacing: 28) {
                    RemoteKey(systemImage: "arrow.uturn.backward", title: "Back", action: { tv.send(.back) }, hold: { tv.hold(.back, $0) })
                    RemoteKey(systemImage: "house.fill", title: "Home", action: { tv.send(.home) }, hold: { tv.hold(.home, $0) })
                    RemoteKey(systemImage: "rectangle.portrait.and.arrow.right", title: "Source", action: { tv.send(.source) }, hold: { tv.hold(.source, $0) })
                }
                Spacer(minLength: 12)
                HStack(alignment: .center) {
                    Rocker(title: "VOL", upImage: "plus", downImage: "minus") { tv.send($0 ? .volumeUp : .volumeDown) }
                    Spacer()
                    VStack(spacing: 18) {
                        VolumeBadge(volume: tv.volume, isMuted: tv.isMuted == true) { panel = .volume }
                        RemoteKey(
                            systemImage: tv.isMuted == true ? "speaker.slash.fill" : "speaker.slash",
                            title: tv.isMuted == true ? "Muted" : "Mute",
                            fill: tv.isMuted == true ? .red.opacity(0.85) : Color(white: 0.2),
                            action: { tv.send(.mute) },
                            hold: { tv.hold(.mute, $0) }
                        )
                    }
                    Spacer()
                    Rocker(title: "CH", upImage: "chevron.up", downImage: "chevron.down") { tv.send($0 ? .channelUp : .channelDown) }
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 12)
                ColorKeys(onPress: { tv.send($0) }, onHold: { tv.hold($0, $1) })
                    .padding(.bottom, 12)
                bottomBar
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            LinearGradient(colors: [Color(white: 0.13), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .background {
            if hardwareVolume {
                SystemVolumeView(observer: volumeButtons)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $panel) { panel in
            switch panel {
            case .settings: SettingsView()
            case .volume: VolumeSheet()
            case .numbers: NumberPadSheet()
            case .text: TextInputSheet()
            case .apps: AppsSheet()
            }
        }
        .onAppear {
            if tv.currentTV == nil { panel = .settings }
            volumeButtons.onPress = { up in tv.send(up ? .volumeUp : .volumeDown) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                if tv.currentTV != nil { tv.connectIfNeeded() }
                if hardwareVolume { volumeButtons.start() }
            case .background:
                volumeButtons.stop()
                tv.disconnect()
            default:
                break
            }
        }
        .onDisappear {
            // Back to the hub: the side buttons must no longer change the TV's volume
            // and the connection would needlessly keep the TV awake.
            volumeButtons.stop()
            tv.disconnect()
        }
        .onChange(of: hardwareVolume) { _, enabled in
            if enabled && scenePhase == .active { volumeButtons.start() } else { volumeButtons.stop() }
        }
        .onChange(of: tv.isTVKeyboardActive) { _, active in
            // The TV opened its keyboard (e.g. search) – offer typing from the phone right away.
            if active && panel == nil { panel = .text }
        }
    }

    private var header: some View {
        HStack {
            PowerKey { tv.power() }
            Spacer()
            TVSwitcher(client: tv) { panel = .settings }
            Spacer()
            Button {
                panel = .settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(RemoteKeyStyle(shape: Circle()))
            .accessibilityLabel("Settings")
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            barButton("Type", systemImage: "keyboard") { panel = .text }
            barButton("Apps", systemImage: "square.grid.2x2.fill") { panel = .apps }
            barButton("Numbers", systemImage: "number") { panel = .numbers }
        }
    }

    private func barButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        RemoteKeyButton(cornerRadius: 22, action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }
}

// MARK: - Apps

/// Pinned apps as a horizontal strip above the remote.
private struct FavoriteAppsStrip: View {
    let apps: [TVApp]
    let launch: (TVApp) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(apps) { app in
                    RemoteKeyButton(cornerRadius: 20, action: { launch(app) }) {
                        HStack(spacing: 8) {
                            AppTile(app: app, size: 26)
                            Text(app.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                        }
                        .padding(.leading, 7)
                        .padding(.trailing, 14)
                        .frame(height: 40)
                    }
                    .accessibilityLabel("Open \(app.name)")
                }
            }
        }
        .scrollClipDisabled()
    }
}

// MARK: - Volume

/// Current volume; tapping opens entry of an exact number.
private struct VolumeBadge: View {
    let volume: Int?
    let isMuted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.footnote)
                    .foregroundStyle(isMuted ? .red : .secondary)
                Text(volume.map(String.init) ?? "–")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isMuted ? .secondary : .primary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: volume)
            }
            .frame(minWidth: 64)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .buttonStyle(RemoteKeyStyle(shape: Capsule()))
        .accessibilityLabel("Volume \(volume.map(String.init) ?? "unknown")\(isMuted ? ", muted" : ""), set a number")
    }
}

// MARK: - TV picker and connection status

/// Name of the controlled TV with the connection status. Tapping opens a menu to switch to another TV.
private struct TVSwitcher: View {
    let client: SamsungTVClient
    let manage: () -> Void

    var body: some View {
        Menu {
            Section {
                ForEach(client.savedTVs) { saved in
                    Button {
                        client.select(saved.id)
                    } label: {
                        if saved.id == client.currentTVID {
                            Label(saved.name, systemImage: "checkmark")
                        } else {
                            Text(saved.name)
                        }
                    }
                }
            }
            if canRetry {
                Button("Reconnect", systemImage: "arrow.clockwise") { client.connect() }
            }
            Button("Manage TVs…", systemImage: "tv") { manage() }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(client.currentTV?.name ?? "Choose a TV")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: client.state)
        .accessibilityLabel("TV \(client.currentTV?.name ?? "not selected"), \(status ?? "connected")")
    }

    private var canRetry: Bool {
        guard !client.isWaking && !client.isReconnecting else { return false }
        switch client.state {
        case .disconnected, .failed: return true
        case .connecting, .waitingForApproval, .connected: return false
        }
    }

    /// Status below the TV name. When all is well we show nothing; the green dot is enough.
    private var status: String? {
        if client.isWaking && client.state != .connected { return "Turning on the TV…" }
        if client.isReconnecting { return "Reconnecting…" }
        switch client.state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .waitingForApproval: return "Allow the connection on the TV"
        case .connected: return nil
        case .failed(let message): return message
        }
    }

    private var color: Color {
        if (client.isWaking || client.isReconnecting) && client.state != .connected { return .orange }
        switch client.state {
        case .connected: return .green
        case .connecting, .waitingForApproval: return .orange
        case .disconnected: return .gray
        case .failed: return .red
        }
    }
}

#Preview {
    ContentView()
        .environment(SamsungTVClient())
        .preferredColorScheme(.dark)
}
