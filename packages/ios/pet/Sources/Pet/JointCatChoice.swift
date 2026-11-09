import Foundation

/// One of the cats on the cushions when a pair chooses its cat together. The raw value is what
/// travels between the phones, so it stays stable.
public enum AdoptionCat: String, CaseIterable, Codable, Hashable, Sendable {
  case ginger
  case greyWhite
  case black
  case kitten
  case fluffy

  public var choice: CatChoice {
    switch self {
    case .ginger: CatChoice(model: .detailed, coat: .natural)
    case .greyWhite: CatChoice(model: .detailed, coat: .greyWhite)
    case .black: CatChoice(model: .detailed, coat: .black)
    case .kitten: CatChoice(model: .detailedKitten)
    case .fluffy: CatChoice(model: .detailedFluffy)
    }
  }

  public var title: String {
    switch self {
    case .ginger: "the ginger tabby"
    case .greyWhite: "the grey and white cat"
    case .black: "the black cat"
    case .kitten: "the kitten"
    case .fluffy: "the fluffy one"
    }
  }
}

/// What one phone tells the other while the pair chooses its cat.
public enum AdoptionMove: Hashable, Sendable {
  case pick(AdoptionCat?)
  /// A finger went down on the picked cat, or came up.
  case hold(Bool)
  /// Both rings filled: this cat is adopted.
  case adopt(AdoptionCat)
}

/// Choosing the cat together. When the picks match, each partner holds the cat until a ring
/// fills; once both rings have filled since the match, at once or in turn, the cat is adopted.
/// No timer. Both phones reach the same adoption, and an `adopt` from either side settles it.
public struct JointCatChoice: Equatable, Sendable {
  /// How long a finger stays down to fill a ring.
  public static let holdLength: TimeInterval = 1.2

  public private(set) var mine: AdoptionCat?
  public private(set) var theirs: AdoptionCat?
  public private(set) var adopted: AdoptionCat?
  public private(set) var partnerHere: Bool
  /// When each finger went down, while it is down.
  private var myHold: Date?
  private var theirHold: Date?
  /// Whether each has filled a ring since the picks last matched.
  public private(set) var iHeldOnce = false
  public private(set) var theyHeldOnce = false

  public init(partnerHere: Bool = true) {
    self.partnerHere = partnerHere
  }

  /// The cat both picked, until it is adopted.
  public var agreed: AdoptionCat? {
    guard adopted == nil, let mine, mine == theirs else { return nil }
    return mine
  }

  /// The two candidates while the picks differ.
  public var bid: (mine: AdoptionCat, theirs: AdoptionCat)? {
    guard adopted == nil, let mine, let theirs, mine != theirs else { return nil }
    return (mine, theirs)
  }

  public var isHolding: Bool { myHold != nil }
  public var partnerIsHolding: Bool { theirHold != nil }

  /// How full this phone's ring is at `now`, from 0 to 1.
  public func myRing(at now: Date) -> Double {
    Self.ring(since: myHold, done: iHeldOnce, at: now)
  }

  /// How full the partner's ring is at `now`, from 0 to 1.
  public func theirRing(at now: Date) -> Double {
    Self.ring(since: theirHold, done: theyHeldOnce, at: now)
  }

  // MARK: - This phone

  public mutating func pick(_ cat: AdoptionCat?) -> [AdoptionMove] {
    guard adopted == nil, cat != mine else { return [] }
    let wasHolding = myHold != nil
    mine = cat
    myHold = nil
    resetRings()
    return wasHolding ? [.hold(false), .pick(cat)] : [.pick(cat)]
  }

  /// A finger went down on the agreed cat, or came up. Down anywhere else does nothing.
  public mutating func hold(_ holding: Bool, at now: Date) -> [AdoptionMove] {
    guard adopted == nil else { return [] }
    if holding {
      guard agreed != nil, myHold == nil else { return [] }
      myHold = now
      return [.hold(true)] + settle(at: now)
    }
    guard let started = myHold else { return [] }
    if now.timeIntervalSince(started) >= Self.holdLength { iHeldOnce = true }
    myHold = nil
    return [.hold(false)] + settle(at: now)
  }

  /// Fills rings as time passes and adopts once both have filled. Call it every frame or so.
  public mutating func tick(at now: Date) -> [AdoptionMove] {
    settle(at: now)
  }

  // MARK: - The partner

  public mutating func received(_ move: AdoptionMove, at now: Date) -> [AdoptionMove] {
    switch move {
    case .pick(let cat):
      guard adopted == nil, cat != theirs else { return [] }
      theirs = cat
      theirHold = nil
      resetRings()
      return []
    case .hold(true):
      guard adopted == nil, agreed != nil, theirHold == nil else { return [] }
      theirHold = now
      return settle(at: now)
    case .hold(false):
      guard let started = theirHold else { return [] }
      if now.timeIntervalSince(started) >= Self.holdLength { theyHeldOnce = true }
      theirHold = nil
      return settle(at: now)
    case .adopt(let cat):
      guard adopted == nil else { return [] }
      adopt(cat)
      return []
    }
  }

  /// The partner came or went. Gone, their finger is up and their ring empties; their pick stays
  /// for when they are back.
  public mutating func partnerPresence(_ here: Bool) {
    partnerHere = here
    if !here { theirHold = nil }
  }

  // MARK: - Settling

  private mutating func settle(at now: Date) -> [AdoptionMove] {
    if let started = myHold, now.timeIntervalSince(started) >= Self.holdLength {
      iHeldOnce = true
    }
    if let started = theirHold, now.timeIntervalSince(started) >= Self.holdLength {
      theyHeldOnce = true
    }
    guard let cat = agreed, iHeldOnce, theyHeldOnce else { return [] }
    adopt(cat)
    return [.adopt(cat)]
  }

  private mutating func adopt(_ cat: AdoptionCat) {
    adopted = cat
    mine = cat
    theirs = cat
    myHold = nil
    theirHold = nil
  }

  private mutating func resetRings() {
    iHeldOnce = false
    theyHeldOnce = false
    if mine != theirs {
      myHold = nil
      theirHold = nil
    }
  }

  private static func ring(since start: Date?, done: Bool, at now: Date) -> Double {
    if done { return 1 }
    guard let start else { return 0 }
    return min(max(now.timeIntervalSince(start) / holdLength, 0), 1)
  }
}
