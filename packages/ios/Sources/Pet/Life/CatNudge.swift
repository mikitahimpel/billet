import Foundation

/// When to nudge the pair about the cat, and in what words: the first time in the next day that
/// the cat would be hangry or lonely if nobody does anything, outside quiet hours, and no more than
/// twice a day. Worked out from the events alone, so care from either partner moves or cancels it
/// on both phones as soon as the event arrives.
public enum CatNudge {
  public struct Plan: Hashable, Sendable {
    public var at: Date
    public var feeling: CatFeeling
    public var body: String
  }

  /// Local hours with no nudges: from ten at night to half past eight in the morning.
  public static let quietFrom = 22.0
  public static let quietUntil = 8.5
  public static let perDay = 2
  /// The least time between two nudges, in seconds.
  public static let apart = 4.0 * 3600
  /// How far ahead it looks, and how finely.
  public static let lookAhead = 24.0 * 3600
  public static let step = 900.0

  /// The feelings worth a nudge.
  public static let worth: Set<CatFeeling> = [.hangry, .lonely]

  /// The next nudge after `now`, or nil if the cat is fine for the day ahead. `sent` are the
  /// nudges that already went off.
  public static func next(
    events: [LifeEvent], now: Date, context: LifeContext, config: LifeConfig = .standard,
    temperament: CatTemperament?, name: String, sent: [Date]
  ) -> Plan? {
    var t = now.timeIntervalSince1970 + step
    let end = now.timeIntervalSince1970 + lookAhead
    let utcOffset = context.utcOffset
    while t <= end {
      defer { t += step }
      let at = Date(timeIntervalSince1970: t)
      guard !isQuiet(t, utcOffset: utcOffset),
        !sent.contains(where: { abs($0.timeIntervalSince1970 - t) < apart }),
        sent.filter({ day($0.timeIntervalSince1970, utcOffset) == day(t, utcOffset) }).count
          < perDay
      else { continue }
      let state = PetLife.state(events: events, now: at, context: context, config: config)
      let feeling = CatFeeling.of(
        needs: state.needs, mood: state.mood, asleep: state.asleep, sleepy: false,
        temperament: temperament, config: config)
      guard worth.contains(feeling) else { continue }
      return Plan(at: at, feeling: feeling, body: body(feeling, name: name))
    }
    return nil
  }

  /// Whether `t` falls in the quiet hours, in local time.
  public static func isQuiet(_ t: Double, utcOffset: Int) -> Bool {
    let hour = localHour(t, utcOffset)
    return hour >= quietFrom || hour < quietUntil
  }

  /// What the nudge says, in the cat's character. Either of you can fix it.
  public static func body(_ feeling: CatFeeling, name: String) -> String {
    switch feeling {
    case .hangry: "\(name) is knocking things off the seat. Someone's hungry 🐟"
    case .hungry: "\(name) is sitting by the empty bowl, staring at you 🐟"
    case .lonely: "\(name) is sulking with its back to the room. A pet would fix it 💛"
    case .bored: "\(name) is doing laps of the window seat. Time for a game? 🧶"
    case .asleep, .sleepy, .happy, .content: "\(name) is thinking of you 💛"
    }
  }

  private static func localHour(_ t: Double, _ utcOffset: Int) -> Double {
    var hour = (t + Double(utcOffset)).truncatingRemainder(dividingBy: 86400) / 3600
    if hour < 0 { hour += 24 }
    return hour
  }

  private static func day(_ t: Double, _ utcOffset: Int) -> Int {
    Int(((t + Double(utcOffset)) / 86400).rounded(.down))
  }
}
