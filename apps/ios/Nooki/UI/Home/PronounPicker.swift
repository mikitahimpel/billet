import Design
import Pet
import SwiftUI

/// One of she / he / they, in a row that falls back to a column where the labels don't fit.
struct PronounPicker: View {
    let selection: CatPronouns
    var choose: (CatPronouns) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s) { options }
            VStack(spacing: Space.s) { options }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var options: some View {
        ForEach(CatPronouns.allCases, id: \.self) { pronouns in
            Button { choose(pronouns) } label: {
                Text(pronouns.label).lineLimit(1)
            }
            .buttonStyle(ToggleButtonStyle(isOn: selection == pronouns))
            .accessibilityIdentifier("pronouns-\(pronouns.rawValue)")
        }
    }
}

/// The cat sheet's last block: how the app words the cat, for both of you.
struct PronounsCard: View {
    let name: String
    let selection: CatPronouns
    var choose: (CatPronouns) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("Pronouns", symbol: "text.bubble.fill")
            Card {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("How the app talks about \(name). Your partner sees it too.")
                        .font(.ourioCallout)
                        .foregroundStyle(Ink.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PronounPicker(selection: selection, choose: choose)
                }
            }
        }
    }
}
