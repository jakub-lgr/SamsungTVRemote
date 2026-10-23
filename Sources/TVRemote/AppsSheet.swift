import SwiftUI

/// Seznam aplikací na televizi. Klepnutí aplikaci spustí, hvězdička ji připne na ovladač.
struct AppsSheet: View {
    @Environment(SamsungTVClient.self) private var tv
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredApps: [TVApp] {
        guard !query.isEmpty else { return tv.installedApps }
        return tv.installedApps.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        @Bindable var tv = tv

        NavigationStack {
            List {
                if !tv.favoriteApps.isEmpty && query.isEmpty {
                    Section {
                        ForEach(tv.favoriteApps) { row(for: $0) }
                            .onMove { tv.favoriteApps.move(fromOffsets: $0, toOffset: $1) }
                    } header: {
                        Text("Na ovladači")
                    } footer: {
                        Text("Pořadí změníš podržením a přetažením.")
                    }
                }

                Section("Všechny aplikace") {
                    if tv.installedApps.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Načítám aplikace z televize…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(filteredApps) { row(for: $0) }
                }
            }
            .searchable(text: $query, prompt: "Hledat aplikaci")
            .navigationTitle("Aplikace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                }
            }
        }
        .onAppear { tv.requestInstalledApps() }
    }

    private func row(for app: TVApp) -> some View {
        HStack(spacing: 12) {
            Button {
                tv.launch(app)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    AppTile(app: app, size: 36)
                    Text(app.name)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                tv.toggleFavorite(app)
            } label: {
                Image(systemName: tv.isFavorite(app) ? "star.fill" : "star")
                    .foregroundStyle(tv.isFavorite(app) ? .yellow : .secondary)
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(tv.isFavorite(app) ? "Odepnout z ovladače" : "Připnout na ovladač")
        }
    }
}

/// Barevná dlaždice s prvním písmenem aplikace (ikony televize přes síť nedává).
struct AppTile: View {
    let app: TVApp
    var size: CGFloat = 44

    var body: some View {
        Text(app.initial)
            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(app.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.26))
    }
}
