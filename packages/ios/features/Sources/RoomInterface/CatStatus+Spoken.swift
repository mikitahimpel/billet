import Pet

extension CatStatus {
  /// What VoiceOver says of her: what she is doing and, when a need is not met, what she would like.
  public var spoken: String {
    guard let needs, let wish = Self.wish(needs.lowest) else { return doing }
    return "\(doing), \(wish)"
  }

  /// What she is doing, in a word or two.
  public var doing: String { mind.map(Self.doing) ?? "Settling in" }

  private static func doing(_ mind: CatMind) -> String {
    switch mind {
    case .idle: "Sitting quietly"
    case .exploring: "Exploring the room"
    case .playing: "Playing"
    case .grooming: "Grooming"
    case .eating: "Eating"
    case .seekingAttention: "Asking for attention"
    case .loaf: "Curled up in a loaf"
    case .napping: "Napping"
    case .deepSleep: "Fast asleep"
    case .beingPetted: "Enjoying a pet"
    case .greetingPartner: "Greeting her person"
    case .sulking: "Sulking a little"
    }
  }

  /// Nil from 0.7 up, where the cat sheet calls a need met.
  private static func wish(_ lowest: (need: PetNeed, value: Double)) -> String? {
    guard lowest.value < 0.7 else { return nil }
    let low = lowest.value < 0.35
    switch lowest.need {
    case .full: return low ? "hungry" : "a little hungry"
    case .rested: return low ? "tired" : "a little sleepy"
    case .loved: return low ? "missing a cuddle" : "would like a cuddle"
    case .playful: return low ? "bored" : "would like to play"
    }
  }
}
