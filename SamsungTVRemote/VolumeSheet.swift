import SwiftUI

/// Nastavení hlasitosti na konkrétní číslo: posuvníkem nebo zadáním hodnoty.
struct VolumeSheet: View {
    @Environment(SamsungTVClient.self) private var tv

    @State private var level: Double = 0
    @State private var isDragging = false
    @State private var input = ""
    @State private var isApplying = false
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    private var inputValue: Int? {
        Int(input).flatMap { TVVolume.range.contains($0) ? $0 : nil }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Hlasitost")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(tv.volume == nil && !isDragging ? "–" : "\(Int(level))")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: Int(level))

            HStack(spacing: 12) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $level, in: 0...100, step: 1) { editing in
                    isDragging = editing
                    if !editing { apply(Int(level)) }
                }
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                TextField("0–100", text: $input)
                    .keyboardType(.numberPad)
                    .focused($inputFocused)
                    .font(.title3.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: input) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(3))
                        if digits != newValue { input = digits }
                    }

                Button {
                    if let value = inputValue {
                        apply(value)
                        input = ""
                        inputFocused = false
                    }
                } label: {
                    Text("Nastavit")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .disabled(inputValue == nil || isApplying)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else if !input.isEmpty && inputValue == nil {
                Text("Zadej číslo od 0 do 100.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            level = Double(tv.volume ?? 0)
            tv.refreshVolume()
        }
        .onChange(of: tv.volume) { _, newValue in
            if let newValue, !isDragging { level = Double(newValue) }
        }
    }

    private func apply(_ value: Int) {
        level = Double(value)
        errorMessage = nil
        isApplying = true
        Task {
            defer { isApplying = false }
            do {
                try await tv.setVolume(value)
            } catch {
                errorMessage = "Hlasitost se nepodařilo nastavit. Je televize zapnutá?"
                tv.refreshVolume()
            }
        }
    }
}
