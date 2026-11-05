import SwiftUI

/// "How are you?" in the header, next to the Inbox: the viewer's own mood once they've shared one today, and the
/// partner's as a small badge.
struct MoodButton: View {
    let state: HomeState
    var action: () -> Void

    private var mine: MoodCheckIn? { state.partnerMoods.latest[state.viewer].flatMap { $0.isFresh() ? $0 : nil } }
    private var theirs: MoodCheckIn? {
        state.partnerMoods.latest[state.otherPartner].flatMap { $0.isFresh() ? $0 : nil }
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let mine {
                    Text(mine.mood.emoji).font(.system(size: 20))
                } else {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                }
            }
            .frame(width: 42, height: 42)
            .warmGlass(.circle, interactive: true)
            .overlay(alignment: .topTrailing) {
                if let theirs {
                    Text(theirs.mood.emoji)
                        .font(.system(size: 11))
                        .frame(width: 20, height: 20)
                        .background(.white, in: .circle)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("How are you?")
        .accessibilityValue(value)
        .accessibilityIdentifier("mood")
    }

    private var value: String {
        let partner = state.profile.name(of: state.otherPartner)
        return [
            mine.map { "You feel \($0.mood.title)" },
            theirs.map { "\(partner) feels \($0.mood.title)" },
        ].compactMap(\.self).joined(separator: ", ")
    }
}

/// The check-in: four moods to tap and a few words if they like. Sharing sends it to the partner.
struct MoodPicker: View {
    let state: HomeState
    @Environment(\.dismiss) private var dismiss
    @State private var mood: PartnerMood?
    @State private var note = ""
    @State private var height: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SheetHeader(title: "How are you, \(state.profile.name(of: state.viewer))?", chips: { EmptyView() }) {
                dismiss()
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)],
                      spacing: Space.s) {
                ForEach(PartnerMood.allCases, id: \.self) { choice in
                    MoodChip(mood: choice, picked: mood == choice) { mood = choice }
                }
            }

            TextField("A few words (optional)", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .font(.nookiCallout)
                .padding(Space.m)
                .background(Ink.surfaceRaised, in: .rect(cornerRadius: Radius.control, style: .continuous))
                .onChange(of: note) { _, new in
                    if new.utf16.count > MoodCheckIn.noteLimit { note = MoodCheckIn.clean(new) ?? "" }
                }
                .accessibilityIdentifier("moodNote")

            Button {
                guard let mood else { return }
                state.setMood(mood, note: note)
                dismiss()
            } label: {
                Text(mood == nil ? "Pick how you feel" : "Share with \(state.profile.name(of: state.otherPartner))")
                    .frame(maxWidth: .infinity)
            }
            .nookiPrimary()
            .disabled(mood == nil)
            .accessibilityIdentifier("shareMood")

            if let theirs = state.partnerMoods.latest[state.otherPartner], theirs.isFresh() {
                PartnerLine(name: state.profile.name(of: state.otherPartner), check: theirs)
            }
        }
        .padding(Space.l)
        .shopSheet(height: $height)
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
                Text(mood.emoji).font(.system(size: 34))
                Text(mood.title.capitalized)
                    .font(.nookiCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(picked ? Color.honey.opacity(0.22) : Ink.surfaceRaised,
                        in: .rect(cornerRadius: Radius.card, style: .continuous))
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
            Text(check.mood.emoji).font(.system(size: 22))
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
        }
        .accessibilityElement(children: .combine)
    }
}
