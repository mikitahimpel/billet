import FeatureInbox
import Foundation

/// A note from a year or a month ago, dug out by the cat.
public struct OnThisDay: Equatable, Sendable {
  public enum Span: Equatable, Sendable {
    case year
    case month

    public var words: String {
      switch self {
      case .year: "a year ago"
      case .month: "a month ago"
      }
    }
  }

  public let note: NoteRecord
  public let span: Span

  /// A note from the same calendar day a year ago, else the same day a month ago. When there are
  /// several, the one nearest the middle of that day. Nothing before there has been history.
  public static func pick(from notes: [NoteRecord], now: Date, calendar: Calendar) -> OnThisDay? {
    for (span, component) in [(Span.year, Calendar.Component.year), (.month, .month)] {
      guard let target = calendar.date(byAdding: component, value: -1, to: now) else { continue }
      let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: target) ?? target
      let sameDay = notes.filter { calendar.isDate($0.date, inSameDayAs: target) }
      if let best = sameDay.min(by: {
        abs($0.date.timeIntervalSince(noon)) < abs($1.date.timeIntervalSince(noon))
      }) {
        return OnThisDay(note: best, span: span)
      }
    }
    return nil
  }
}
