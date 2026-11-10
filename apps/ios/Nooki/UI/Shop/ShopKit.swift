import SwiftUI
import Design

enum ShopInk {
    static let coral = Color(hex: 0xFF7A59)
    static let plum = Color(hex: 0xA466E8)
    static let teal = Color(hex: 0x3CC8E0)
    static let gold = Color(hex: 0xFFB52E)
    static var lamplight: RadialGradient {
        RadialGradient(colors: [Color(hex: 0xFFD08A), Color(hex: 0xF08A4E), Color(hex: 0x8A3A4E), Color(hex: 0x3A1C2A)],
                       center: UnitPoint(x: 0.55, y: 0.32), startRadius: 8, endRadius: 360)
    }
}

extension ShopRarity {
    var tint: Color {
        switch self {
        case .common: Color(hex: 0xE3BD8F)
        case .rare: ShopInk.teal
        case .epic: ShopInk.plum
        case .legendary: ShopInk.gold
        }
    }

    var fill: (light: Color, edge: Color) {
        switch self {
        // Always the light pair, in either appearance: the art sits on a bright tint, never on dark.
        case .common: (Color(hex: 0xFFF1DE), Color(hex: 0xF3DDC2))
        case .rare: (Color(hex: 0xDDF6FA), Color(hex: 0xB9E6EE))
        case .epic: (Color(hex: 0xF1E3FF), Color(hex: 0xDCC4F8))
        case .legendary: (Color(hex: 0xFFF0C4), Color(hex: 0xFFDB8A))
        }
    }

    var chip: Chip {
        Chip(title, style: self == .common ? .quiet : .tinted(tint))
    }

    var shines: Bool { self == .epic || self == .legendary }
}

struct RarityFrame<Content: View>: View {
    let rarity: ShopRarity
    @ViewBuilder let content: Content
    @Environment(\.perfShine) private var shine

    private let shape = RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                // The glow comes from the frame's shape alone, so the art and the shine moving over it never have
                // to be drawn again just to cast it.
                shape.fill(RadialGradient(colors: [rarity.fill.light, rarity.fill.edge],
                                          center: UnitPoint(x: 0.5, y: 0.3), startRadius: 4, endRadius: 140))
                    .perfShadow(color: rarity.shines ? rarity.tint.opacity(0.5) : .clear, radius: 9)
            }
            .overlay {
                if rarity.shines, shine { ShineSweep(period: rarity == .legendary ? 2.6 : 3.6).clipShape(shape) }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [rarity.tint, rarity.tint.opacity(rarity == .common ? 0.15 : 0.45)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: rarity == .common ? 1 : 1.5)
            }
    }
}

/// Whether the page under the shop's cards is being scrolled. Its own object, read only by the sweeps, so a scroll
/// starting or ending re-evaluates them and not the page.
@MainActor
@Observable
final class ShopScrolling {
    var isScrolling = false
}

/// Crosses once per period, only while on screen and the page holds still; still under Reduce Motion and in Low
/// Power Mode. An animated effect, not a timeline: SwiftUI moves it each frame without building the view again. Only
/// the crossing is animated: between crossings nothing moves, so the page and the glass over it can go idle.
private struct ShineSweep: View {
    let period: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ShopScrolling.self) private var scrolling: ShopScrolling?
    /// 0 to 1 through a crossing.
    @State private var progress = 0.0
    @State private var visible = false

    private var runs: Bool { visible && scrolling?.isScrolling != true }

    var body: some View {
        if !reduceMotion {
            GeometryReader { proxy in
                let width = proxy.size.width * 0.4
                LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
                    .rotationEffect(.degrees(12))
                    .modifier(SweepEffect(progress: progress, frameWidth: proxy.size.width, bandWidth: width))
            }
            .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
            .task(id: runs) {
                rest()
                guard runs else { return }
                let crossing = period * 0.45
                while !Task.isCancelled {
                    guard (try? await Task.sleep(for: .seconds(period - crossing))) != nil else { return }
                    if ProcessInfo.processInfo.isLowPowerModeEnabled { continue }
                    withAnimation(.linear(duration: crossing)) { progress = 1 }
                    guard (try? await Task.sleep(for: .seconds(crossing))) != nil else { return }
                    rest()
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Back out of sight at the start, without animating there.
    private func rest() {
        var still = Transaction(animation: nil)
        still.disablesAnimations = true
        withTransaction(still) { progress = 0 }
    }
}

/// Where the band is at `progress` through a crossing: out of sight on the left at 0, on the right at 1.
private struct SweepEffect: GeometryEffect {
    var progress: Double
    let frameWidth: CGFloat
    let bandWidth: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = -bandWidth * 1.5 + progress * (frameWidth + bandWidth * 2)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

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
                    .font(.ourioCaption.monospacedDigit())
                    .strikethrough()
                    .opacity(0.6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(was.map { $0 > price ? "\(price) coins, was \($0)" : "\(price) coins" } ?? "\(price) coins")
    }
}

extension View {
    /// Fades and rises a little into place as it scrolls in, straight up, never sideways; only a fade under Reduce
    /// Motion.
    func shopAppear() -> some View {
        modifier(ShopAppear())
    }
}

/// A card springs up as it comes into view while the page scrolls. Set once as it crosses in, not a scroll transition
/// worked out for every card on every scrolled frame, which was each card's work on the main thread through a whole
/// scroll.
private struct ShopAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ShopScrolling.self) private var scrolling: ShopScrolling?
    @State private var shown = true

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0.3)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onScrollVisibilityChange(threshold: 0.2) { visible in
                // A card already there when the page opens shows at once.
                guard scrolling?.isScrolling == true else { return shown = true }
                if visible {
                    withAnimation(.spring(duration: 0.5, bounce: 0.25)) { shown = true }
                } else {
                    shown = false
                }
            }
    }
}

enum ShopLayout {
    static let dealWidth: CGFloat = 176
}
