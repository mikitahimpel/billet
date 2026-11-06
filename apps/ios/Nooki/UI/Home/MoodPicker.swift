import SwiftUI
import Design

/// The check-in: four moods to tap and a few words if they like. Sharing sends it to the partner.
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

                TextField("A few words (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.text)
                    .padding(Space.m)
                    .background(Ink.surfaceRaised, in: .rect(cornerRadius: Radius.control, style: .continuous))
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
            VStack(spacing: Space.xs) {
                Text(mood.emoji)
                    .font(.largeTitle)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Ink.surfaceRaised))
                Text(mood.title.capitalized)
                    .font(.nookiCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .cardSurface(warm: picked)
            .overlay {
                if picked {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Color.honey, lineWidth: 2)
                }
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(mood.title.capitalized)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: picked)
    }
}

/// What the partner last shared, under the picker.
private struct PartnerLine: View {
    let name: String
    let check: MoodCheckIn

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Text(check.mood.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name) feels \(check.mood.title)")
                    .font(.nookiCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
                if let note = check.note {
                    Text(note)
                        .font(.nookiCallout)
                        .foregroundStyle(Ink.textSecondary)
                }
                Text(check.date, format: .relative(presentation: .named))
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}
