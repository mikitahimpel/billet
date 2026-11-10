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

/// Mochi's four needs, one row each: what it is, how she feels in a word, and the care a tap on the row gives. Only a
/// need that wants something, and at most two of them, is raised.
struct NeedList: View {
    let name: String
    let needs: PetNeeds?
    var care: (NeedCare) -> Void

    var body: some View {
        if let needs {
            let raised = NeedLevel.raised(needs)
            GroupedSection(inset: StatusRow.inset) {
                ForEach(PetNeed.displayOrder, id: \.self) { need in
                    row(need, value: needs[need], raised: raised.contains(need))
                }
            }
        } else {
            // Before her needs are known: one calm line rather than four empty rows.
            Card {
                Text("\(name) is settling in. Her needs show here soon.")
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func row(_ need: PetNeed, value: Double, raised: Bool) -> some View {
        let level = NeedLevel(value)
        let emphasis: StatusRow.Emphasis = raised ? .raised : .quiet
        if let action = need.care {
            StatusRow(need.title, state: need.word(level), symbol: need.symbol, tint: need.tint, emphasis: emphasis,
                      value: need.spoken(value), action: action.title, hint: action.hint(name: name)) {
                care(action)
            }
            .accessibilityIdentifier(action.title)
        } else {
            StatusRow(need.title, state: need.word(level), symbol: need.symbol, tint: need.tint, emphasis: emphasis,
                      value: need.spoken(value), note: need.note ?? "")
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
