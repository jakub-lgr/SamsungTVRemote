import SwiftUI
import UIKit

/// A short haptic on every press so you can feel the button responded.
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

/// Looks like `RemoteKeyStyle`, but the action runs on touch-down and repeats while held,
/// like a physical remote. The button's own action is therefore left empty.
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
                // Short delay so a plain tap doesn't send the key twice.
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

/// Shared between the button's style and action. After a quick tap the action can run before
/// `onChange(isPressed)`, so these are two independent flags and the order doesn't matter.
private final class HoldState {
    /// The TV got Press and is waiting for Release.
    var isHolding = false
    /// After a hold, lifting the finger must not also send a plain tap.
    var skipNextTap = false
}

/// Looks like `RemoteKeyStyle`. After a longer press it also reports the start and end of the hold.
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
                    // A tap stays a plain Click; the hold only starts after this delay.
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    state.isHolding = true
                    state.skipNextTap = true
                    tap { hold(true) }
                }
            } else {
                release()
                // If the finger slid off the button, the action isn't called and the next tap would stay swallowed.
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    state.skipNextTap = false
                }
            }
        }
        .onDisappear {
            // The button disappeared under the finger: the key must not stay held on the TV.
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

/// Key button: a tap calls `action`, a hold calls `hold(true)` and `hold(false)` on release.
/// Without `hold` it's a plain button.
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

/// Remote button with a rounded shape and a haptic on press.
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

/// Round button with an icon and a caption below it.
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
        .accessibilityLabel("Power")
    }
}

/// Colour buttons for teletext, HbbTV and app menus. The order matches the Samsung remote.
struct ColorKeys: View {
    let onPress: (TVKey) -> Void
    let onHold: (TVKey, Bool) -> Void

    private let keys: [(key: TVKey, color: Color, label: String)] = [
        (.red, .red, "Red button"),
        (.green, .green, "Green button"),
        (.yellow, .yellow, "Yellow button"),
        (.blue, .blue, "Blue button"),
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

/// Vertical two-button rocker for volume and channels. `onPress(true)` is up.
struct Rocker: View {
    let title: String
    let upImage: String
    let downImage: String
    let onPress: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            half(systemImage: upImage, label: "\(title) up") { onPress(true) }
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            half(systemImage: downImage, label: "\(title) down") { onPress(false) }
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

/// Circular pad with arrows and OK in the middle.
struct DirectionPad: View {
    var size: CGFloat = 260
    let onPress: (TVKey) -> Void
    /// Only for OK. The arrows repeat while held, like a physical remote.
    let onHold: (TVKey, Bool) -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.16))
                .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))

            arrow(.up, systemImage: "chevron.up", label: "Up")
                .offset(y: -size * 0.34)
            arrow(.down, systemImage: "chevron.down", label: "Down")
                .offset(y: size * 0.34)
            arrow(.left, systemImage: "chevron.left", label: "Left")
                .offset(x: -size * 0.34)
            arrow(.right, systemImage: "chevron.right", label: "Right")
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
