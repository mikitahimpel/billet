import MomentsInterface
import MoodInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import UsInterface

struct MoodPicker: View {
    let state: HomeState
    @Environment(\.dismiss) private var dismiss
    @State private var mood: PartnerMood?
    @State private var note = ""

    var body: some View {
        BilletSheet("How are you, \(state.profile.name(of: state.viewer))?", size: .fit) {
            VStack(alignment: .leading, spacing: Space.l) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)],
                          spacing: Space.s) {
                    ForEach(PartnerMood.allCases, id: \.self) { choice in
                        MoodChip(mood: choice, picked: mood == choice) { mood = choice }
                    }
                }

                Field("A few words (optional)", text: $note, axis: .vertical, lines: 1...3)
                    .onChange(of: note) { _, new in
                        if new.utf16.count > MoodCheckIn.noteLimit { note = MoodCheckIn.clean(new) ?? "" }
                    }
                    .accessibilityIdentifier("moodNote")

                PrimaryButton(mood == nil ? "Pick how you feel" : "Share with \(state.profile.name(of: state.otherPartner))") {
                    guard let mood else { return }
                    state.setMood(mood, note: note)
                    dismiss()
                }
                .disabled(mood == nil)
                .accessibilityIdentifier("shareMood")

                if let theirs = state.partnerMoods.latest[state.otherPartner], theirs.isFresh() {
                    PartnerLine(name: state.profile.name(of: state.otherPartner), check: theirs)
                }
            }
        }
        .accessibilityIdentifier("moodPicker")
        .onAppear {
            let current = state.partnerMoods.latest[state.viewer]
            mood = current.flatMap { $0.isFresh() ? $0.mood : nil }
            note = current.flatMap { $0.isFresh() ? $0.note : nil } ?? ""
        }
    }
}

private struct MoodChip: View {
    let mood: PartnerMood
    let picked: Bool
    var pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(spacing: Space.s) {
                MoodArt(mood: mood, size: 48)
                Text(mood.title.capitalized)
                    .font(.ourioCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.l)
            .cardSurface(state: picked ? .selected : .rest)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(mood.title.capitalized)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: picked)
    }
}

private struct PartnerLine: View {
    let name: String
    let check: MoodCheckIn

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            MoodArt(mood: check.mood, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name) feels \(check.mood.title)")
                    .font(.ourioCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
                if let note = check.note {
                    Text(note)
                        .font(.ourioCallout)
                        .foregroundStyle(Ink.textSecondary)
                }
                Text(check.date, format: .relative(presentation: .named))
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(CardMetrics.padding)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}
