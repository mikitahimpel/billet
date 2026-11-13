import Pet
import RoomInterface
import SwiftUI
import Design

/// Where the cat sheet reads Mochi (her four needs, 0...1, her day and what kind of cat she is) and tells her she
/// ate: her brain on this phone today, the couple's cat journal on the server later, without the sheet changing.
@MainActor
protocol PetNeedsSource: AnyObject {
    var status: CatStatus { get }
    func feed()
}

extension PetNeedsSource {
    var needs: PetNeeds? { status.needs }
}

extension RoomController: PetNeedsSource {}

/// Mochi's four needs, a gauge each in two columns: how full it is as a ring and a number, how she feels in a word,
/// when it next runs low, and the care a tap on the tile gives. Only the lowest need, and only while it wants
/// something, is raised.
struct NeedGrid: View {
    let name: String
    let pronouns: CatPronouns
    let needs: PetNeeds?
    let asleep: Bool
    var care: (NeedCare) -> Void
    /// Why a care is turned down just now, or nil while it is welcome.
    var declined: (NeedCare) -> String? = { _ in nil }

    var body: some View {
        if let needs {
            let raised = NeedLevel.cue(needs)
            ItemGrid {
                ForEach(PetNeed.displayOrder, id: \.self) { need in
                    tile(need, in: needs, raised: need == raised)
                }
            }
        } else {
            // Before her needs are known: one calm line rather than four empty gauges.
            Card {
                Text(pronouns.say(.needsSettlingIn(name: name)))
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func tile(_ need: PetNeed, in needs: PetNeeds, raised: Bool) -> some View {
        let value = needs[need]
        let state = need.word(NeedLevel(value))
        let hint = need.hint(NeedForecast.outlook(need, in: needs, asleep: asleep))
        let emphasis: GaugeTile.Emphasis = raised ? .raised : .quiet
        if let action = need.care, let why = declined(action) {
            GaugeTile(need.title, state: state, hint: hint, value: value, symbol: need.symbol, tint: need.tint,
                      emphasis: .quiet, note: why)
        } else if let action = need.care {
            GaugeTile(need.title, state: state, hint: hint, value: value, symbol: need.symbol, tint: need.tint,
                      emphasis: emphasis, action: action.title) {
                care(action)
            }
            .accessibilityHint(action.hint(name: name))
            .accessibilityIdentifier(action.title)
        } else {
            GaugeTile(need.title, state: state, hint: hint, value: value, symbol: need.symbol, tint: need.tint,
                      emphasis: emphasis, note: need.note(pronouns: pronouns) ?? "")
        }
    }
}

/// A fixed cat for the UI tests and screenshots (`-uitestNeeds 0.2` sets all four needs to 20%); nil in normal use.
final class FixedNeeds: PetNeedsSource {
    let status: CatStatus

    init(_ status: CatStatus) {
        self.status = status
    }

    func feed() {}

    static let fromLaunch: FixedNeeds? = UserDefaults.standard.string(forKey: "uitestNeeds")
        .flatMap(Double.init)
        .map { FixedNeeds(CatStatus(needs: PetNeeds(all: $0))) }
}
