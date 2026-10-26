import SwiftUI

/// List of apps on the TV. A tap opens the app, the star pins it to the remote.
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
                        Text("On the Remote")
                    } footer: {
                        Text("Touch and hold, then drag to reorder.")
                    }
                }

                Section("All Apps") {
                    if tv.installedApps.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Loading apps from the TV…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(filteredApps) { row(for: $0) }
                }
            }
            .searchable(text: $query, prompt: "Search Apps")
            .navigationTitle("Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
            .accessibilityLabel(tv.isFavorite(app) ? "Unpin from Remote" : "Pin to Remote")
        }
    }
}

/// Coloured tile with the app's first letter (the TV doesn't provide icons over the network).
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
