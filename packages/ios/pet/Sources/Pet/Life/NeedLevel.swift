import Foundation

/// How a need reads on screen: met, fine for now, or wanting something. A low need is an
/// invitation, never a warning.
public enum NeedLevel: Hashable, CaseIterable, Sendable {
  case content
  case okay
  case wants

  /// Met from here up; the room's spoken status draws the same line.
  public static let contentFrom = 0.7
  /// The brain's own line for a low need, so the screen and her behaviour agree.
  public static let wantsBelow = LifeConfig.standard.lowBelow

  public init(_ value: Double) {
    switch value {
    case Self.contentFrom...: self = .content
    case Self.wantsBelow..<Self.contentFrom: self = .okay
    default: self = .wants
    }
  }

  /// The one need raised, on the sheet and on her portrait on Home: the lowest, while it wants
  /// something. Only one, so the eye always lands on what comes first.
  public static func cue(_ needs: PetNeeds) -> PetNeed? {
    let (need, value) = needs.lowest
    return NeedLevel(value) == .wants ? need : nil
  }
}

extension PetNeed {
  /// The order the needs are shown in, on the sheet and round her portrait.
  public static let displayOrder: [PetNeed] = [.full, .rested, .playful, .loved]

  public func word(_ level: NeedLevel) -> String {
    switch (self, level) {
    case (.full, .content): "Well fed"
    case (.full, .okay): "Peckish"
    case (.full, .wants): "Hungry"
    case (.rested, .content): "Wide awake"
    case (.rested, .okay): "Drowsy"
    case (.rested, .wants): "Sleepy"
    case (.playful, .content): "Had fun"
    case (.playful, .okay): "Curious"
    case (.playful, .wants): "Wants to play"
    case (.loved, .content): "Adored"
    case (.loved, .okay): "Cuddly"
    case (.loved, .wants): "Wants a cuddle"
    }
  }

  /// What she asks for while this need is the one raised, short enough for the tag under her
  /// portrait.
  public var ask: String {
    switch self {
    case .full: "Hungry"
    case .rested: "Sleepy"
    case .playful: "Play?"
    case .loved: "Cuddle?"
    }
  }

  /// The word, then the number the screen draws as an arc.
  public func spoken(_ value: Double) -> String {
    "\(word(NeedLevel(value))), \(Self.percent(value)) percent"
  }

  /// A level as a whole percentage, 0 to 100, whatever the value.
  public static func percent(_ value: Double) -> Int {
    guard value.isFinite else { return 0 }
    return Int((min(max(value, 0), 1) * 100).rounded())
  }

  public func line(_ level: NeedLevel, name: String) -> String {
    switch (self, level) {
    case (.full, .content): "Happily full"
    case (.full, .okay): "Could nibble something"
    case (.full, .wants): "\(name) would love a meal"
    case (.rested, .content): "Well rested"
    case (.rested, .okay): "A little sleepy"
    case (.rested, .wants): "\(name) would love a cozy nap"
    case (.playful, .content): "Had a lovely play"
    case (.playful, .okay): "Up for a game"
    case (.playful, .wants): "\(name) would love to play"
    case (.loved, .content): "Feels so loved"
    case (.loved, .okay): "Glad you're here"
    case (.loved, .wants): "\(name) would love a cuddle"
    }
  }
}

extension PetNeeds {
  /// Her mood in a few words, from her lowest need.
  public func moodLine(name: String) -> String {
    let (need, value) = lowest
    let level = NeedLevel(value)
    return level == .content ? "Happy and cosy" : need.line(level, name: name)
  }
}
