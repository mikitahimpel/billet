import Foundation

/// One of the pet's four needs. Nothing here is about cats: any species can have them.
public enum PetNeed: String, CaseIterable, Codable, Hashable, Sendable {
  /// Fed: a treat or a meal fills it.
  case full
  /// Slept: it fills while asleep, mostly at night.
  case rested
  /// Cared for: petting by each partner, and notes most of all.
  case loved
  case playful

  public var title: String {
    switch self {
    case .full: "Full"
    case .rested: "Rested"
    case .loved: "Loved"
    case .playful: "Playful"
    }
  }
}

/// The four needs, each from the config's floor up to 1. Mood is worked out from them and never
/// stored.
public struct PetNeeds: Codable, Hashable, Sendable {
  public var full: Double
  public var rested: Double
  public var loved: Double
  public var playful: Double

  public init(full: Double, rested: Double, loved: Double, playful: Double) {
    self.full = full
    self.rested = rested
    self.loved = loved
    self.playful = playful
  }

  public init(all value: Double) {
    self.init(full: value, rested: value, loved: value, playful: value)
  }

  public subscript(need: PetNeed) -> Double {
    get {
      switch need {
      case .full: full
      case .rested: rested
      case .loved: loved
      case .playful: playful
      }
    }
    set {
      switch need {
      case .full: full = newValue
      case .rested: rested = newValue
      case .loved: loved = newValue
      case .playful: playful = newValue
      }
    }
  }

  /// The weighted geometric mean `Π nᵢ^wᵢ`, so the lowest need pulls mood down hardest.
  public func mood(weights: PetNeeds) -> Double {
    let total = PetNeed.allCases.reduce(0) { $0 + weights[$1] }
    guard total > 0 else { return 0 }
    let log = PetNeed.allCases.reduce(0) { $0 + weights[$1] * Foundation.log(max(self[$1], 1e-6)) }
    return exp(log / total)
  }

  public var lowest: (need: PetNeed, value: Double) {
    PetNeed.allCases.map { ($0, self[$0]) }.min { $0.1 < $1.1 } ?? (.full, full)
  }
}
