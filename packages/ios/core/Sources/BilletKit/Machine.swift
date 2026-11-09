/// `transition` performs no work; outputs describe work for a ``Store``. Switch over
/// `(state, event)` exhaustively, with no `default` or wildcard, so a new case fails to compile.
public protocol Machine {
  associatedtype State: Sendable
  associatedtype Event: Sendable
  associatedtype Output: Sendable

  static func transition(_ state: State, _ event: Event) -> (State, [Output])
}
