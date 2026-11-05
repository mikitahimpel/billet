import Foundation

/// One small thing to draw each day. Both phones read the same day and the same list, so they
/// show the same word with nothing sent between them.
public enum TodaysWord {
  /// A step coprime to the list length, so every word comes up once before any comes up twice and
  /// neighbouring days are not neighbours in the list.
  private static let stride = 37

  public static var count: Int { TodaysWordList.all.count }

  /// The word for a day written `yyyy-MM-dd`, as ``Pet/TreatDay`` writes them, or nil for text
  /// that is not a day.
  public static func word(onDay day: String) -> String? {
    guard let number = dayNumber(day) else { return nil }
    let all = TodaysWordList.all
    return all[((number * stride) % all.count + all.count) % all.count]
  }

  /// Whether the card shows: the word is there, it was not put away today, and no note has been
  /// sent today.
  public static func isShown(onDay day: String, dismissedDay: String?, sentToday: Bool) -> Bool {
    word(onDay: day) != nil && dismissedDay != day && !sentToday
  }

  /// Days counted from 1 January 2000 by the calendar date alone, so the time zone never moves a
  /// word to another day.
  static func dayNumber(_ day: String) -> Int? {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
      return nil
    }
    let (year, month, day) = (parts[0], parts[1], parts[2])
    let shifted = month <= 2 ? year - 1 : year
    let era = shifted / 400
    let yearOfEra = shifted - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468 - 10_957
  }
}
