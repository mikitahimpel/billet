import BilletKit

/// When the cat notices the partner: once each time they arrive, while the room is on screen. An
/// arrival under a cover waits until the room shows again.
public enum PartnerNoticeMachine: Machine {
  public enum State: Equatable, Sendable {
    case away
    case unnoticed
    case noticed
  }

  public enum Event: Equatable, Sendable {
    case input(partnerHere: Bool, visible: Bool)
  }

  public enum Output: Equatable, Sendable {
    case notice
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.away, .input(false, _)), (.unnoticed, .input(false, _)), (.noticed, .input(false, _)):
      return (.away, [])
    case (.away, .input(true, true)), (.unnoticed, .input(true, true)):
      return (.noticed, [.notice])
    case (.away, .input(true, false)), (.unnoticed, .input(true, false)):
      return (.unnoticed, [])
    case (.noticed, .input(true, _)):
      return (.noticed, [])
    }
  }
}
