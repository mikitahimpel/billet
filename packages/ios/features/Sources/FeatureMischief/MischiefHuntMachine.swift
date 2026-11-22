import BilletKit
import Foundation
import MischiefInterface

/// The seeker looking for the toy mouse the partner hid. Looks cost nothing and nothing runs out: she can leave at any
/// time and the mouse waits.
public enum MischiefHuntMachine: Machine {
  /// Misses after which the cat stops being coy and walks to the mouse.
  public static let leadsAfter = 3

  public struct Hunt: Equatable, Sendable {
    public let hide: MischiefHide
    public let startedAt: Date
    /// The spots looked at without luck, in order, with how warm each was.
    public private(set) var looks: [Look]

    public struct Look: Equatable, Sendable {
      public let spot: MischiefSpot
      public let warmth: Warmth
    }

    public var misses: Int { looks.count }
    public var last: Look? { looks.last }

    public init(hide: MischiefHide, startedAt: Date) {
      self.hide = hide
      self.startedAt = startedAt
      looks = []
    }

    fileprivate mutating func miss(_ look: Look) { looks.append(look) }
  }

  public struct Found: Equatable, Sendable {
    public let hide: MischiefHide
    public let tries: Int
    public let seconds: Int
  }

  public enum State: Equatable, Sendable {
    case idle
    case hunting(Hunt)
    /// Shown until the seeker moves on.
    case found(Found)
  }

  public enum Event: Equatable, Sendable {
    case begin(MischiefHide, at: Date)
    /// A look at `spot`; `warmth` is how near it is to the hidden one, worked out by the caller from the room.
    case look(MischiefSpot, warmth: Warmth, at: Date)
    case leave
    case dismissed
    /// The mouse in this hunt is no longer open: found elsewhere, hidden again or turned up by the cat.
    case hideEnded(String)
  }

  public enum Output: Equatable, Sendable {
    case hint(MischiefHint)
    /// The find, for the journal.
    case report(Found)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.idle, .begin(let hide, let at)), (.found, .begin(let hide, let at)):
      return (.hunting(Hunt(hide: hide, startedAt: at)), [])

    case (.hunting(var hunt), .look(let spot, let warmth, let at)):
      guard !hunt.looks.contains(where: { $0.spot == spot }) else { return (state, []) }
      let target = hunt.hide.spot
      if spot == target {
        let seconds = min(max(Int(at.timeIntervalSince(hunt.startedAt)), 0), 86_400)
        let found = Found(hide: hunt.hide, tries: min(hunt.misses + 1, 99), seconds: seconds)
        return (.found(found), [.hint(.pounces(on: target)), .report(found)])
      }
      hunt.miss(.init(spot: spot, warmth: warmth))
      return (.hunting(hunt), [.hint(hint(after: hunt, warmth: warmth, target: target))])

    case (.hunting, .leave), (.found, .dismissed):
      return (.idle, [])

    case (.hunting(let hunt), .hideEnded(let id)) where hunt.hide.id == id:
      return (.idle, [])

    case (.idle, .look), (.found, .look),
      (.hunting, .begin), (.idle, .leave), (.found, .leave),
      (.idle, .dismissed), (.hunting, .dismissed),
      (.idle, .hideEnded), (.found, .hideEnded), (.hunting, .hideEnded):
      return (state, [])
    }
  }

  private static func hint(after hunt: Hunt, warmth: Warmth, target: MischiefSpot) -> MischiefHint {
    if hunt.misses >= leadsAfter { return .leads(to: target) }
    switch warmth {
    case .cold: return .away
    case .cool: return .curious
    case .warm: return .turns(toward: target)
    case .hot: return .sniffs(at: target)
    }
  }
}
