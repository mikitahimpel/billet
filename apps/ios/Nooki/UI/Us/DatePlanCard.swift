import PhotosUI
import SwiftUI
import Design

struct DateMatchOverlay: View {
    let idea: DateIdea
    var onPlan: () -> Void
    var onKeep: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("It's a match!")
                    .font(.nookiLargeTitle)
                    .foregroundStyle(Ink.text)
                UsIcon(glyph: .init(symbol: "heart.fill", tint: .blush), size: 72)
                Text(idea.title)
                    .font(.nookiTitle)
                    .foregroundStyle(Ink.text)
                    .multilineTextAlignment(.center)
                Label("+10", systemImage: "star.fill")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.accentText)

                HStack(spacing: 10) {
                    Button(action: onKeep) {
                        Text("Keep swiping")
                            .font(.nookiHeadline)
                            .foregroundStyle(Ink.text)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(Ink.surfaceRaised, in: .capsule)
                    }
                    .buttonStyle(.plain)

                    Button(action: onPlan) {
                        Text("Plan it")
                            .font(.nookiHeadline)
                            .foregroundStyle(Ink.heroInk)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(.honeyGradient))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 330)
            .background(Ink.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        }
    }
}

struct DatePlanCard: View {
    let plan: PlannedDate
    let idea: DateIdea?
    let viewer: String
    let profile: CoupleStore
    let moments: MomentStore
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onDone: () -> Void

    @State private var photo: UIImage?

    private var hidden: Bool { plan.surprise && plan.organizer != viewer && plan.rating == nil }
    private var upcoming: Bool { plan.rating == nil && plan.date > .now }
    private var moment: Moment? { plan.momentID.flatMap { id in moments.moments.first { $0.id == id } } }

    var body: some View {
        Group {
            if upcoming {
                content.contextMenu {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                }
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                UsIcon(glyph: hidden ? .init(symbol: "gift.fill", tint: .coral)
                                     : idea?.place.icon ?? .init(symbol: "heart.fill", tint: .blush), size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hidden ? "Surprise from \(plan.organizer)" : idea?.title ?? "Date")
                        .font(.nookiHeadline)
                        .foregroundStyle(Ink.text)
                    HStack(spacing: 4) {
                        Text(plan.date.formatted(.dateTime.weekday().day().month().hour().minute()))
                        if upcoming, plan.remind == true {
                            Image(systemName: "bell.fill")
                                .accessibilityLabel("Reminder on")
                        }
                    }
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
                }
                Spacer(minLength: 0)
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(.rect(cornerRadius: Radius.inner, style: .continuous))
                        .accessibilityHidden(true)
                } else {
                    Monogram(partner: plan.organizer, profile: profile, size: 26)
                }
            }
            .task(id: plan.momentID) {
                guard let moment else { return }
                photo = moments.cachedThumbnail(for: moment, maxPixels: 128)
                if photo == nil { photo = await moments.thumbnail(for: moment, maxPixels: 128) }
            }

            if hidden {
                if !plan.hint.isEmpty {
                    Text("Hint: \(plan.hint)")
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
            } else if !plan.place.isEmpty {
                Label(plan.place, systemImage: "mappin.and.ellipse")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }

            ratingRow
        }
        .padding(CardMetrics.padding)
        .cardSurface()
    }

    @ViewBuilder
    private var ratingRow: some View {
        if let rating = plan.rating {
            HStack(spacing: 4) {
                ForEach(1...3, id: \.self) { value in
                    Image(systemName: value <= rating ? "heart.fill" : "heart")
                        .font(.nookiHeadline)
                        .foregroundStyle(Color.blushPink.opacity(value <= rating ? 1 : 0.4))
                }
                Spacer(minLength: 0)
            }
        } else if plan.date < .now {
            Button(action: onDone) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("How was it? Mark it done")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.nookiCaption.weight(.bold))
                }
                .font(.nookiCallout.weight(.semibold))
                .foregroundStyle(Color.honey)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Color.honey.opacity(0.16), in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
}
