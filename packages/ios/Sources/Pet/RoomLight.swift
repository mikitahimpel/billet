import Foundation

/// Where the switch on the room's wall stands. Both partners' rooms show the same one. The raw
/// value is what is stored and sent, so it stays stable across releases.
public enum RoomLight: String, CaseIterable, Codable, Hashable, Sendable {
  /// The room lit as its lighting preset says.
  case on
  /// Only the lamp and the fairy lights, low and warm.
  case cosy
  /// Every light out: only the moon and the street through the window.
  case off

  /// What the switch shows before anyone touches it.
  public static let standard = RoomLight.on

  /// Where one press of the switch goes: on, then cosy, then off, then on again.
  public var next: RoomLight {
    switch self {
    case .on: .cosy
    case .cosy: .off
    case .off: .on
    }
  }

  public var title: String {
    switch self {
    case .on: "Lights on"
    case .cosy: "Cosy"
    case .off: "Lights off"
    }
  }
}
