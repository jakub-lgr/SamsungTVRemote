import SwiftUI

/// Number pad for choosing a channel directly. The TV switches after a moment by itself; OK switches right away.
struct NumberPadSheet: View {
    @Environment(SamsungTVClient.self) private var tv

    private let columns = Array(repeating: GridItem(.fixed(84), spacing: 20), count: 3)

    var body: some View {
        VStack(spacing: 20) {
            Text("Channel")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(1...9, id: \.self) { digit in
                    key(Text("\(digit)").font(.title.weight(.semibold)), label: "\(digit)", key: .digit(digit))
                }
                key(Image(systemName: "arrow.uturn.left").font(.title3.weight(.semibold)), label: "Previous Channel", key: .previousChannel)
                key(Text("0").font(.title.weight(.semibold)), label: "0", key: .digit(0))
                key(Text("OK").font(.title3.weight(.bold)), label: "Confirm", key: .enter)
            }
        }
        .padding(24)
        .presentationDetents([.height(480)])
        .presentationDragIndicator(.visible)
    }

    private func key(_ content: some View, label: String, key: TVKey) -> some View {
        RemoteKeyButton(action: { tv.send(key) }, hold: { tv.hold(key, $0) }) {
            content.frame(width: 84, height: 70)
        }
        .accessibilityLabel(label)
    }
}
