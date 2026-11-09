import Foundation

/// How the first screen is laid out around the room. The raw value is what gets stored, so it
/// stays stable across releases.
public enum HomeVariant: String, CaseIterable, Hashable, Sendable {
  /// The room above its cards and the Draw button.
  case classic
  /// The room edge to edge, one pen to draw, everything else in a sheet pulled up from the bottom.
  case immersive
  /// As immersive, with a room that answers the phone's tilt and the finger, and controls that
  /// wait until the room is left alone.
  case livingWindow
  /// As immersive, lit for the time of day here, with the partner's sky in the window.
  case nightAndDay

  public static let standard = HomeVariant.classic

  public var title: String {
    switch self {
    case .classic: "Classic"
    case .immersive: "Immersive"
    case .livingWindow: "Living window"
    case .nightAndDay: "Night and day"
    }
  }

  public var detail: String {
    switch self {
    case .classic: "The room, its cards and the Draw button."
    case .immersive: "Only the room and a pen. Pull up for the rest."
    case .livingWindow: "Tilt the phone, the cat watches your finger, hold for a treat."
    case .nightAndDay: "Lit for the hour here. Their sky is in the window."
    }
  }

  /// Whether the room fills the screen with no cards over it.
  public var isFullBleed: Bool {
    switch self {
    case .classic: false
    case .immersive, .livingWindow, .nightAndDay: true
    }
  }
}

extension HomeVariant: Codable {
  /// Layouts Home once had, and the one each became.
  static let retired: [String: HomeVariant] = ["cinematic": .immersive]

  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let variant = HomeVariant(rawValue: raw) ?? Self.retired[raw] else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "No Home layout \(raw)"))
    }
    self = variant
  }
}
