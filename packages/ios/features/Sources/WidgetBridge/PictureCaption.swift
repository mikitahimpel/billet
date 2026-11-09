import Foundation

/// The words and symbol for one picture, so every widget family says the same thing.
public struct PictureCaption: Equatable, Sendable {
  public var headline: String
  public var detail: String
  public var symbol: String
  /// The figure the picture is about, for the families that have room for only that.
  public var number: Int?

  public init(headline: String, detail: String, symbol: String, number: Int? = nil) {
    self.headline = headline
    self.detail = detail
    self.symbol = symbol
    self.number = number
  }

  public static func make(
    _ mode: PictureMode, snapshot: WidgetSnapshot?, now: Date, calendar: Calendar
  ) -> PictureCaption {
    let current = snapshot?.current(now: now, calendar: calendar)
    switch mode {
    case .nudge:
      let days = current?.daysSinceLastSent(now: now, calendar: calendar)
      let detail =
        days.map { "It has been \($0) days since your last note." } ?? "You have not drawn one yet."
      return PictureCaption(headline: "Draw something", detail: detail, symbol: "pencil.tip")

    case .partnerDrawing:
      return PictureCaption(
        headline: "New note", detail: "Your partner's latest drawing.", symbol: "scribble")

    case .partnerWindow:
      if current?.partnerHere == true {
        return PictureCaption(
          headline: "They're here", detail: "The window is lit: your partner is in Ourio.",
          symbol: "lightbulb.fill")
      }
      return PictureCaption(
        headline: "Window's dark", detail: "Your partner is away.", symbol: "moon.fill")

    case .streak:
      let days = current?.streak ?? 0
      return PictureCaption(
        headline: "\(days) in a row", detail: "Days you both gave a treat.", symbol: "flame.fill",
        number: days)

    case .daysTogether:
      let days = current?.daysTogether(now: now, calendar: calendar) ?? 0
      return PictureCaption(
        headline: "\(days) days", detail: "Together on Ourio.", symbol: "heart.fill",
        number: days)

    case .timeOfDay:
      let phase = DayPhase(hour: calendar.component(.hour, from: now))
      return PictureCaption(
        headline: phase.title, detail: "The house this \(phase.title.lowercased()).",
        symbol: phase.symbol)
    }
  }
}

extension DayPhase {
  public var symbol: String {
    switch self {
    case .dawn: "sunrise.fill"
    case .day: "sun.max.fill"
    case .dusk: "sunset.fill"
    case .night: "moon.stars.fill"
    }
  }
}
