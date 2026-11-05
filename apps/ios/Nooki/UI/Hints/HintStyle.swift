import SwiftUI
import TipKit

/// The hints' look: a honey symbol, an SF Rounded title, the message and the hint's button under it, and an X. The
/// background is the system's (glass on iOS 26), warmed before that.
struct HintStyle: TipViewStyle {
    let hints: Hints

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            configuration.image?
                .font(.system(.title2, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.honey)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                configuration.title?
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                configuration.message?
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(3)
                ForEach(configuration.actions) { action in
                    Button(action: action.handler) {
                        action.label()
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.honey)
                    .foregroundStyle(Ink.heroInk)
                    .padding(.top, 6)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                hints.close(configuration.tip)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Ink.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close hint")
        }
        .padding(16)
        .environment(\.colorScheme, .dark)
        .onAppear { hints.appeared(configuration.tip) }
    }
}

extension View {
    /// The hints' style and background for everything under this view.
    func hintStyle(_ hints: Hints) -> some View {
        modifier(HintLook(hints: hints))
    }
}

private struct HintLook: ViewModifier {
    let hints: Hints

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tipViewStyle(HintStyle(hints: hints))
        } else {
            content
                .tipViewStyle(HintStyle(hints: hints))
                .tipBackground(Ink.sheet)
        }
    }
}
