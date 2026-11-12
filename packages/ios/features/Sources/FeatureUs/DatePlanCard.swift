#if canImport(UIKit)
  import MomentsInterface
  import WidgetInterface
  import WidgetUI
  import PhotosUI
  import ProfileInterface
  import SwiftUI
  import Design
  import UsInterface

  struct DateMatchOverlay: View {
    let idea: DateIdea
    var onPlan: () -> Void
    var onKeep: () -> Void

    var body: some View {
      ZStack {
        Color.black.opacity(0.6)
          .ignoresSafeArea()

        ScrollView {
          VStack(spacing: Space.m) {
            Text("It's a match!")
              .font(.ourioLargeTitle)
              .foregroundStyle(Ink.text)
            UsIcon(glyph: .init(symbol: "heart.fill", tint: .blush), size: 72)
            Text(idea.title)
              .font(.ourioTitle)
              .foregroundStyle(Ink.text)
              .multilineTextAlignment(.center)
            Label("+10", systemImage: "star.fill")
              .font(.ourioHeadline)
              .foregroundStyle(Ink.accentText)

            VStack(spacing: Space.s) {
              PrimaryButton("Plan it", action: onPlan)
              SecondaryButton("Keep swiping", action: onKeep)
            }
            .padding(.top, Space.s)
          }
          .padding(CardMetrics.padding)
          .frame(maxWidth: 330)
          .cardSurface()
          .padding(Space.gutter)
          .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ourioScrollEdges()
      }
      .accessibilityAddTraits(.isModal)
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
    private var moment: Moment? {
      plan.momentID.flatMap { id in moments.moments.first { $0.id == id } }
    }

    var body: some View {
      Group {
        if upcoming {
          content.contextMenu {
            Button {
              onEdit()
            } label: {
              Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
              onDelete()
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        } else {
          content
        }
      }
    }

    private var content: some View {
      VStack(alignment: .leading, spacing: Space.s) {
        HStack(spacing: Space.m) {
          UsIcon(
            glyph: hidden
              ? .init(symbol: "gift.fill", tint: .coral)
              : idea?.place.icon ?? .init(symbol: "heart.fill", tint: .blush), size: 42)
          VStack(alignment: .leading, spacing: 2) {
            Text(hidden ? "Surprise from \(plan.organizer)" : idea?.title ?? "Date")
              .font(.ourioHeadline)
              .foregroundStyle(Ink.text)
            HStack(spacing: Space.xs) {
              Text(plan.date.formatted(.dateTime.weekday().day().month().hour().minute()))
              if upcoming, plan.remind == true {
                Image(systemName: "bell.fill")
                  .accessibilityLabel("Reminder on")
              }
            }
            .font(.ourioCaption)
            .foregroundStyle(Ink.textSecondary)
          }
          Spacer(minLength: 0)
          if let photo {
            Image(uiImage: photo)
              .resizable()
              .scaledToFill()
              .frame(width: 42, height: 42)
              .corners(.inner)
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
              .font(.ourioCaption)
              .foregroundStyle(Ink.textSecondary)
          }
        } else if !plan.place.isEmpty {
          Label(plan.place, systemImage: "mappin.and.ellipse")
            .font(.ourioCaption)
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
        HStack(spacing: Space.xs) {
          ForEach(1...3, id: \.self) { value in
            Image(systemName: value <= rating ? "heart.fill" : "heart")
              .font(.ourioHeadline)
              .foregroundStyle(Color.blushPink.opacity(value <= rating ? 1 : 0.4))
          }
          Spacer(minLength: 0)
        }
      } else if plan.date < .now {
        SecondaryButton("How was it? Mark it done", action: onDone)
      }
    }
  }
#endif
