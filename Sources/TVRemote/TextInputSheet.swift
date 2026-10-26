import SwiftUI

/// Typing into a text field on the TV (search in YouTube, Netflix…) with the iPhone keyboard.
struct TextInputSheet: View {
    @Environment(SamsungTVClient.self) private var tv
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Type on TV")
                .font(.headline)

            TextField("What are you looking for?", text: $text)
                .focused($focused)
                .submitLabel(.send)
                .autocorrectionDisabled()
                .font(.title3)
                .padding(14)
                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 14))
                .onSubmit(send)

            Label {
                Text(tv.isTVKeyboardActive
                     ? "The TV is waiting for text. Send it with the Send key."
                     : "First open a text field on the TV, such as search. This panel then opens by itself.")
            } icon: {
                Image(systemName: tv.isTVKeyboardActive ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(tv.isTVKeyboardActive ? .green : .secondary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button(action: send) {
                Text("Send")
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
