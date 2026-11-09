import PhotosUI
import SwiftUI
import Design

/// Closes a date: hearts, and a photo from it that goes into Moments (and to the partner, as any new moment does).
struct DateDoneSheet: View {
    let state: HomeState
    let plan: PlannedDate

    @Environment(\.dismiss) private var dismiss
    @State private var hearts = 3
    @State private var pick: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var caption: String

    init(state: HomeState, plan: PlannedDate) {
        self.state = state
        self.plan = plan
        _caption = State(initialValue: DateIdea.idea(plan.ideaID)?.title ?? "Date night")
    }

    var body: some View {
        BilletSheet("How was it?", size: .fit) {
                VStack(spacing: 14) {
                    if let title = DateIdea.idea(plan.ideaID)?.title { SheetSubtitle(text: title) }
                    HStack(spacing: 18) {
                        ForEach(1...3, id: \.self) { value in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { hearts = value }
                            } label: {
                                Image(systemName: value <= hearts ? "heart.fill" : "heart")
                                    .font(.system(.largeTitle, weight: .semibold))
                                    .foregroundStyle(Color.blushPink)
                                    .symbolEffect(.bounce, value: hearts == value)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(value == 1 ? "1 heart" : "\(value) hearts")
                            .accessibilityAddTraits(value == hearts ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    PhotosPicker(selection: $pick, matching: .images) {
                        photoSlot
                    }
                    .buttonStyle(.plain)

                    if photo != nil {
                        UsField(placeholder: "Caption", text: $caption)
                    }

                    PrimaryButton(photo == nil ? "Done" : "Done, add to Moments") { save() }
                        .padding(.top, 4)
                }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let image = await item.loadImage(maxPixels: MomentStore.storedPixels) {
                    withAnimation(.snappy(duration: 0.25)) { photo = image }
                }
            }
        }
    }

    @ViewBuilder
    private var photoSlot: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Label("Change", systemImage: "photo")
                        .font(.nookiCaption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: .capsule)
                        .padding(10)
                }
                .accessibilityLabel("Change photo")
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(.title, weight: .semibold))
                    .foregroundStyle(Color.honey)
                Text("Add a photo from the date")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Text("It goes into your Moments")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .cardSurface()
        }
    }

    private func save() {
        var momentID: UUID?
        if let photo {
            let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            // addMoment puts the newest photo first.
            if state.journal.addMoment(photo, caption: text, shares: true) {
                momentID = state.moments.moments.first?.id
            }
        }
        state.us.rate(plan.id, hearts: hearts, momentID: momentID)
        DateReminders.cancel(plan.id)
        dismiss()
    }
}

struct DatePlannerSheet: View {
    let state: HomeState
    let ideaID: Int
    let existing: PlannedDate?
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var place: String
    @State private var organizer: String
    @State private var surprise: Bool
    @State private var hint: String
    @State private var remind: Bool

    init(state: HomeState, target: PlannerTarget, onSaved: @escaping () -> Void) {
        self.state = state
        self.ideaID = target.ideaID
        self.existing = target.existing
        self.onSaved = onSaved
        _date = State(initialValue: target.existing?.date ?? Date.now.addingTimeInterval(86_400))
        _place = State(initialValue: target.existing?.place ?? "")
        _organizer = State(initialValue: target.existing?.organizer ?? state.viewer)
        _surprise = State(initialValue: target.existing?.surprise ?? false)
        _hint = State(initialValue: target.existing?.hint ?? "")
        _remind = State(initialValue: target.existing?.remind ?? (target.existing == nil))
    }

    var body: some View {
        BilletSheet(DateIdea.idea(ideaID)?.title ?? "Plan a date", size: .mediumLarge, onConfirm: { save() }) {
                VStack(alignment: .leading, spacing: 12) {
                    SheetSubtitle(text: "Pick a day and what you'll do")
                    DatePicker("When", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .tint(.honey)
                        .font(.nookiBody)
                        .foregroundStyle(Ink.text)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .cardSurface(radius: Radius.control)

                    UsField(placeholder: "Place, e.g. our kitchen", text: $place)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Who plans it")
                            .font(.nookiCaption.weight(.semibold))
                            .foregroundStyle(Ink.textSecondary)
                        HStack(spacing: 8) {
                            ForEach([state.partners.0, state.partners.1], id: \.self) { initial in
                                FilterChip(initial, isSelected: organizer == initial) {
                                    organizer = initial
                                }
                            }
                        }
                    }

                    Toggle("Surprise mode", isOn: $surprise)
                        .font(.nookiBody)
                        .foregroundStyle(Ink.text)
                        .tint(.honey)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .cardSurface(radius: Radius.control)

                    if surprise {
                        UsField(placeholder: "Hint, e.g. dress warm", text: $hint)
                    }

                    Toggle("Remind us a day and an hour before", isOn: $remind)
                        .font(.nookiBody)
                        .foregroundStyle(Ink.text)
                        .tint(.honey)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .cardSurface(radius: Radius.control)

                }
        }
    }

    private func save() {
        let plan = PlannedDate(
            id: existing?.id ?? UUID(),
            ideaID: ideaID,
            date: date,
            place: place.trimmingCharacters(in: .whitespacesAndNewlines),
            organizer: organizer,
            surprise: surprise,
            hint: hint.trimmingCharacters(in: .whitespacesAndNewlines),
            remind: remind
        )
        state.us.upsertPlan(plan)
        let title = DateIdea.idea(ideaID)?.title ?? "Date night"
        let organizerName = state.profile.name(of: organizer)
        Task { await DateReminders.schedule(plan, title: title, organizer: organizerName) }
        onSaved()
        dismiss()
    }
}
