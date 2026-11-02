import DesignSystem
import SwiftUI

/// A small suitcase by the door: a handle, a body, and a row of compartments that fill up as the
/// day of the visit comes closer.
struct SuitcaseView: View {
  let packed: Int

  var body: some View {
    VStack(spacing: 0) {
      RoundedRectangle(cornerRadius: 4)
        .stroke(Palette.woodShade.color, lineWidth: 3)
        .frame(width: 20, height: 9)
      ZStack {
        RoundedRectangle(cornerRadius: 7).fill(Palette.wood.color)
        RoundedRectangle(cornerRadius: 7).stroke(Palette.woodLit.color, lineWidth: 1.5)
        HStack(spacing: 3) {
          ForEach(0..<NextVisit.compartments, id: \.self) { index in
            RoundedRectangle(cornerRadius: 2)
              .fill(index < packed ? Palette.light.color : Palette.woodDeep.color)
              .frame(width: 5, height: 22)
          }
        }
      }
      .frame(width: 52, height: 38)
    }
    .accessibilityHidden(true)
  }
}

/// Home's card for the next visit: pick the day you meet next, then watch the suitcase fill.
public struct NextVisitSection: View {
  private let store: NextVisitStore

  @State private var picked = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
  @State private var changing = false

  public init(store: NextVisitStore) {
    self.store = store
  }

  public var body: some View {
    TimelineView(.everyMinute) { context in
      let calendar = Calendar.current
      VStack(alignment: .leading, spacing: Spacing.small) {
        if let visit = store.visit, visit.isShown(now: context.date, calendar: calendar), !changing
        {
          let left = visit.daysLeft(now: context.date, calendar: calendar)
          HStack(spacing: Spacing.medium) {
            SuitcaseView(packed: visit.packed(now: context.date, calendar: calendar))
            VStack(alignment: .leading, spacing: 0) {
              Text(Self.words(daysLeft: left))
                .billetType(.heading)
                .foregroundStyle(Palette.paper.color)
              Text(visit.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .billetType(.label)
                .foregroundStyle(Palette.muted.color)
            }
            Spacer(minLength: 0)
            Button("Change") { changing = true }
              .billetType(.label)
              .foregroundStyle(Palette.gold.color)
              .frame(minWidth: Target.minimum, minHeight: Target.minimum)
          }
        } else {
          Text("Next visit")
            .billetType(.body)
            .foregroundStyle(Palette.paper.color)
          Text("Pick the day you meet next. A suitcase by the door fills up as it nears.")
            .billetType(.label)
            .foregroundStyle(Palette.muted.color)
          DatePicker(
            "Day", selection: $picked,
            in: (calendar.date(byAdding: .day, value: 1, to: context.date) ?? context.date)...,
            displayedComponents: .date
          )
          .labelsHidden()
          .tint(Palette.gold.color)
          .colorScheme(.dark)
          BilletButton("Set the day", rank: .secondary) {
            store.set(day: picked, now: context.date, calendar: calendar)
            changing = false
          }
        }
      }
      .padding(Spacing.medium)
      .frame(maxWidth: .infinity, alignment: .leading)
      .card()
      .accessibilityIdentifier("nextVisit")
    }
    .calmAnimation(value: changing)
  }

  static func words(daysLeft: Int) -> String {
    switch daysLeft {
    case 0: "Today"
    case 1: "Tomorrow"
    default: "\(daysLeft) days"
    }
  }
}
