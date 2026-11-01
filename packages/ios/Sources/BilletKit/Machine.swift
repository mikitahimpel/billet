/// A feature's behaviour as a pure function from state and event to the next state and its outputs.
///
/// `transition` performs no work. An `Output` describes work for a ``Store`` to run, so a machine
/// can be tested without any services. Switch over `(state, event)` exhaustively, with no
/// `default` and no wildcard in place of a state or an event, so that adding a case fails to
/// compile until each pairing has been decided.
public protocol Machine {
  associatedtype State: Sendable
  associatedtype Event: Sendable
  associatedtype Output: Sendable

  static func transition(_ state: State, _ event: Event) -> (State, [Output])
}
