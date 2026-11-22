import Design
import FeatureMischief
import MischiefInterface
import SwiftUI

/// Hide and seek with the toy mouse: look for the one the partner hid, hide one for them, and see how the last ones
/// went. Nothing here counts down; a mouse waits.
struct MischiefSheet: View {
    let state: HomeState

    @Environment(\.dismiss) private var dismiss

    private var model: MischiefModel { state.mischief }
    private var partner: String { state.profile.name(of: state.otherPartner) }

    var body: some View {
        BilletSheet("Hide & seek", size: .fit) {
            VStack(alignment: .leading, spacing: Space.section) {
                if let theirs = model.theirs { seek(theirs) }
                hide
                past
            }
        }
        .accessibilityIdentifier("mischiefSheet")
        .onAppear { if model.mine == nil, model.hiding == .closed, model.theirs == nil { model.send(.opened) } }
        .onDisappear { model.send(.cancelled) }
    }

    private func seek(_ hide: MischiefHide) -> some View {
        Card(warm: true) {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("\(partner) hid the mouse for you")
                    .font(.ourioValue)
                    .foregroundStyle(Ink.text)
                Text("\(state.petName) knows where. Watch for \(state.petName)'s hints.")
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.textSecondary)
                PrimaryButton("Go look", symbol: "magnifyingglass") {
                    model.beginHunt()
                    dismiss()
                }
                .accessibilityIdentifier("mischiefGoLook")
            }
        }
    }

    @ViewBuilder private var hide: some View {
        switch model.hiding {
        case .choosing(let draft): chooser(draft)
        case .closed:
            if let mine = model.mine {
                VStack(alignment: .leading, spacing: Space.m) {
                    SectionHeader("Your mouse", symbol: "sparkle.magnifyingglass")
                    Card {
                        VStack(alignment: .leading, spacing: Space.m) {
                            Text("Hidden \(mine.spot.phrase). Waiting for \(partner).")
                                .font(.ourioCallout)
                                .foregroundStyle(Ink.text)
                            if let line = mine.line {
                                Text("“\(line)”")
                                    .font(.ourioCallout)
                                    .foregroundStyle(Ink.textSecondary)
                            }
                            SecondaryButton("Hide it somewhere else", symbol: "arrow.triangle.2.circlepath") {
                                model.send(.opened)
                            }
                        }
                    }
                }
            } else {
                SecondaryButton("Hide the mouse for \(partner)", symbol: "sparkle.magnifyingglass") {
                    model.send(.opened)
                }
                .accessibilityIdentifier("mischiefHide")
            }
        }
    }

    private func chooser(_ draft: MischiefHideMachine.Draft) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("Where does it go?", symbol: "sparkle.magnifyingglass")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)],
                      spacing: Space.s) {
                ForEach(model.spots(), id: \.self) { spot in
                    SpotChip(spot: spot, picked: draft.spot == spot) { model.send(.picked(spot)) }
                }
            }
            Field("A few words to go with it (optional)", text: line(draft))
                .accessibilityIdentifier("mischiefLine")
            PrimaryButton("Hide it", symbol: "checkmark") {
                model.send(.submitted)
                if state.mischief.mine != nil { dismiss() }
            }
            .disabled(!draft.canHide)
            .accessibilityIdentifier("mischiefSubmit")
        }
    }

    private func line(_ draft: MischiefHideMachine.Draft) -> Binding<String> {
        Binding(get: { draft.line }, set: { model.send(.wrote($0)) })
    }

    @ViewBuilder private var past: some View {
        let over = Array(model.over.prefix(3))
        if !over.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                SectionHeader("Lately", symbol: "clock")
                ForEach(over, id: \.hide.id) { item in
                    Card { MischiefResultLine(hide: item.hide, status: item.status, model: model, partner: partner,
                                              cat: state.petName) }
                }
            }
        }
    }
}

/// One finished hide, in words.
private struct MischiefResultLine: View {
    let hide: MischiefHide
    let status: MischiefStatus
    let model: MischiefModel
    let partner: String
    let cat: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(headline)
                .font(.ourioCallout.weight(.semibold))
                .foregroundStyle(Ink.text)
            if let line = hide.line, case .found = status {
                Text("“\(line)”")
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
    }

    private var headline: String {
        let hider = model.isMine(hide) ? "your" : "\(partner)'s"
        switch status {
        case .found(let found):
            let who = found.by == hide.by ? "" : (model.isMine(hide) ? partner : "You")
            return "\(who) found \(hider) mouse \(hide.spot.phrase) in \(MischiefTime.spoken(seconds: found.seconds))"
                .trimmingCharacters(in: .whitespaces).capitalizedFirst
        case .turnedUp: return "\(cat) found \(hider) mouse \(hide.spot.phrase) and left it by the door"
        case .hidden, .replaced: return ""
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

struct SpotChip: View {
    let spot: MischiefSpot
    let picked: Bool
    var pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: Space.s) {
                Image(systemName: spot.symbol)
                    .foregroundStyle(Ink.accentText)
                    .frame(width: 24)
                Text(spot.title)
                    .font(.ourioCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.m)
            .frame(maxWidth: .infinity, minHeight: Size.button, alignment: .leading)
            .cardSurface(state: picked ? .selected : .rest)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(spot.title)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: picked)
    }
}
