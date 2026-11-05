import DesignSystem
import Foundation
import SwiftUI

/// The calm screen shown while billet is down for maintenance: the cat asleep in its room, the
/// service's message, and when it should be back. It is a pause, not an error.
struct MaintenanceView: View {
  let message: String
  let until: Date?
  let room: AnyView?
  let onRead: () -> Void

  @Environment(\.locale) private var locale

  var body: some View {
    ZStack(alignment: .bottom) {
      EveningBackground()
      if let room {
        room
          .ignoresSafeArea()
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      } else {
        Image(systemName: "moon.zzz.fill")
          .font(.system(size: 64, weight: .medium))
          .foregroundStyle(Palette.light.color)
          .lampGlow()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityHidden(true)
      }
      card
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, Spacing.large)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("maintenance")
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text(message)
        .billetType(.heading)
        .foregroundStyle(Palette.paper.color)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      TimelineView(.everyMinute) { context in
        if let line = ServiceStatusCopy.backAround(
          until, now: context.date, timeZone: .autoupdatingCurrent, locale: locale)
        {
          Text(line)
            .billetType(.label)
            .foregroundStyle(Palette.gold.color)
        }
      }
      Text("Your notes are safe here, and anything you send waits until billet is back.")
        .billetType(.body)
        .foregroundStyle(Palette.muted.color)
        .fixedSize(horizontal: false, vertical: true)
      BilletButton("Read your notes", rank: .secondary, systemImage: "note.text", action: onRead)
        .padding(.top, Spacing.small)
        .accessibilityIdentifier("maintenanceReadNotes")
    }
    .padding(Spacing.large)
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }
}

/// The maintenance screen folded into a pill while the user reads the app underneath, with the
/// way back to it.
struct MaintenanceReadingBar: View {
  let message: String
  let onBack: () -> Void

  var body: some View {
    HStack(spacing: Spacing.small) {
      Circle()
        .fill(Palette.woodLit.color)
        .frame(width: Spacing.small, height: Spacing.small)
        .accessibilityHidden(true)
      Text(message)
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
        .lineLimit(2)
      Button("Back", action: onBack)
        .billetType(.label)
        .foregroundStyle(Palette.gold.color)
        .frame(minWidth: Target.minimum, minHeight: Target.minimum)
        .accessibilityHint("Shows the maintenance screen again")
    }
    .padding(.leading, Spacing.medium)
    .padding(.trailing, Spacing.small)
    .frame(minHeight: Target.minimum)
    .floatingGlass()
    .padding(.top, Spacing.small)
    .padding(.horizontal, Spacing.medium)
    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("maintenanceReading")
  }
}
