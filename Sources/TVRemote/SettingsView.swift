import SwiftUI

struct SettingsView: View {
    @Environment(SamsungTVClient.self) private var tv
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TVConfig.hardwareVolumeKey) private var hardwareVolume = true
    @State private var discovery = TVDiscovery()
    /// TV open for editing, or a new (empty) one when adding manually.
    @State private var editing: SavedTV?

    /// TVs found on the network that aren't saved yet.
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
                    Toggle("Volume with Side Buttons", isOn: $hardwareVolume)
                } header: {
                    Text("Controls")
                } footer: {
                    Text("While the app is open, the iPhone's side buttons change the TV's volume instead of the phone's.")
                }
            }
            .navigationTitle("TVs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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

    // MARK: - My TVs

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
                            detail: [saved.host, saved.token == nil ? "not paired" : nil].compactMap { $0 }.joined(separator: " · "),
                            isCurrent: saved.id == tv.currentTVID
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) { tv.remove(saved.id) }
                        Button("Edit") { editing = saved }
                            .tint(.gray)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editing = saved }
                        if saved.token != nil {
                            Button("Forget Pairing", systemImage: "link") {
                                var unpaired = saved
                                unpaired.token = nil
                                tv.save(unpaired, select: false)
                            }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { tv.remove(saved.id) }
                    }
                }
            } header: {
                Text("My TVs")
            } footer: {
                Text("Tap a TV to select it. Swipe left or touch and hold to edit or delete.")
            }
        }
    }

    // MARK: - Network discovery

    @ViewBuilder
    private var discoveredSection: some View {
        Section {
            ForEach(newTelevisions) { found in
                Button {
                    tv.add(found)
                } label: {
                    TVRow(
                        name: found.name,
                        detail: [found.model, found.host, found.isOn ? nil : "standby"].compactMap { $0 }.joined(separator: " · "),
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
                    Text(discovery.televisions.isEmpty ? "Looking for TVs on the network…" : "No other TVs found yet…")
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text(message).foregroundStyle(.red)
            default:
                EmptyView()
            }

            Button("Add Manually (IP and MAC)", systemImage: "keyboard") {
                editing = SavedTV(id: UUID().uuidString, name: "", host: "", mac: "")
            }
        } header: {
            HStack {
                Text("Add TV")
                Spacer()
                Button("Search Again") { discovery.start() }
                    .font(.footnote)
                    .textCase(nil)
            }
        } footer: {
            Text("A TV shows up when it's on or in standby and on the same Wi-Fi. On the first connection, choose Allow on the TV.")
        }
    }
}

/// TV row in the list.
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

// MARK: - Editing a TV

/// Manually adding or editing a saved TV.
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
                Section("Name") {
                    TextField("Living Room", text: $name)
                }

                Section {
                    TextField("192.168.1.50", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("IP Address")
                } footer: {
                    if !host.isEmpty && !hostIsValid {
                        Text("Enter an address like 192.168.1.50.").foregroundStyle(.red)
                    } else {
                        Text("On the TV: Settings → General → Network → Network Status → IP Settings. Reserve a fixed address for it in your router so it doesn't change.")
                    }
                }

                Section {
                    TextField("AA:BB:CC:DD:EE:FF", text: $mac)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("MAC Address (for Power On)")
                } footer: {
                    if !macIsValid {
                        Text("A MAC address has 12 hex digits, e.g. AA:BB:CC:DD:EE:FF.").foregroundStyle(.red)
                    } else {
                        Text("On the TV, turn on Settings → General → Network → Expert Settings → Power On with Mobile.")
                    }
                }

                if !isNew && tv.token != nil && trimmedHost != tv.host {
                    Section {
                        Text("After changing the IP address, the TV will need to be paired again.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isNew ? "New TV" : "Edit TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
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
