import BilletKit

/// The chrome over the room steps back after a while without a touch and returns on the next one.
/// Each wait carries an id, so a wait a touch has since restarted is a legal event that changes
/// nothing.
public enum QuietRoomMachine: Machine {
  public static let after = Duration.seconds(6)

  public enum State: Equatable, Sendable {
    /// Not on the World, something over it, a game, VoiceOver, or the variant off.
    case off(wait: Int)
    case awake(wait: Int)
    case quiet(wait: Int)

    public var isQuiet: Bool {
      switch self {
      case .quiet: true
      case .off, .awake: false
      }
    }
  }

  public enum Event: Equatable, Sendable {
    case allowed(Bool)
    case touched
    case waited(Int)
  }

  public enum Output: Equatable, Sendable {
    /// Sleep ``QuietRoomMachine/after``, then send `.waited(id)`.
    case wait(Int)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.off(let wait), .allowed(true)),
      (.awake(let wait), .touched),
      (.quiet(let wait), .touched):
      return (.awake(wait: wait + 1), [.wait(wait + 1)])

    case (.awake(let wait), .allowed(false)), (.quiet(let wait), .allowed(false)):
      return (.off(wait: wait), [])

    case (.awake(let wait), .waited(let id)) where id == wait:
      return (.quiet(wait: wait), [])

    case (.off, .allowed(false)), (.off, .touched), (.off, .waited),
      (.awake, .allowed(true)), (.awake, .waited),
      (.quiet, .allowed(true)), (.quiet, .waited):
      return (state, [])
    }
  }
}

/// How the chrome steps back on a quiet room: a Labs choice, so the owner can compare.
public enum QuietChrome: String, CaseIterable, Sendable {
  case off
  case dim
  case hide

  public var title: String {
    switch self {
    case .off: "Off"
    case .dim: "Dim"
    case .hide: "Hide"
    }
  }

  /// The chrome's opacity while the room is quiet.
  public var quietOpacity: Double {
    switch self {
    case .off: 1
    case .dim: 0.18
    case .hide: 0
    }
  }

  /// A dimmed control still shows where it is, so a tap on it works; a hidden one lets the first
  /// touch through to the room.
  public var quietTakesTouches: Bool {
    switch self {
    case .off, .dim: true
    case .hide: false
    }
  }
}
