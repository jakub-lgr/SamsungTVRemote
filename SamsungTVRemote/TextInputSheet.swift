import SwiftUI

/// Psaní do textového pole na televizi (hledání v YouTube, Netflixu…) klávesnicí iPhonu.
struct TextInputSheet: View {
    @Environment(SamsungTVClient.self) private var tv
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Psaní na televizi")
                .font(.headline)

            TextField("Co hledáš?", text: $text)
                .focused($focused)
                .submitLabel(.send)
                .autocorrectionDisabled()
                .font(.title3)
                .padding(14)
                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 14))
                .onSubmit(send)

            Label {
                Text(tv.isTVKeyboardActive
                     ? "Televize čeká na text. Odešli ho klávesou Odeslat."
                     : "Nejdřív na televizi otevři pole pro psaní, třeba hledání. Panel se pak otevře sám.")
            } icon: {
                Image(systemName: tv.isTVKeyboardActive ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(tv.isTVKeyboardActive ? .green : .secondary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button(action: send) {
                Text("Odeslat")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(text.isEmpty)
        }
        .padding(24)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }

    private func send() {
        guard !text.isEmpty else { return }
        tv.sendText(text)
        dismiss()
    }
}
