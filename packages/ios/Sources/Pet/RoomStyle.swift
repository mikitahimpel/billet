import Foundation

/// How a scene that has more than one room dresses it. The raw value is what gets stored, so it
/// stays stable across releases.
public enum RoomStyle: String, CaseIterable, Codable, Hashable, Sendable {
  /// A daybed under a big window on a suburb at night, the note taped to the glass.
  case windowSeat
  /// A night bedroom lit by a sunset-projection lamp, the note taped in the middle of its disc.
  case sunsetLamp
  /// The cosy diorama the scene showed first, and the one it can be renovated in.
  case nooki

  /// What a room shows before anyone chooses.
  public static let standard = RoomStyle.windowSeat

  public var title: String {
    switch self {
    case .windowSeat: "Window Seat"
    case .sunsetLamp: "Sunset Lamp"
    case .nooki: "Nooki"
    }
  }

  public var detail: String {
    switch self {
    case .windowSeat: "A daybed under a window on the street. The note is taped to the glass."
    case .sunsetLamp: "A bedroom at 11 pm. The lamp throws a sunset on the wall, the note in it."
    case .nooki: "The cosy room, seen from above."
    }
  }
}
