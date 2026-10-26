import SwiftUI
import UIKit

/// Krátká vibrace při každém stisku, ať je cítit, že tlačítko zareagovalo.
private let haptics = UIImpactFeedbackGenerator(style: .light)

private func tap(_ action: () -> Void) {
    haptics.impactOccurred()
    action()
}

struct RemoteKeyStyle<S: Shape>: ButtonStyle {
    var shape: S
    var fill: Color = Color(white: 0.2)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(fill.opacity(configuration.isPressed ? 0.6 : 1), in: shape)
            .overlay(shape.stroke(.white.opacity(0.08), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Vzhled jako `RemoteKeyStyle`, ale akce proběhne hned při dotyku a při podržení se opakuje
/// jako na fyzickém ovladači. Vlastní akce tlačítka se proto nechává prázdná.
struct RepeatingKeyStyle<S: Shape>: ButtonStyle {
    var shape: S
    var fill: Color = Color(white: 0.2)
    let action: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        RemoteKeyStyle(shape: shape, fill: fill)
            .makeBody(configuration: configuration)
            .modifier(RepeatWhilePressed(isPressed: configuration.isPressed, action: action))
    }
}

private struct RepeatWhilePressed: ViewModifier {
    let isPressed: Bool
    let action: () -> Void
    @State private var repeatTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.onChange(of: isPressed) { _, pressed in
            repeatTask?.cancel()
            guard pressed else { return }
            tap(action)
            repeatTask = Task {
                // Krátká prodleva, aby obyčejné klepnutí neposlalo klávesu dvakrát.
                try? await Task.sleep(for: .milliseconds(450))
                while !Task.isCancelled {
                    tap(action)
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
        }
        .onDisappear { repeatTask?.cancel() }
    }
}

/// Sdílené mezi stylem a akcí tlačítka. Akce po rychlém klepnutí může proběhnout dřív než
/// `onChange(isPressed)`, proto jsou to dva nezávislé příznaky a na pořadí nezáleží.
private final class HoldState {
    /// Televize dostala Press a čeká na Release.
    var isHolding = false
    /// Po podržení už puštění nesmí poslat ještě obyčejné klepnutí.
    var skipNextTap = false
}

/// Vzhled jako `RemoteKeyStyle`. Po delším stisku navíc ohlásí začátek a konec podržení.
private struct HoldableKeyStyle<S: Shape>: ButtonStyle {
    var shape: S
    var fill: Color
    let state: HoldState
    let hold: ((Bool) -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        RemoteKeyStyle(shape: shape, fill: fill)
            .makeBody(configuration: configuration)
            .modifier(HoldWhilePressed(isPressed: configuration.isPressed, state: state, hold: hold))
    }
}

private struct HoldWhilePressed: ViewModifier {
    let isPressed: Bool
    let state: HoldState
    let hold: ((Bool) -> Void)?
    @State private var holdTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.onChange(of: isPressed) { _, pressed in
            guard let hold else { return }
            holdTask?.cancel()
            if pressed {
                holdTask = Task {
                    // Klepnutí zůstává obyčejným Click, podržení začne až po této prodlevě.
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    state.isHolding = true
                    state.skipNextTap = true
                    tap { hold(true) }
                }
            } else {
                release()
                // Když prst sjel z tlačítka, akce se nezavolá a klepnutí by zůstalo spolknuté.
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    state.skipNextTap = false
                }
            }
        }
        .onDisappear {
            // Tlačítko zmizelo pod prstem: klávesa nesmí na televizi zůstat držená.
            holdTask?.cancel()
            release()
        }
    }

    private func release() {
        guard state.isHolding, let hold else { return }
        state.isHolding = false
        hold(false)
    }
}

/// Tlačítko klávesy: klepnutí zavolá `action`, podržení `hold(true)` a po puštění `hold(false)`.
/// Bez `hold` je to obyčejné tlačítko.
private struct KeyButton<S: Shape, Label: View>: View {
    var shape: S
    var fill: Color = Color(white: 0.2)
    let action: () -> Void
    var hold: ((Bool) -> Void)?
    @ViewBuilder let label: Label
    @State private var state = HoldState()

