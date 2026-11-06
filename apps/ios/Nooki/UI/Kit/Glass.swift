import SwiftUI

extension View {
    /// Liquid Glass from iOS 26, tinted when given one (`Ink.glassTint` keeps it warm over the room); earlier systems
    /// get a frosted material in the same shape. `clear` is the more see-through variant, for glass over the busy room.
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, tint: Color? = nil, clear: Bool = false, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect((clear ? Glass.clear : .regular).tint(tint).interactive(interactive), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}

extension View {
    /// The see-through, honey-tinted glass for controls that float over the room: the tab bar and the chips.
    func warmGlass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        glass(shape, tint: Ink.glassTint, clear: true, interactive: interactive)
    }
}

extension View {
    /// Warm glass behind a button's label that never takes a touch itself, so the button always gets it.
    func warmGlassBacking<S: Shape>(_ shape: S) -> some View {
        background { Color.clear.warmGlass(shape).allowsHitTesting(false) }
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
