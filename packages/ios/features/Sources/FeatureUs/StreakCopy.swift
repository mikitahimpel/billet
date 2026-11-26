import Foundation
import ProfileInterface
import UsInterface

/// The words of the Us hero for one moment of the streak, apart from how the card draws them.
public nonisolated struct StreakCopy: Equatable, Sendable {
  /// Nil until paired.
  let daysTogether: Int?
  let status: LoveStreak.Status
  let turn: LoveStreak.Turn?
  /// The flame's number today.
  let days: Int
  /// The next badge's day; nil past the last one.
  let next: Int?
  let partner: String
  let cat: String

  public init(
    streak: LoveStreak, on date: Date, calendar: Calendar = .current, daysTogether: Int?,
    partner: String, cat: String
  ) {
    self.daysTogether = daysTogether
    status = streak.status(on: date, calendar: calendar)
    turn = streak.turn(on: date, calendar: calendar)
    let days = streak.current(on: date, calendar: calendar)
    self.days = days
    next = LoveStreak.milestones.first { $0 > days }
    self.partner = partner
    self.cat = cat
  }

  var isPaired: Bool { daysTogether != nil }

  /// What today needs. While unpaired the invitation says it, until a streak of one's own is going.
  var line: (lead: String, rest: String)? {
    guard isPaired || status != .cold else { return nil }
    switch turn {
    case .yours:
      return ("\(partner) did their part.", " Your turn: pet \(cat) or leave a note.")
    case .partners:
      return ("You did your part.", " The flame lights when \(partner) does theirs.")
    case nil: break
    }
    switch status {
    case .done:
      return ("Day \(days) is in.", next.map { " Badge at day \($0)." } ?? " See you tomorrow.")
    case .atRisk: return ("Keep it going.", " You both do one small thing today.")
    case .restorable: return ("You missed a day.", " You can bring the flame back once a month.")
    case .cold: return ("Light the flame", " together today.")
    }
  }

  /// The hero read out as one element.
  var spoken: String {
    let together =
      switch daysTogether {
      case nil: Couple.waitingLine
      case 1?: "1 day together"
      case let days?: "\(days) days together"
      }
    let streak = days == 1 ? "1-day streak" : "\(days)-day streak"
    let waiting =
      switch turn {
      case .yours: " \(partner) did their part, your turn."
      case .partners: " Waiting for \(partner)."
      case nil: ""
      }
    guard let next else { return "\(together). \(streak).\(waiting)" }
    let left = next - days
    return
      "\(together). \(streak), \(left) \(left == 1 ? "day" : "days") to the \(next)-day badge.\(waiting)"
  }
}
