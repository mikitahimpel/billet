import Foundation
import Pet

/// How the cat seems, worked out from the day's play and the hour. Never stored: the same
/// snapshot read at another hour can give another mood.
public enum CatMood: String, CaseIterable, Sendable {
  case sleepy
  case curious
  case happy
  case hungry
  case waiting
  case content
  /// Its life: it wants to play.
  case playful
  /// Its life: it misses being cared for, and waits by the door.
  case lonely

  /// Night runs from 22:00 to 06:00.
  static func isNight(hour: Int) -> Bool {
    hour >= 22 || hour < 6
  }

  public init(snapshot: WidgetSnapshot, now: Date, calendar: Calendar) {
    if let life = snapshot.life {
      self.init(life: life.state(at: now), config: life.config)
      return
    }
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

  /// The mood from the cat's needs: asleep is sleepy, a low need shows as itself, and a cat
  /// whose needs are well met is happy.
  public init(life: LifeState, config: LifeConfig) {
    let lowest = life.needs.lowest
    if life.asleep {
      self = .sleepy
    } else if lowest.value < config.lowBelow {
      switch lowest.need {
      case .full: self = .hungry
      case .rested: self = .sleepy
      case .loved: self = .lonely
      case .playful: self = .playful
      }
    } else if life.mood >= Self.happyMood {
      self = .happy
    } else {
      self = .content
    }
  }

  /// Mood from this up reads as happy.
  static let happyMood = 0.62

  public var title: String {
    switch self {
    case .sleepy: "Sleepy"
    case .curious: "Curious"
    case .happy: "Happy"
    case .hungry: "Hungry"
    case .waiting: "Waiting"
    case .content: "Content"
    case .playful: "Playful"
    case .lonely: "Missing you"
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
    case .playful: return "\(cat) wants to play."
    case .lonely: return "\(cat) is waiting by the door."
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
    case .playful: "tennisball.fill"
    case .lonely: "heart.fill"
    }
  }
}
