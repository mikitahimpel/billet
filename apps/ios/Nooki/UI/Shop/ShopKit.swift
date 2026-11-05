import SwiftUI

/// The Shop's own accents on the warm room palette, saturated so offers stand out against the brown.
enum ShopInk {
    static let coral = Color(hex: 0xFF7A59)
    static let plum = Color(hex: 0xA466E8)
    static let teal = Color(hex: 0x3CC8E0)
    static let gold = Color(hex: 0xFFB52E)
    /// Lamplight on a warm room, for the hero offer and the set sheet: honey into coral into a plum dusk.
    static var lamplight: RadialGradient {
        RadialGradient(colors: [Color(hex: 0xFFD08A), Color(hex: 0xF08A4E), Color(hex: 0x8A3A4E), Color(hex: 0x3A1C2A)],
                       center: UnitPoint(x: 0.55, y: 0.32), startRadius: 8, endRadius: 360)
    }
}

extension ShopRarity {
    /// The frame's glow and the label's fill.
    var tint: Color {
        switch self {
        case .common: Color(hex: 0xE3BD8F)
        case .rare: ShopInk.teal
        case .epic: ShopInk.plum
        case .legendary: ShopInk.gold
        }
    }

    /// The frame's fill behind the art, lit from above: the centre of the light, then its edge.
    var fill: (light: Color, edge: Color) {
        switch self {
        case .common: (Color(light: Color(hex: 0xFFF1DE), dark: Color(hex: 0x6A4A36)),
                       Color(light: Color(hex: 0xF3DDC2), dark: Color(hex: 0x3E2A20)))
        case .rare: (Color(light: Color(hex: 0xDDF6FA), dark: Color(hex: 0x23707E)),
                     Color(light: Color(hex: 0xB9E6EE), dark: Color(hex: 0x163A44)))
        case .epic: (Color(light: Color(hex: 0xF1E3FF), dark: Color(hex: 0x6A3FA6)),
                     Color(light: Color(hex: 0xDCC4F8), dark: Color(hex: 0x2E1C4A)))
        case .legendary: (Color(light: Color(hex: 0xFFF0C4), dark: Color(hex: 0x9A6A1C)),
                          Color(light: Color(hex: 0xFFDB8A), dark: Color(hex: 0x4A3210)))
        }
    }

    /// Epic and legendary pieces glow and catch the light now and then.
    var shines: Bool { self == .epic || self == .legendary }
}

/// The item's art in its rarity frame: a fill lit from above in the rarity's colour, a rim, a glow for the top two
/// and a shine sweep across them.
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
                shape.fill(RadialGradient(colors: [rarity.fill.light, rarity.fill.edge],
                                          center: UnitPoint(x: 0.5, y: 0.3), startRadius: 4, endRadius: 140))
                    .shadow(color: rarity.shines ? rarity.tint.opacity(0.5) : .clear, radius: 9)
            }
            .overlay {
                if rarity.shines { ShineSweep(period: rarity == .legendary ? 2.6 : 3.6).clipShape(shape) }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [rarity.tint, rarity.tint.opacity(rarity == .common ? 0.15 : 0.45)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: rarity == .common ? 1 : 1.5)
            }
    }
}

/// Art lifted off its frame: a soft oval on the floor under it, drawn once, instead of a shadow traced around the
/// picture.
struct Lifted<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(alignment: .bottom) {
                Ellipse()
                    .fill(RadialGradient(colors: [.black.opacity(0.35), .clear], center: .center, startRadius: 0,
                                         endRadius: 60))
                    .frame(height: 18)
                    .scaleEffect(x: 0.8, y: 1)
                    .offset(y: 6)
                    .accessibilityHidden(true)
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

/// A small label in a rounded tag: rarity, NEW, a discount. Dark ink, since every tag fill is light and saturated.
struct ShopTag: View {
    let text: String
    let fill: Color
    var ink: Color = Ink.heroInk

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

    /// A card on the Shop: the app's clay card.
    func shopCard(radius: CGFloat = Radius.card) -> some View {
        nookiCard(radius: radius)
    }

    /// Fades and rises a little into place as it scrolls in, straight up, never sideways; only a fade under Reduce
    /// Motion.
    func shopAppear() -> some View {
        modifier(ShopAppear())
    }
}

private struct ShopAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // `.animated` springs once when the card crosses into view rather than following every scrolled point.
        content.scrollTransition(.animated(.spring(duration: 0.5, bounce: 0.25))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.3)
                .offset(y: phase.isIdentity || reduceMotion ? 0 : 10)
        }
    }
}

/// A Shop section's title with its icon on a disc of the section's accent, and a quiet line on the right.
struct ShopSectionHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            Image(systemName: symbol)
                .font(.nookiCallout.weight(.bold))
                .foregroundStyle(Ink.heroInk)
                .frame(width: 30, height: 30)
                .background(tint, in: .circle)
                .accessibilityHidden(true)
            Text(title)
                .font(.nookiTitle)
                .foregroundStyle(Ink.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s)
            trailing
                .font(.nookiCaption)
                .foregroundStyle(Ink.textSecondary)
        }
    }
}

/// Lays its views out in rows, left to right, starting a new row when the next one wouldn't fit.
struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
