import Foundation

/// Something the keeper puts on the floor between her and the jar.
public struct RaidDefence: Equatable, Sendable, Identifiable, Codable {
  public enum Kind: Equatable, Sendable, Codable {
    /// Runs to and fro between its place and `to`; touching it, she rides it.
    case vacuum(to: RaidPoint)
    /// She cannot walk past it slowly.
    case box
    /// Hidden. She leaps back from it once.
    case cucumber
    /// Hidden. Stepped on at more than a creep, it puts the lamp on.
    case squeakyBoard
  }

  public let id: Int
  public var kind: Kind
  public var at: RaidPoint

  public init(id: Int, kind: Kind, at: RaidPoint) {
    self.id = id
    self.kind = kind
    self.at = at
  }

  /// The runner does not see it until it goes off or she sniffs it out.
  public var isHidden: Bool {
    switch kind {
    case .cucumber, .squeakyBoard: true
    case .vacuum, .box: false
    }
  }
}

/// What the keeper made: where the jar stands and what guards it.
public struct RaidLevel: Equatable, Sendable, Codable {
  public var jar: RaidPoint
  public var defences: [RaidDefence]

  public init(jar: RaidPoint, defences: [RaidDefence] = []) {
    self.jar = jar
    self.defences = defences
  }

  public enum Problem: Equatable, Sendable {
    case jarTooNearStart
    case tooManyDefences
    case defenceNearStart(Int)
    case defenceOnFurniture(Int)
  }

  /// Why the level cannot be played, or nil. A level that passes can always be won: no defence holds her for
  /// good, and none can stand where she starts.
  public func problem(on board: RaidBoard) -> Problem? {
    if jar.distance(to: board.start) < RaidRules.jarFromStart { return .jarTooNearStart }
    if defences.count > RaidRules.maxDefences { return .tooManyDefences }
    for defence in defences {
      var places = [defence.at]
      if case .vacuum(let to) = defence.kind { places.append(to) }
      for place in places {
        if place.distance(to: board.start) < RaidRules.startClear {
          return .defenceNearStart(defence.id)
        }
        if board.top(at: place) != nil { return .defenceOnFurniture(defence.id) }
      }
    }
    return nil
  }
}

/// What the runner's thumb did in one tick.
public struct RaidInput: Equatable, Sendable, Codable {
  /// Where the finger is on the floor; nil with the finger up.
  public var steer: RaidPoint?
  public var jump: Bool
  public var sniff: Bool

  public init(steer: RaidPoint? = nil, jump: Bool = false, sniff: Bool = false) {
    self.steer = steer
    self.jump = jump
    self.sniff = sniff
  }

  public static let idle = RaidInput()
}

public enum RaidOutcome: Equatable, Sendable, Codable {
  /// She tipped the jar over, this many seconds in.
  case got(seconds: Double)
  /// Time ran out; the nearest she came, in metres.
  case kept(closest: Double)
}
