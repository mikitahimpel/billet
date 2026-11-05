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
            .background(rarity.fill, in: shape)
            .overlay {
                if rarity.shines { ShineSweep(period: rarity == .legendary ? 2.6 : 3.6).clipShape(shape) }
            }
            .overlay {
                if rarity != .common { shape.strokeBorder(rarity.tint.opacity(0.7), lineWidth: 1.5) }
            }
            .shadow(color: rarity == .legendary ? rarity.tint.opacity(0.45) : .clear, radius: 10)
    }
}

/// A soft band of light that crosses the frame once per period. Still under Reduce Motion.
private struct ShineSweep: View {
    let period: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                GeometryReader { proxy in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                    // The band crosses in the last 45% of the period and rests out of sight before that.
                    let travel = max(0, (phase - 0.55) / 0.45)
                    let width = proxy.size.width * 0.4
                    LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: width)
                        .rotationEffect(.degrees(12))
                        .offset(x: -width * 1.5 + travel * (proxy.size.width + width * 2))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
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
        background(Ink.surface, in: .rect(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
