import SwiftUI

struct ContentView: View {
    /// Panely, které se nad ovladačem otevírají zespodu.
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
                // Na menších iPhonech se ovladač zmenší, aby se vešlo všechno ostatní.
                DirectionPad(size: min(260, max(190, proxy.size.height - 522))) { tv.send($0) }
                Spacer(minLength: 12)
                HStack(spacing: 28) {
                    RemoteKey(systemImage: "arrow.uturn.backward", title: "Zpět") { tv.send(.back) }
                    RemoteKey(systemImage: "house.fill", title: "Domů") { tv.send(.home) }
                    RemoteKey(systemImage: "rectangle.portrait.and.arrow.right", title: "Zdroj") { tv.send(.source) }
                }
                Spacer(minLength: 12)
                HStack(alignment: .center) {
                    Rocker(title: "VOL", upImage: "plus", downImage: "minus") { tv.send($0 ? .volumeUp : .volumeDown) }
                    Spacer()
                    VStack(spacing: 18) {
                        VolumeBadge(volume: tv.volume, isMuted: tv.isMuted == true) { panel = .volume }
                        RemoteKey(
                            systemImage: tv.isMuted == true ? "speaker.slash.fill" : "speaker.slash",
                            title: tv.isMuted == true ? "Ztlumeno" : "Ztlumit",
                            fill: tv.isMuted == true ? .red.opacity(0.85) : Color(white: 0.2)
                        ) { tv.send(.mute) }
                    }
                    Spacer()
                    Rocker(title: "CH", upImage: "chevron.up", downImage: "chevron.down") { tv.send($0 ? .channelUp : .channelDown) }
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 12)
                ColorKeys { tv.send($0) }
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
            // Návrat do rozcestníku: boční tlačítka už nesmí měnit hlasitost televize
            // a spojení by zbytečně drželo televizi vzhůru.
            volumeButtons.stop()
            tv.disconnect()
        }
        .onChange(of: hardwareVolume) { _, enabled in
            if enabled && scenePhase == .active { volumeButtons.start() } else { volumeButtons.stop() }
        }
        .onChange(of: tv.isTVKeyboardActive) { _, active in
            // Televize otevřela klávesnici (třeba hledání) – rovnou nabídneme psaní z telefonu.
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
            .accessibilityLabel("Nastavení")
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            barButton("Psát", systemImage: "keyboard") { panel = .text }
            barButton("Aplikace", systemImage: "square.grid.2x2.fill") { panel = .apps }
            barButton("Čísla", systemImage: "number") { panel = .numbers }
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

// MARK: - Aplikace

/// Připnuté aplikace jako vodorovný pás nad ovladačem.
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
                    .accessibilityLabel("Spustit \(app.name)")
                }
            }
        }
        .scrollClipDisabled()
    }
}

// MARK: - Hlasitost

/// Aktuální hlasitost; klepnutím se otevře zadání přesného čísla.
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
        .accessibilityLabel("Hlasitost \(volume.map(String.init) ?? "neznámá")\(isMuted ? ", ztlumeno" : ""), nastavit číslo")
    }
}

// MARK: - Výběr televize a stav spojení

/// Název ovládané televize se stavem spojení. Klepnutím se otevře menu pro přepnutí na jinou televizi.
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
                Button("Připojit znovu", systemImage: "arrow.clockwise") { client.connect() }
            }
            Button("Spravovat televize…", systemImage: "tv") { manage() }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(client.currentTV?.name ?? "Vyber televizi")
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
        .accessibilityLabel("Televize \(client.currentTV?.name ?? "nevybrána"), \(status ?? "připojeno")")
    }

    private var canRetry: Bool {
        guard !client.isWaking && !client.isReconnecting else { return false }
        switch client.state {
        case .disconnected, .failed: return true
        case .connecting, .waitingForApproval, .connected: return false
        }
    }

    /// Stav pod názvem televize. Když je vše v pořádku, nepíšeme nic, stačí zelená tečka.
    private var status: String? {
        if client.isWaking && client.state != .connected { return "Zapínám televizi…" }
        if client.isReconnecting { return "Obnovuji spojení…" }
        switch client.state {
        case .disconnected: return "Odpojeno"
        case .connecting: return "Připojuji…"
        case .waitingForApproval: return "Potvrď připojení na televizi"
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
