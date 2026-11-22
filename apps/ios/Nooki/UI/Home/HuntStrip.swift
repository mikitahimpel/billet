import Design
import FeatureMischief
import MischiefInterface
import SwiftUI

/// Over the room while the partner's mouse is hunted: where to look, and what the cat made of the last look. She is
/// the hint; the words only repeat what she did, for whoever cannot see it.
struct HuntStrip: View {
    let state: HomeState

    private var model: MischiefModel { state.mischief }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            switch model.hunt {
            case .hunting(let hunt): hunting(hunt)
            case .found(let found): foundCard(found)
            case .idle: EmptyView()
            }
        }
        .padding(CardMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .animation(Motion.spring(0.3), value: model.hunt)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("huntStrip")
    }

    private func hunting(_ hunt: MischiefHuntMachine.Hunt) -> some View {
        let partner = state.profile.name(of: state.otherPartner)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.words(hunt, cat: state.petName, partner: partner))
                    .font(.ourioCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: Space.s)
                Button("Not now") { model.send(.leave) }
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.text)
                    .frame(minHeight: Size.control)
                    .accessibilityHint("The mouse stays hidden")
                    .accessibilityIdentifier("huntLeave")
            }
            ScrollView(.horizontal) {
                HStack(spacing: Space.s) {
                    ForEach(model.spots(including: hunt.hide.spot), id: \.self) { spot in
                        let looked = hunt.looks.first { $0.spot == spot }
                        LookChip(spot: spot, warmth: looked?.warmth) { model.look(at: spot) }
                            .disabled(looked != nil)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func foundCard(_ found: MischiefHuntMachine.Found) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Found it \(found.hide.spot.phrase)!")
                .font(.ourioValue)
                .foregroundStyle(Ink.text)
            Text("\(MischiefTime.spoken(seconds: found.seconds)), \(found.tries == 1 ? "first try" : "\(found.tries) tries")")
                .font(.ourioCallout)
                .foregroundStyle(Ink.text)
            if let line = found.hide.line {
                Text("“\(line)”")
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PillButton("Done", symbol: "checkmark") { model.send(.dismissed) }
                .accessibilityIdentifier("huntDone")
        }
    }

    static func words(_ hunt: MischiefHuntMachine.Hunt, cat: String, partner: String) -> String {
        guard let last = hunt.last else { return "Where did \(partner) hide it? \(cat) knows." }
        if hunt.misses >= MischiefHuntMachine.leadsAfter { return "\(cat) is showing you." }
        switch last.warmth {
        case .cold: return "\(cat) yawns. Not there."
        case .cool: return "\(cat)'s ear flicks."
        case .warm: return "\(cat)'s ears go up. Close."
        case .hot: return "\(cat) sniffs. Very close."
        }
    }
}

private struct LookChip: View {
    let spot: MischiefSpot
    let warmth: Warmth?
    var look: () -> Void

    var body: some View {
        PillButton(spot.title, symbol: spot.symbol, action: look)
            .opacity(warmth == nil ? 1 : 0.5)
            .accessibilityLabel(warmth.map { "\(spot.title), \(Self.spoken($0))" } ?? spot.title)
            .accessibilityIdentifier("look-\(spot.rawValue)")
    }

    private static func spoken(_ warmth: Warmth) -> String {
        switch warmth {
        case .cold: "cold"
        case .cool: "cool"
        case .warm: "warm"
        case .hot: "hot"
        }
    }
}
