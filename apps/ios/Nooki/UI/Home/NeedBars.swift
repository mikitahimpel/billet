import FeatureGames
import GamesInterface
import Pet
import SwiftUI
import Design

/// Where the cat sheet reads Mochi's four needs (0...1) and tells her she ate: her brain on this phone today, the
/// couple's cat journal on the server later, without the sheet changing.
@MainActor
protocol PetNeedsSource: AnyObject {
    var needs: PetNeeds? { get }
    func feed()
}

extension RoomController: PetNeedsSource {
    var needs: PetNeeds? { status.needs }
}

/// Mochi's four needs as warm, chunky bars, two by two on one clay card. A low bar is an invitation, never a warning:
/// nothing turns red, blinks or shakes.
struct NeedBars: View {
    let name: String
    let needs: PetNeeds?

    var body: some View {
        Group {
            if let needs {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.l), GridItem(.flexible())], spacing: Space.m) {
                    ForEach(PetNeed.displayOrder, id: \.self) { need in
                        NeedCell(need: need, name: name, value: needs[need])
                    }
                }
            } else {
                // Before her needs are known: one calm line rather than four empty bars.
                Text("\(name) is settling in. Her needs show here soon.")
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding(Space.m + 2)
        .cardSurface()
    }
}

private struct NeedCell: View {
    let need: PetNeed
    let name: String
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: need.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(LinearGradient(colors: [need.hue.mix(with: .white, by: 0.2), need.hue],
                                               startPoint: .top, endPoint: .bottom), in: .circle)
                    .shadow(color: need.hue.opacity(0.35), radius: 3, y: 2)
                Text(need.title)
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
            }
            NeedTrack(value: value, hue: need.hue)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.2), value: value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(need.title)
        .accessibilityValue("\(Int((value * 100).rounded())) percent, \(need.line(for: value, name: name))")
    }
}

/// What the couple can do for her, as big clay tiles: the games start in the room once the sheet is down.
struct PetActions: View {
    var treat: () -> Void
    var pet: () -> Void
    var play: (MiniGame) -> Void

    private struct Action: Identifiable {
        let title: String
        let symbol: String
        let hue: Color
        /// A price in coins, if it costs any.
        var price: Int?
        let run: () -> Void
        var id: String { title }
    }

    private var actions: [Action] {
        [
            Action(title: "Feed", symbol: "fork.knife", hue: PetNeed.full.hue, run: { play(.feed) }),
            Action(title: "Water", symbol: "drop.fill", hue: PetNeed.rested.hue, run: { play(.water) }),
            Action(title: "Play", symbol: "tennisball.fill", hue: PetNeed.playful.hue, run: { play(.laser) }),
            Action(title: "Brush", symbol: "paintbrush.fill", hue: PetNeed.loved.hue, run: { play(.brush) }),
            Action(title: "Pet", symbol: "hand.raised.fill", hue: PetNeed.loved.hue, run: pet),
            Action(title: "Treat", symbol: "gift.fill", hue: PetNeed.full.hue, price: ShopModel.treatPrice, run: treat),
        ]
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 3), spacing: Space.s) {
            ForEach(actions) { action in
                Button(action: action.run) {
                    VStack(spacing: 6) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(LinearGradient(colors: [action.hue.mix(with: .white, by: 0.2),
                                                                action.hue],
                                                       startPoint: .top, endPoint: .bottom), in: .circle)
                            .shadow(color: action.hue.opacity(0.4), radius: 4, y: 2)
                        HStack(spacing: 3) {
                            Text(action.title)
                            if let price = action.price {
                                CoinIcon(size: 12)
                                Text("\(price)").monospacedDigit()
                            }
                        }
                        .font(.nookiCallout.weight(.semibold))
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .cardSurface(warm: true)
                    .contentShape(.rect(cornerRadius: Radius.card))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(action.price.map { "\(action.title), \($0) coins" } ?? action.title)
            }
        }
    }
}

/// A thick rounded track with a glossy fill in the need's own hue.
private struct NeedTrack: View {
    let value: Double
    let hue: Color

    var body: some View {
        Capsule()
            .fill(Ink.surfaceRaised)
            .overlay(Capsule().strokeBorder(Ink.separator, lineWidth: 0.5))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(LinearGradient(colors: [hue.mix(with: .white, by: 0.25), hue],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .top) {
                            Capsule().fill(.white.opacity(0.35)).frame(height: 3).padding(.horizontal, 5).padding(.top, 2)
                        }
                        // A sliver even when empty, so the bar reads as waiting rather than gone.
                        .frame(width: max(proxy.size.height, proxy.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(height: 14)
    }
}

extension PetNeed {
    /// Full, Rested, Playful, Loved: the order the sheet lists them.
    static let displayOrder: [PetNeed] = [.full, .rested, .playful, .loved]

    var title: String {
        switch self {
        case .full: "Full"
        case .rested: "Rested"
        case .playful: "Playful"
        case .loved: "Loved"
        }
    }

    var symbol: String {
        switch self {
        case .full: "fork.knife"
        case .rested: "moon.zzz.fill"
        case .playful: "tennisball.fill"
        case .loved: "heart.fill"
        }
    }

    /// One warm family: honey, sand, coral, blush.
    var hue: Color {
        switch self {
        case .full: Color(hex: 0xF2A65E)
        case .rested: Color(hex: 0xE8C47A)
        case .playful: Color(hex: 0xF08A5D)
        case .loved: Color(hex: 0xFF8FA3)
        }
    }

    var content: String {
        switch self {
        case .full: "Happily full"
        case .rested: "Well rested"
        case .playful: "Had a lovely play"
        case .loved: "Feels so loved"
        }
    }

    var middle: String {
        switch self {
        case .full: "Could nibble something"
        case .rested: "A little sleepy"
        case .playful: "Up for a game"
        case .loved: "Glad you're here"
        }
    }

    /// Gentle words for where the bar is; an empty bar asks, it never complains.
    func line(for value: Double, name: String) -> String {
        switch value {
        case 0.7...: content
        case 0.35..<0.7: middle
        default: invitation(name)
        }
    }

    func invitation(_ name: String) -> String {
        switch self {
        case .full: "\(name) would love a treat"
        case .rested: "\(name) would love a cozy nap"
        case .playful: "\(name) would love to play"
        case .loved: "\(name) would love a cuddle"
        }
    }
}

extension PetNeeds {
    /// Her mood in a few words, from her lowest need.
    func moodLine(name: String) -> String {
        let (need, value) = lowest
        return value >= 0.7 ? "Happy and cosy" : need.line(for: value, name: name)
    }
}

/// Fixed needs for the UI tests and screenshots (`-uitestNeeds 0.2` sets all four to 20%); nil in normal use.
final class FixedNeeds: PetNeedsSource {
    let needs: PetNeeds?

    private init(_ value: Double) {
        needs = PetNeeds(all: value)
    }

    func feed() {}

    static let fromLaunch: FixedNeeds? = UserDefaults.standard.string(forKey: "uitestNeeds")
        .flatMap(Double.init)
        .map { FixedNeeds($0) }
}
