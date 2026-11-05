import SwiftUI

extension ShopRarity {
    /// The frame's fill behind the art.
    var fill: Color {
        switch self {
        case .common: Ink.surfaceRaised
        case .rare: Color(light: Color(hex: 0xD5EEF3), dark: Color(hex: 0x24474F))
        case .epic: Color(light: Color(hex: 0xEADBF8), dark: Color(hex: 0x3B2D52))
        case .legendary: Color(light: Color(hex: 0xFFE7B0), dark: Color(hex: 0x56421E))
        }
    }

    /// The frame's rim, the label's fill and the glow.
    var tint: Color {
        switch self {
        case .common: Color(hex: 0xB39C86)
        case .rare: Color(hex: 0x3E9DB0)
        case .epic: Color(hex: 0x9A5FD0)
        case .legendary: Color(hex: 0xD9952A)
        }
    }

    /// Epic and legendary pieces catch the light now and then.
    var shines: Bool { self == .epic || self == .legendary }
}

/// The item's art in its rarity frame: a tinted fill and rim, a glow for legendary, a shine sweep for the top two.
struct RarityFrame<Content: View>: View {
    let rarity: ShopRarity
    @ViewBuilder let content: Content

    private let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                // The glow comes from the frame's shape alone, so the art and the shine moving over it never have
                // to be drawn again just to cast it.
                shape.fill(rarity.fill)
                    .shadow(color: rarity == .legendary ? rarity.tint.opacity(0.45) : .clear, radius: 10)
            }
            .overlay {
                if rarity.shines { ShineSweep(period: rarity == .legendary ? 2.6 : 3.6).clipShape(shape) }
            }
            .overlay {
                if rarity != .common { shape.strokeBorder(rarity.tint.opacity(0.7), lineWidth: 1.5) }
            }
    }
}

/// A soft band of light that crosses the frame once per period, only while the frame is on screen. Still under
/// Reduce Motion.
///
/// The band moves by an animated effect, not a timeline: SwiftUI moves it each frame without building the view again,
/// and a card scrolled out of sight stops it.
private struct ShineSweep: View {
    let period: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 to 1 through each period, animated forever while the frame is on screen.
    @State private var progress = 0.0

    var body: some View {
        if !reduceMotion {
            GeometryReader { proxy in
                let width = proxy.size.width * 0.4
                LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
                    .rotationEffect(.degrees(12))
                    .modifier(SweepEffect(progress: progress, frameWidth: proxy.size.width, bandWidth: width))
            }
            .onScrollVisibilityChange(threshold: 0.01) { visible in
                if visible {
                    withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) { progress = 1 }
                } else {
                    var still = Transaction(animation: nil)
                    still.disablesAnimations = true
                    withTransaction(still) { progress = 0 }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Where the band is at `progress` through the period: it crosses in the last 45% and rests out of sight before that.
private struct SweepEffect: GeometryEffect {
    var progress: Double
    let frameWidth: CGFloat
    let bandWidth: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let travel = max(0, (progress - 0.55) / 0.45)
        let x = -bandWidth * 1.5 + travel * (frameWidth + bandWidth * 2)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

/// A small label in a rounded tag: rarity, NEW, a discount.
struct ShopTag: View {
    let text: String
    let fill: Color
    var ink: Color = .white

    var body: some View {
        Text(text)
            .font(.nookiMicro)
            .textCase(.uppercase)
            .foregroundStyle(ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(fill, in: .rect(cornerRadius: Radius.tag, style: .continuous))
    }
}

/// A price in coins, with the old price struck through when there's a deal.
struct CoinPrice: View {
    let price: Int
    var was: Int? = nil

    var body: some View {
        HStack(spacing: 5) {
            CoinIcon(size: 18)
            Text("\(price)")
                .monospacedDigit()
            if let was, was > price {
                Text("\(was)")
                    .font(.nookiCaption.monospacedDigit())
                    .strikethrough()
                    .opacity(0.6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(was.map { $0 > price ? "\(price) coins, was \($0)" : "\(price) coins" } ?? "\(price) coins")
    }
}

extension View {
    /// A buy or claim button inside a card: honey prominent glass from iOS 26, bordered prominent before.
    @ViewBuilder
    func shopButton(prominent: Bool = true) -> some View {
        let styled = font(.nookiHeadline)
            .buttonBorderShape(.capsule)
            .tint(.honey)
        if prominent {
            if #available(iOS 26, *) {
                styled.foregroundStyle(Ink.heroInk).buttonStyle(.glassProminent)
            } else {
                styled.foregroundStyle(Ink.heroInk).buttonStyle(.borderedProminent)
            }
        } else {
            if #available(iOS 26, *) {
                styled.buttonStyle(.glass)
            } else {
                styled.buttonStyle(.bordered)
            }
        }
    }

    /// A card on the Shop: the adaptive surface, card corners and a soft shadow.
    func shopCard(radius: CGFloat = Radius.card) -> some View {
        // The shadow is the card's shape's own, not the whole card's: a shine or a countdown changing inside never
        // makes it draw again.
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Ink.surface)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
    }
}