    var body: some View {
        Button {
            if state.skipNextTap {
                state.skipNextTap = false
            } else {
                tap(action)
            }
        } label: {
            label
        }
        .buttonStyle(HoldableKeyStyle(shape: shape, fill: fill, state: state, hold: hold))
    }
}

/// Tlačítko ovladače se zaobleným tvarem a vibrací při stisku.
struct RemoteKeyButton<Label: View>: View {
    var cornerRadius: CGFloat = 20
    let action: () -> Void
    var hold: ((Bool) -> Void)?
    @ViewBuilder let label: Label

    var body: some View {
        KeyButton(shape: RoundedRectangle(cornerRadius: cornerRadius), action: action, hold: hold) {
            label
        }
    }
}

/// Kulaté tlačítko s ikonou a popiskem pod ním.
struct RemoteKey: View {
    let systemImage: String
    let title: String
    var fill: Color = Color(white: 0.2)
    let action: () -> Void
    var hold: ((Bool) -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            KeyButton(shape: Circle(), fill: fill, action: action, hold: hold) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 64, height: 64)
            }
            .accessibilityLabel(title)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct PowerKey: View {
    let action: () -> Void

    var body: some View {
        Button {
            tap(action)
        } label: {
            Image(systemName: "power")
                .font(.title3.weight(.bold))
                .frame(width: 52, height: 52)
        }
        .buttonStyle(RemoteKeyStyle(shape: Circle(), fill: .red.opacity(0.85)))
        .accessibilityLabel("Zapnout nebo vypnout")
    }
}

/// Barevná tlačítka pro teletext, HbbTV a nabídky aplikací. Pořadí odpovídá ovladači Samsung.
struct ColorKeys: View {
    let onPress: (TVKey) -> Void
    let onHold: (TVKey, Bool) -> Void

    private let keys: [(key: TVKey, color: Color, label: String)] = [
        (.red, .red, "Červené tlačítko"),
        (.green, .green, "Zelené tlačítko"),
        (.yellow, .yellow, "Žluté tlačítko"),
        (.blue, .blue, "Modré tlačítko"),
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(keys, id: \.key) { item in
                KeyButton(
                    shape: Capsule(),
                    fill: item.color.opacity(0.85),
                    action: { onPress(item.key) },
                    hold: { onHold(item.key, $0) }
                ) {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .contentShape(Capsule())
                }
                .accessibilityLabel(item.label)
            }
        }
    }
}

/// Svislý dvojtlačítkový ovladač pro hlasitost a kanály. `onPress(true)` je nahoru.
struct Rocker: View {
    let title: String
    let upImage: String
    let downImage: String
    let onPress: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            half(systemImage: upImage, label: "\(title) nahoru") { onPress(true) }
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            half(systemImage: downImage, label: "\(title) dolů") { onPress(false) }
        }
        .padding(6)
        .background(Color(white: 0.16), in: Capsule())
    }

    private func half(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {} label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 64, height: 64)
        }
        .buttonStyle(RepeatingKeyStyle(shape: Circle(), fill: Color(white: 0.24), action: action))
        .accessibilityLabel(label)
    }
}

/// Kruhový ovladač se šipkami a OK uprostřed.
struct DirectionPad: View {
    var size: CGFloat = 260
    let onPress: (TVKey) -> Void
    /// Jen pro OK. Šipky se při podržení opakují, jako na fyzickém ovladači.
    let onHold: (TVKey, Bool) -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.16))
                .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))

            arrow(.up, systemImage: "chevron.up", label: "Nahoru")
                .offset(y: -size * 0.34)
            arrow(.down, systemImage: "chevron.down", label: "Dolů")
                .offset(y: size * 0.34)
            arrow(.left, systemImage: "chevron.left", label: "Doleva")
                .offset(x: -size * 0.34)
            arrow(.right, systemImage: "chevron.right", label: "Doprava")
                .offset(x: size * 0.34)

            KeyButton(
                shape: Circle(),
                fill: Color(white: 0.28),
                action: { onPress(.enter) },
                hold: { onHold(.enter, $0) }
            ) {
                Text("OK")
                    .font(.title2.weight(.bold))
                    .frame(width: size * 0.38, height: size * 0.38)
            }
            .accessibilityLabel("OK")
        }
        .frame(width: size, height: size)
    }

    private func arrow(_ key: TVKey, systemImage: String, label: String) -> some View {
        Button {} label: {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .frame(width: 72, height: 72)
                .contentShape(Rectangle())
        }
        .buttonStyle(RepeatingKeyStyle(shape: Circle(), fill: .clear) { onPress(key) })
        .accessibilityLabel(label)
    }
}
