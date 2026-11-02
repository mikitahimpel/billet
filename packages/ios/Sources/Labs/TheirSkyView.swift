import DesignSystem
import SwiftUI

/// The sky where the partner is, and what time it is for them.
public struct TheirSkySection: View {
  private let store: LampStore

  public init(store: LampStore) {
    self.store = store
  }

  public var body: some View {
    TimelineView(.everyMinute) { context in
      if let zoneID = store.theirs?.timeZoneID, let zone = TimeZone(identifier: zoneID),
        let sky = TheirSky.over(timeZoneID: zoneID, at: context.date)
      {
        let colours = sky.colours
        HStack(spacing: Spacing.medium) {
          RoundedRectangle(cornerRadius: Radius.plate)
            .fill(
              LinearGradient(
                colors: [colours.top.color, colours.bottom.color], startPoint: .top,
                endPoint: .bottom)
            )
            .frame(width: 52, height: 52)
            .overlay {
              RoundedRectangle(cornerRadius: Radius.plate).strokeBorder(
                Palette.lightWarm.color.opacity(Glow.edgeOpacity))
            }
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 0) {
            Text("\(sky.title) where they are")
              .billetType(.body)
              .foregroundStyle(Palette.paper.color)
            Text("\(Self.time(context.date, in: zone)) for them")
              .billetType(.label)
              .foregroundStyle(Palette.muted.color)
          }
          Spacer(minLength: 0)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("theirSky")
      }
    }
    .calmAnimation(value: store.theirs?.timeZoneID)
  }

  static func time(_ date: Date, in zone: TimeZone) -> String {
    var style = Date.FormatStyle(date: .omitted, time: .shortened)
    style.timeZone = zone
    return style.format(date)
  }
}
