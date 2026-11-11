import Foundation

/// What kind of cat this one is. Each trait runs from 0 to 1 around a middle of 0.5, drawn once
/// from the pet's seed when it is adopted, so two cats in the same room behave differently.
public struct CatPersonality: Codable, Hashable, Sendable {
  public enum Trait: String, CaseIterable, Codable, Hashable, Sendable {
    case curious
    case lazy
    case cuddly
    case playful
    case bold
    /// The app makes no sound: a vocal cat shows itself, perking up and seeking company.
    case vocal
  }

  public var curious: Double
  public var lazy: Double
  public var cuddly: Double
  public var playful: Double
  public var bold: Double
  public var vocal: Double

  public init(
    curious: Double = 0.5, lazy: Double = 0.5, cuddly: Double = 0.5, playful: Double = 0.5,
    bold: Double = 0.5, vocal: Double = 0.5
  ) {
    self.curious = curious
    self.lazy = lazy
    self.cuddly = cuddly
    self.playful = playful
    self.bold = bold
    self.vocal = vocal
  }

  public static let even = CatPersonality()

  /// The range a seeded trait lands in: never all one thing.
  public static let seededRange = 0.15...0.85

  /// The personality drawn from `seed`: the same on both phones for the same pet.
  public static func seeded(_ seed: UInt64) -> CatPersonality {
    var random = SplitMix64(seed: seed ^ 0x5045_5253_4F4E_414C)
    var traits = CatPersonality()
    for trait in Trait.allCases {
      traits[trait] = random.next(in: seededRange)
    }
    return traits
  }

  public subscript(trait: Trait) -> Double {
    get {
      switch trait {
      case .curious: curious
      case .lazy: lazy
      case .cuddly: cuddly
      case .playful: playful
      case .bold: bold
      case .vocal: vocal
      }
    }
    set {
      let value = min(max(newValue, 0), 1)
      switch trait {
      case .curious: curious = value
      case .lazy: lazy = value
      case .cuddly: cuddly = value
      case .playful: playful = value
      case .bold: bold = value
      case .vocal: vocal = value
      }
    }
  }

  /// `Π (1 + wᵢ·(2·tᵢ − 1))` over the weighted traits: 1 for an even cat, up to `1 + w` for a
  /// cat at the top of a trait and down to `1 − w` at the bottom.
  public func lean(_ weights: [(Trait, Double)]) -> Double {
    weights.reduce(1) { product, pair in
      product * max(0.05, 1 + pair.1 * (2 * self[pair.0] - 1))
    }
  }
}

/// A stable 64-bit hash of text, the same on every phone and every launch, unlike `Hasher`.
public enum StableHash {
  /// FNV-1a over the UTF-8 bytes.
  public static func of(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in text.utf8 {
      hash ^= UInt64(byte)
      hash &*= 0x0000_0100_0000_01B3
    }
    return hash
  }
}

extension CatPersonality.Trait {
  public var title: String {
    switch self {
    case .curious: "Curious"
    case .lazy: "Lazy"
    case .cuddly: "Cuddly"
    case .playful: "Playful"
    case .bold: "Bold"
    case .vocal: "Chatty"
    }
  }
}

extension CatPersonality {
  /// The traits furthest from an even cat's, strongest first: what sets this one apart. A trait
  /// below the middle is told by its opposite, so `high` says which way it leans.
  public func standouts(_ count: Int = 2) -> [(trait: Trait, high: Bool)] {
    let all = Trait.allCases.enumerated().sorted { a, b in
      let da = abs(self[a.element] - 0.5)
      let db = abs(self[b.element] - 0.5)
      return da != db ? da > db : a.offset < b.offset
    }
    return all.prefix(max(0, count)).map { ($0.element, self[$0.element] >= 0.5) }
  }
}
