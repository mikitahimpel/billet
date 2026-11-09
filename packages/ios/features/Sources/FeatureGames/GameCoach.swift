import BilletKit

/// The hand that shows how a game is played: it shows each step as soon as the step comes up, goes
/// at the first touch, and comes back once the player has left the game alone for a while.
public enum GameCoach: Machine {
  /// Seconds without a touch before the hand shows the step again.
  public static let patience: Double = 5

  public enum State: Equatable, Sendable {
    /// Nothing to show: the game needs no gesture now.
    case idle
    /// The hand shows `step`.
    case showing(step: Int)
    /// The player has touched since `step` came up; `idle` seconds have passed without a touch.
    case quiet(step: Int, idle: Double)
  }

  public enum Event: Equatable, Sendable {
    /// The step the game is at, or nil when it needs no gesture.
    case step(Int?)
    case touched
    case tick(Double)
  }

  public enum Output: Equatable, Sendable {}

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.idle, .step(let next)):
      return (next.map { .showing(step: $0) } ?? .idle, [])
    case (.showing(let step), .step(let next)), (.quiet(let step, _), .step(let next)):
      guard let next else { return (.idle, []) }
      return (next == step ? state : .showing(step: next), [])
    case (.showing(let step), .touched), (.quiet(let step, _), .touched):
      return (.quiet(step: step, idle: 0), [])
    case (.quiet(let step, let idle), .tick(let dt)):
      let waited = idle + max(dt, 0)
      return (waited >= patience ? .showing(step: step) : .quiet(step: step, idle: waited), [])
    case (.idle, .touched), (.idle, .tick), (.showing, .tick):
      return (state, [])
    }
  }
}

extension GameCoach.State {
  /// The step the hand shows now.
  public var shown: Int? {
    switch self {
    case .showing(let step): step
    case .idle, .quiet: nil
    }
  }
}
