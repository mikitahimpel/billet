import DesignSystem
import SwiftUI

/// Home's card for the porch light: how many nights to leave it on, or when it goes out.
public struct PorchLightSection: View {
  private let store: PorchLightStore

  public init(store: PorchLightStore) {
    self.store = store
  }

  public var body: some View {
    TimelineView(.everyMinute) { context in
      let calendar = Calendar.current
      VStack(alignment: .leading, spacing: Spacing.small) {
        if let light = store.light, light.isOn(at: context.date, calendar: calendar) {
          Text("The porch light is on")
            .billetType(.body)
            .foregroundStyle(Palette.paper.color)
          Text(
            "The streak waits until \(light.ends(calendar: calendar).formatted(.dateTime.weekday(.wide).day().month())). Nothing is lost."
          )
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
          BilletButton("Turn it off", rank: .secondary) { store.switchOff() }
        } else {
          Text("Going away?")
            .billetType(.body)
            .foregroundStyle(Palette.paper.color)
          Text("Leave the porch light on and the streak waits for you. Free, always.")
            .billetType(.label)
            .foregroundStyle(Palette.muted.color)
          HStack(spacing: Spacing.small) {
            ForEach(1...PorchLight.longest, id: \.self) { nights in
              BilletButton(nights == 1 ? "1 night" : "\(nights) nights", rank: .secondary) {
                store.leaveOn(nights: nights, now: context.date, calendar: calendar)
              }
            }
          }
        }
      }
      .padding(Spacing.medium)
      .frame(maxWidth: .infinity, alignment: .leading)
      .card()
      .accessibilityIdentifier("porchLight")
    }
  }
}
