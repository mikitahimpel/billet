import Foundation

/// How Mochi is, in one word, from what the couple did and what she needs. She is never sad, whatever the couple does
/// or doesn't do: a low need is a request in her own voice.
public nonisolated enum MochiPose: Equatable, Sendable {
  case purring, asleep, hungry, drowsy, cuddly, playful, waiting, chirpy, napping, quiet, idle

  /// What the widget's one care button does for her.
  public enum Care: Equatable, Sendable {
    case feed, pet
  }

  public static func pose(
    isPurring: Bool, isNight: Bool, freshDrawing: Bool, partnerMood: PartnerMood?,
    want: CatNeedsGlance.Want?
  ) -> MochiPose {
    if isPurring { return .purring }
    if isNight { return .asleep }
    switch want {
    case .food: return .hungry
    case .rest: return .drowsy
    case .love: return .cuddly
    case .play: return .playful
    case nil: break
    }
    if freshDrawing { return .waiting }
    switch partnerMood {
    case .sleepy: return .napping
    case .happy: return .chirpy
    case .busy: return .quiet
    case .missing: return .waiting
    case nil: return .idle
    }
  }

  public var word: String {
    switch self {
    case .purring: "Purring"
    case .asleep: "Asleep"
    case .hungry: "Hungry"
    case .drowsy: "Sleepy"
    case .cuddly: "Wants cuddles"
    case .playful: "Feeling playful"
    case .waiting: "Waiting"
    case .chirpy: "Chirpy"
    case .napping: "Napping"
    case .quiet: "Keeping quiet"
    case .idle: "Sitting pretty"
    }
  }

  /// The line under the word, about the couple.
  public func line(partner: String, freshDrawing: Bool) -> String {
    switch self {
    case .purring: "Love received"
    case .asleep: "Lamps are on"
    case .hungry: "Dinner is late"
    case .drowsy: "Needs a quiet minute"
    case .cuddly: "Could use a pet"
    case .playful: "Bored of the rug"
    case .waiting: freshDrawing ? "\(partner) drew you something" : "\(partner) is missing you"
    case .chirpy: "\(partner) is happy"
    case .napping: "\(partner) is sleepy"
    case .quiet: "\(partner) is busy"
    case .idle: "Say hi"
    }
  }

  /// What she says in the bubble beside her: short, in her voice.
  public func speech(partner: String, freshDrawing: Bool) -> String {
    switch self {
    case .purring: "Prrrr…"
    case .asleep: "Zzz…"
    case .hungry: "Mrrp? Dinner?"
    case .drowsy: "*yawn*"
    case .cuddly: "Pet me?"
    case .playful: "Play with me!"
    case .waiting: freshDrawing ? "\(partner) sent art!" : "Where's \(partner)?"
    case .chirpy: "Mew mew!"
    case .napping: "Shh, nap time"
    case .quiet: "Psst, \(partner) is busy"
    case .idle: "Hi!"
    }
  }

  public var care: Care { self == .hungry ? .feed : .pet }
}
