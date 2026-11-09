import Foundation

/// While `active`, the server refuses every write with a 503 carrying this block. `until` is a
/// hint for "back around …"; it does not end maintenance by itself.
public struct MaintenanceStatus: Codable, Hashable, Sendable {
  public let active: Bool
  public let message: StatusMessage?
  /// UTC as the server sent it, such as `2026-11-03T22:30:00Z`. See ``untilDate``.
  public let until: String?

  public init(active: Bool, message: StatusMessage? = nil, until: String? = nil) {
    self.active = active
    self.message = message
    self.until = until
  }

  public var untilDate: Date? { until.flatMap(Self.instant) }

  private enum CodingKeys: String, CodingKey {
    case active
    case message
    case until
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    active = try container.decode(Bool.self, forKey: .active)
    message = try container.decodeIfPresent(StatusMessage.self, forKey: .message)
    let until = try container.decodeIfPresent(String.self, forKey: .until)
    if let until, Self.instant(until) == nil {
      throw DecodingError.dataCorruptedError(
        forKey: .until, in: container,
        debugDescription: "until must be a UTC instant such as 2026-11-03T22:30:00Z")
    }
    self.until = until
  }

  /// Reads the contract's `StatusInstant`: `YYYY-MM-DDTHH:MM`, then optional seconds and up to
  /// three digits of fractions, then `Z`.
  public static func instant(_ text: String) -> Date? {
    let chars = Array(text)
    guard chars.last == "Z", chars.count >= 17 else { return nil }
    func number(_ range: Range<Int>) -> Int? {
      guard range.upperBound <= chars.count,
        chars[range].allSatisfy({ $0.isASCII && $0.isNumber })
      else { return nil }
      return Int(String(chars[range]))
    }
    guard chars[4] == "-", chars[7] == "-", chars[10] == "T", chars[13] == ":",
      let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
      let hour = number(11..<13), let minute = number(14..<16)
    else { return nil }
    // After the minutes: `Z`, `:SSZ`, or `:SS.f` to `:SS.fffZ`.
    let rest = chars[16..<(chars.count - 1)]
    var second = 0
    var millisecond = 0
    if !rest.isEmpty {
      guard rest.count >= 3, rest.first == ":", let seconds = number(17..<19) else { return nil }
      second = seconds
      let fraction = chars[19..<(chars.count - 1)]
      if !fraction.isEmpty {
        let digits = fraction.dropFirst()
        guard fraction.first == ".", (1...3).contains(digits.count),
          digits.allSatisfy({ $0.isASCII && $0.isNumber }),
          let value = Int(String(digits))
        else { return nil }
        millisecond = value * [100, 10, 1][digits.count - 1]
      }
    }
    guard (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour),
      (0...59).contains(minute), (0...59).contains(second)
    else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    guard let utc = TimeZone(identifier: "UTC") else { return nil }
    calendar.timeZone = utc
    let components = DateComponents(
      year: year, month: month, day: day, hour: hour, minute: minute, second: second,
      nanosecond: millisecond * 1_000_000)
    guard let date = calendar.date(from: components),
      calendar.component(.day, from: date) == day
    else { return nil }
    return date
  }
}
