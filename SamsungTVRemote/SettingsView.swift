import SwiftUI

struct SettingsView: View {
    @Environment(SamsungTVClient.self) private var tv
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TVConfig.hardwareVolumeKey) private var hardwareVolume = true
    @State private var discovery = TVDiscovery()
    /// Televize otevřená k úpravě, nebo nová (prázdná) při ručním přidání.
    @State private var editing: SavedTV?

    /// Nalezené televize, které ještě nejsou uložené.
    private var newTelevisions: [DiscoveredTV] {
        discovery.televisions.filter { found in
            !tv.savedTVs.contains { $0.id == found.id || $0.host == found.host }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                savedSection
                discoveredSection

                Section {
                    Toggle("Hlasitost bočními tlačítky", isOn: $hardwareVolume)
                } header: {
                    Text("Ovládání")
                } footer: {
                    Text("Když je aplikace otevřená, boční tlačítka iPhonu mění hlasitost televize místo telefonu.")
                }
            }
            .navigationTitle("Televize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                        .disabled(tv.currentTV == nil)
                }
            }
            .sheet(item: $editing) { tvToEdit in
                EditTVView(tv: tvToEdit, isNew: !tv.savedTVs.contains { $0.id == tvToEdit.id })
            }
            .onAppear { discovery.start() }
            .onDisappear { discovery.stop() }
        }
        .interactiveDismissDisabled(tv.currentTV == nil)
    }

    // MARK: - Moje televize

    @ViewBuilder
    private var savedSection: some View {
        if !tv.savedTVs.isEmpty {
            Section {
                ForEach(tv.savedTVs) { saved in
                    Button {
                        tv.select(saved.id)
                    } label: {
                        TVRow(
                            name: saved.name,
                            detail: [saved.host, saved.token == nil ? "nespárováno" : nil].compactMap { $0 }.joined(separator: " · "),
                            isCurrent: saved.id == tv.currentTVID
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Smazat", role: .destructive) { tv.remove(saved.id) }
                        Button("Upravit") { editing = saved }
                            .tint(.gray)
                    }
                    .contextMenu {
                        Button("Upravit", systemImage: "pencil") { editing = saved }
                        if saved.token != nil {
                            Button("Zapomenout spárování", systemImage: "link") {
                                var unpaired = saved
                                unpaired.token = nil
                                tv.save(unpaired, select: false)
                            }
                        }
                        Button("Smazat", systemImage: "trash", role: .destructive) { tv.remove(saved.id) }
                    }
                }
            } header: {
                Text("Moje televize")
            } footer: {
                Text("Klepnutím televizi vybereš. Úpravy a mazání najdeš po přejetí doleva nebo podržení.")
            }
        }
    }

    // MARK: - Hledání v síti

    @ViewBuilder
    private var discoveredSection: some View {
        Section {
            ForEach(newTelevisions) { found in
                Button {
                    tv.add(found)
                } label: {
                    TVRow(
                        name: found.name,
                        detail: [found.model, found.host, found.isOn ? nil : "v pohotovosti"].compactMap { $0 }.joined(separator: " · "),
                        isCurrent: false,
                        accessory: "plus.circle.fill"
                    )
                }
                .buttonStyle(.plain)
            }

            switch discovery.state {
            case .searching where newTelevisions.isEmpty:
                HStack(spacing: 10) {
                    ProgressView()
                    Text(discovery.televisions.isEmpty ? "Hledám televize v síti…" : "Další televize zatím nevidím…")
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text(message).foregroundStyle(.red)
            default:
                EmptyView()
            }

            Button("Přidat ručně (IP a MAC)", systemImage: "keyboard") {
                editing = SavedTV(id: UUID().uuidString, name: "", host: "", mac: "")
            }
        } header: {
            HStack {
                Text("Přidat televizi")
                Spacer()
                Button("Hledat znovu") { discovery.start() }
                    .font(.footnote)
                    .textCase(nil)
            }
        } footer: {
            Text("Televize se v síti ukáže, když je zapnutá nebo v pohotovosti a ve stejné Wi-Fi. Při prvním připojení na ní potvrď Povolit.")
        }
    }
}

/// Řádek televize v seznamu.
private struct TVRow: View {
    let name: String
    let detail: String
    let isCurrent: Bool
    var accessory: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tv")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
            } else if let accessory {
                Image(systemName: accessory)
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Úprava televize

/// Ruční přidání nebo úprava uložené televize.
struct EditTVView: View {
    @Environment(SamsungTVClient.self) private var client
    @Environment(\.dismiss) private var dismiss

    let tv: SavedTV
    let isNew: Bool

    @State private var name = ""
    @State private var host = ""
    @State private var mac = ""

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespaces) }
    private var trimmedMAC: String { mac.trimmingCharacters(in: .whitespaces) }
    private var hostIsValid: Bool { TVConfig.isValidIPv4(trimmedHost) }
    private var macIsValid: Bool { trimmedMAC.isEmpty || TVConfig.isValidMAC(trimmedMAC) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Název") {
                    TextField("Obývák", text: $name)
                }

                Section {
                    TextField("192.168.1.50", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("IP adresa")
                } footer: {
                    if !host.isEmpty && !hostIsValid {
                        Text("Zadej adresu ve tvaru 192.168.1.50.").foregroundStyle(.red)
                    } else {
                        Text("Na TV: Nastavení → Obecné → Síť → Stav sítě → Nastavení IP. V routeru jí nastav pevnou adresu, ať se nemění.")
                    }
                }

                Section {
                    TextField("AA:BB:CC:DD:EE:FF", text: $mac)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("MAC adresa (pro zapnutí)")
                } footer: {
                    if !macIsValid {
                        Text("MAC adresa má 12 šestnáctkových znaků, např. AA:BB:CC:DD:EE:FF.").foregroundStyle(.red)
                    } else {
                        Text("Na TV musí být zapnuté Nastavení → Obecné → Síť → Odborné nastavení → Zapnutí přes mobil.")
                    }
                }

                if !isNew && tv.token != nil && trimmedHost != tv.host {
                    Section {
                        Text("Po změně IP adresy bude potřeba televizi spárovat znovu.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isNew ? "Nová televize" : "Upravit televizi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit", action: save)
                        .disabled(!hostIsValid || !macIsValid)
                }
            }
            .onAppear {
                name = tv.name
                host = tv.host
                mac = tv.mac
            }
        }
    }

    private func save() {
        var updated = tv
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        updated.name = trimmedName.isEmpty ? "Samsung TV" : trimmedName
        updated.host = trimmedHost
        updated.mac = trimmedMAC.uppercased()
        client.save(updated, select: isNew)
        dismiss()
    }
}
