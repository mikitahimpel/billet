import BilletKit
import Foundation
import MischiefInterface

/// The hider choosing where the toy mouse goes and the few words that go with it.
public enum MischiefHideMachine: Machine {
  public struct Draft: Equatable, Sendable {
    public var spot: MischiefSpot?
    public var line: String

    public init(spot: MischiefSpot? = nil, line: String = "") {
      self.spot = spot
      self.line = line
    }

    public var canHide: Bool { spot != nil }
  }

  public enum State: Equatable, Sendable {
    case closed
    case choosing(Draft)
  }

  public enum Event: Equatable, Sendable {
    case opened
    case picked(MischiefSpot)
    case wrote(String)
    case submitted
    case cancelled
  }

  public enum Output: Equatable, Sendable {
    /// The partner's phone hears it through the journal.
    case hide(spot: MischiefSpot, line: String?)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.closed, .opened):
      return (.choosing(Draft()), [])

    case (.choosing(var draft), .picked(let spot)):
      draft.spot = spot
      return (.choosing(draft), [])

    case (.choosing(var draft), .wrote(let text)):
      draft.line = MischiefLine.clip(text)
      return (.choosing(draft), [])

    case (.choosing(let draft), .submitted):
      guard let spot = draft.spot else { return (state, []) }
      return (.closed, [.hide(spot: spot, line: MischiefLine.clean(draft.line))])

    case (.choosing, .cancelled):
      return (.closed, [])

    case (.closed, .picked), (.closed, .wrote), (.closed, .submitted), (.closed, .cancelled),
      (.choosing, .opened):
      return (state, [])
    }
  }
}
