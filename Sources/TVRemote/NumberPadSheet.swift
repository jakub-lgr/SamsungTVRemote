import SwiftUI

/// Číselník pro přímou volbu kanálu. Televize po chvíli sama přepne, OK přepne hned.
struct NumberPadSheet: View {
    @Environment(SamsungTVClient.self) private var tv

    private let columns = Array(repeating: GridItem(.fixed(84), spacing: 20), count: 3)

    var body: some View {
        VStack(spacing: 20) {
            Text("Kanál")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(1...9, id: \.self) { digit in
                    key(Text("\(digit)").font(.title.weight(.semibold)), label: "\(digit)") { tv.send(.digit(digit)) }
                }
                key(Image(systemName: "arrow.uturn.left").font(.title3.weight(.semibold)), label: "Předchozí kanál") {
                    tv.send(.previousChannel)
                }
                key(Text("0").font(.title.weight(.semibold)), label: "0") { tv.send(.digit(0)) }
                key(Text("OK").font(.title3.weight(.bold)), label: "Potvrdit") { tv.send(.enter) }
            }
        }
        .padding(24)
        .presentationDetents([.height(480)])
        .presentationDragIndicator(.visible)
    }

    private func key(_ content: some View, label: String, action: @escaping () -> Void) -> some View {
        RemoteKeyButton(action: action) {
            content.frame(width: 84, height: 70)
        }
        .accessibilityLabel(label)
    }
}
