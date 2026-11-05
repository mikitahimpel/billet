import Pet
import SwiftUI

/// Where the cat sheet reads Mochi's four needs (0...1) and tells her she ate: her brain on this phone today, the
/// couple's cat journal on the server later, without the sheet changing.
@MainActor
protocol PetNeedsSource: AnyObject {
    var needs: PetNeeds? { get }
    func feed()
}

extension CatDirector: PetNeedsSource {}

/// Mochi's four needs as calm bars, each with the one thing that fills it. A low bar is an invitation, never a
/// warning: nothing turns red, blinks or shakes.
struct NeedBars: View {
    let name: String
    let needs: PetNeeds?
    var feed: () -> Void
    var pet: () -> Void
    var play: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ForEach(PetNeed.displayOrder, id: \.self) { need in
                NeedRow(need: need, name: name, value: needs?[need], action: action(for: need))
            }
        }
    }

    private func action(for need: PetNeed) -> NeedRow.Action? {
        switch need {
        case .full: NeedRow.Action(title: "Treat", detail: "\(HomeState.treatPrice)", run: feed)
        case .loved: NeedRow.Action(title: "Pet", detail: nil, run: pet)
        case .playful: NeedRow.Action(title: "Play", detail: nil, run: play)
        case .rested: nil
        }
    }
}

private struct NeedRow: View {
    struct Action {
        let title: String
        /// A price in coins, if it costs any.
        let detail: String?
        let run: () -> Void
    }

    let need: PetNeed
    let name: String
    let value: Double?
    let action: Action?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: need.symbol)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(need.hue)
                .frame(width: 30, height: 30)
                .background(need.hue.opacity(0.16), in: .circle)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(need.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                    Spacer(minLength: 8)
                    Text(line)
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                NeedTrack(value: value ?? 0, hue: need.hue)
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.2), value: value)
            }

            if let action {
                Button(action: action.run) {
                    HStack(spacing: 4) {
                        Text(action.title)
                        if let detail = action.detail {
                            CoinIcon(size: 13)
                            Text(detail).monospacedDigit()
                        }
                    }
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 64, minHeight: 34)
                    .background(need.hue.opacity(0.22), in: .capsule)
                    .overlay(Capsule().stroke(need.hue.opacity(0.35), lineWidth: 0.5))
                    .contentShape(.capsule)
                }
                .buttonStyle(PressScaleStyle())
            } else {
                Color.clear.frame(width: 64, height: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(need.title)
        .accessibilityValue(value.map { "\(Int(($0 * 100).rounded())) percent, \(line)" } ?? line)
    }

    /// Gentle words for where the bar is; an empty bar asks, it never complains.
    private var line: String {
        guard let value else { return "\(name) is settling in" }
        switch value {
        case 0.7...: return need.content
        case 0.35..<0.7: return need.middle
        default: return need.invitation(name)
        }
    }
}

/// A rounded track with a soft fill in the need's own hue.
private struct NeedTrack: View {
    let value: Double
    let hue: Color

    var body: some View {
        Capsule()
            .fill(Ink.card)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(LinearGradient(colors: [hue.opacity(0.75), hue], startPoint: .leading, endPoint: .trailing))
                        // A sliver even when empty, so the bar reads as waiting rather than gone.
                        .frame(width: max(proxy.size.height, proxy.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(height: 8)
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

    func invitation(_ name: String) -> String {
        switch self {
        case .full: "\(name) would love a treat"
        case .rested: "\(name) would love a cozy nap"
        case .playful: "\(name) would love to play"
        case .loved: "\(name) would love a cuddle"
        }
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
