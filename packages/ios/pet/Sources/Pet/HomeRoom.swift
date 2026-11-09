import Foundation

/// Which room Home shows the cat in. Chosen in Labs. The raw value is what gets stored, so it stays
/// stable across releases.
public enum HomeRoom: String, CaseIterable, Codable, Hashable, Sendable {
  /// A daybed under a big window on a suburb at night, the note taped to the glass.
  case windowSeat
  /// A snowed-in cabin seen from above like a diorama, the note pinned in the middle of it.
  case nookiCabin

  public static let standard = HomeRoom.windowSeat

  public var title: String {
    switch self {
    case .windowSeat: "Window Seat"
    case .nookiCabin: "Cabin"
    }
  }

  public var detail: String {
    switch self {
    case .windowSeat: "A daybed under a window on the street. The note is taped to the glass."
    case .nookiCabin: "A snowed-in cabin seen from above. The note hangs on the polaroid garland."
    }
  }
}
