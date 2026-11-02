import Foundation

/// How one widget button reads right now: its words, and whether pressing it can do anything.
public struct ActionButtonState: Equatable, Sendable {
  public var title: String
  public var symbol: String
  public var isEnabled: Bool

  public static func make(
    _ kind: WidgetActionKind, snapshot: WidgetSnapshot?, pending: [WidgetAction], now: Date,
    calendar: Calendar
  ) -> ActionButtonState {
    let current = snapshot?.current(now: now, calendar: calendar)
    let waiting = pending.contains { $0.kind == kind }
    switch kind {
    case .treat:
      if waiting { return .init(title: "Queued", symbol: "clock.fill", isEnabled: false) }
      switch current?.treat {
      case .waitingOnPartner, .fed:
        return .init(title: "Given", symbol: "checkmark.circle.fill", isEnabled: false)
      case .neither, .waitingOnMe, nil:
        return .init(title: "Treat", symbol: "fish.fill", isEnabled: true)
      }
    case .pet:
      if waiting { return .init(title: "Queued", symbol: "clock.fill", isEnabled: true) }
      return .init(title: "Pet", symbol: "pawprint.fill", isEnabled: true)
    case .heart:
      if waiting { return .init(title: "Queued", symbol: "clock.fill", isEnabled: false) }
      return .init(
        title: "Heart", symbol: "heart.fill", isEnabled: current?.latestReceivedNote != nil)
    case .openCanvas:
      return .init(title: "Draw", symbol: "pencil.tip", isEnabled: true)
    }
  }

  /// The buttons to show, in order: those whose flags are on at `surface`.
  public static func kinds(features: WidgetFeatures, surface: ActionSurface) -> [WidgetActionKind] {
    [WidgetActionKind.treat, .pet, .heart].filter {
      WidgetActionRequest.required($0, at: surface).allSatisfy(features.isOn)
    }
  }
}
