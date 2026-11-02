import DesignSystem
import SwiftUI

/// The couple's streak in days. Shows nothing until the backend reports one.
public struct StreakBadge: View {
  private let days: Int?

  public init(days: Int?) {
    self.days = days
  }

  public var body: some View {
    if let days {
      Label {
        Text(Self.text(days: days))
          .billetType(.body)
          .foregroundStyle(Palette.paper.color)
      } icon: {
        Image(systemName: "flame")
          .foregroundStyle(Palette.gold.color)
      }
      .accessibilityIdentifier("streak")
    }
  }

  static func text(days: Int) -> String {
    days == 1 ? "1 day in a row" : "\(days) days in a row"
  }
}
