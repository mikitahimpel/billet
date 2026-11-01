import Foundation

/// How the cat seems, worked out from the day's play and the hour. Never stored: the same
/// snapshot read at another hour can give another mood.
public enum CatMood: String, CaseIterable, Sendable {
  case sleepy
  case curious
  case happy
  case hungry
  case waiting
  case content

  /// Night runs from 22:00 to 06:00.
  static func isNight(hour: Int) -> Bool {
    hour >= 22 || hour < 6
  }

  public init(snapshot: WidgetSnapshot, now: Date, calendar: Calendar) {
    let current = snapshot.current(now: now, calendar: calendar)
    let hour = calendar.component(.hour, from: now)
    if Self.isNight(hour: hour) {
      self = .sleepy
    } else if current.partnerHere {
      self = .curious
    } else {
      switch current.treat {
      case .fed: self = .happy
      case .waitingOnMe: self = .hungry
      case .waitingOnPartner: self = .waiting
      case .neither: self = .content
      }
    }
  }

  public var title: String {
    switch self {
    case .sleepy: "Sleepy"
    case .curious: "Curious"
    case .happy: "Happy"
    case .hungry: "Hungry"
    case .waiting: "Waiting"
    case .content: "Content"
    }
  }

  public func line(name: String?) -> String {
    let cat = name ?? "The cat"
    switch self {
    case .sleepy: return "\(cat) is asleep."
    case .curious: return "\(cat) is watching the window."
    case .happy: return "\(cat) had a treat from you both."
    case .hungry: return "\(cat) is waiting for your treat."
    case .waiting: return "\(cat) is waiting for your partner's treat."
    case .content: return "\(cat) is doing nothing much."
    }
  }

  public var symbol: String {
    switch self {
    case .sleepy: "moon.zzz.fill"
    case .curious: "eye.fill"
    case .happy: "heart.fill"
    case .hungry: "fish.fill"
    case .waiting: "hourglass"
    case .content: "pawprint.fill"
    }
  }
}
