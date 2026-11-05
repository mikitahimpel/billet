import FeatureGames
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

/// Mochi's four needs as calm bars, each with the things that fill it: a mini-game, and a pet or a treat. A low bar
/// is an invitation, never a warning: nothing turns red, blinks or shakes.
struct NeedBars: View {
    let name: String
    let needs: PetNeeds?
    var treat: () -> Void
    var pet: () -> Void
    var play: (MiniGame) -> Void

    var body: some View {
        if let needs {
            VStack(spacing: 14) {
                ForEach(PetNeed.displayOrder, id: \.self) { need in
                    NeedRow(need: need, name: name, value: needs[need], actions: actions(for: need))
                }
            }
        } else {
            // Before her needs are known: one calm line and the things to do, rather than four empty bars.
            VStack(spacing: 14) {
                Text("\(name) is settling in. Her needs show here soon.")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
                    .multilineTextAlignment(.center)
                NeedActions(actions: PetNeed.displayOrder.flatMap { need in actions(for: need).map { ($0, need.hue) } })
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func actions(for need: PetNeed) -> [NeedRow.Action] {
        switch need {
        case .full: [
            NeedRow.Action(title: "Feed", detail: nil, run: { play(.feed) }),
            NeedRow.Action(title: "Water", detail: nil, run: { play(.water) }),
            NeedRow.Action(title: "Treat", detail: "\(ShopModel.treatPrice)", run: treat),
        ]
        case .loved: [
            NeedRow.Action(title: "Brush", detail: nil, run: { play(.brush) }),
            NeedRow.Action(title: "Pet", detail: nil, run: pet),
        ]
        case .playful: [NeedRow.Action(title: "Play", detail: nil, run: { play(.laser) })]
        case .rested: []
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
    let actions: [Action]
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
                Text(need.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.text)
                NeedTrack(value: value ?? 0, hue: need.hue)
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.2), value: value)
                Text(line)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(Ink.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                if !actions.isEmpty { NeedActions(actions: actions.map { ($0, need.hue) }) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(need.title)
        .accessibilityValue(value.map { "\(Int(($0 * 100).rounded())) percent, \(line)" } ?? line)
    }

    /// Gentle words for where the bar is; an empty bar asks, it never complains.
    private var line: String {
        guard let value else { return need.middle }
        switch value {
        case 0.7...: return need.content
        case 0.35..<0.7: return need.middle
        default: return need.invitation(name)
        }
    }
}

/// A need's actions side by side, wrapping onto a second line when they don't fit.
private struct NeedActions: View {
    let actions: [(NeedRow.Action, Color)]

    var body: some View {
        FlowRow(spacing: 6) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
                NeedActionButton(action: item.0, hue: item.1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}

/// Lays its children out left to right, starting a new line when one would overflow.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { row in row.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(row.count - 1, 0)) }.max() ?? 0
        let height = rows.map { $0.map(\.height).max() ?? 0 }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var index = 0
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            let height = row.map(\.height).max() ?? 0
            for size in row {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
                index += 1
            }
            y += height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [[CGSize]] {
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        return rows
    }
}

/// A need's action (Feed, Treat, Play, Pet) as a capsule in the need's hue.
private struct NeedActionButton: View {
    let action: NeedRow.Action
    let hue: Color

    var body: some View {
        Button(action: action.run) {
            HStack(spacing: 4) {
                Text(action.title)
                if let detail = action.detail {
                    CoinIcon(size: 13)
                    Text(detail).monospacedDigit()
                }
            }
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 12)
            .frame(minWidth: 56, minHeight: 32)
            .background(hue.opacity(0.22), in: .capsule)
            .overlay(Capsule().stroke(hue.opacity(0.35), lineWidth: 0.5))
            .contentShape(.capsule)
        }
        .buttonStyle(PressScaleStyle())
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
