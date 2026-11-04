import SwiftUI

extension View {
    /// Liquid Glass from iOS 26; earlier systems get a frosted material in the same shape.
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}

/// GlassEffectContainer from iOS 26; earlier systems show the content as is.
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

struct RoundGlassButton: View {
    let symbol: String
    var badge = false

    var body: some View {
        Button {} label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.primary)
                .frame(width: 42, height: 42)
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle()
                            .fill(Color(hex: 0xFF5D73))
                            .frame(width: 8, height: 8)
                            .offset(x: -11, y: 10)
                    }
                }
        }
        .buttonStyle(.plain)
        .glass(.circle, interactive: true)
    }
}
