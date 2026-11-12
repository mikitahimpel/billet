import Design
import FeatureOnboarding
import Pet
import SwiftUI

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
