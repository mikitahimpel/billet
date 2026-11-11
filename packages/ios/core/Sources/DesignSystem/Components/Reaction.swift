import Foundation

/// The raw value is the room's name for it.
public enum Reaction: String, CaseIterable, Codable, Hashable, Sendable {
  case heart
  case stamp

  public var symbol: String {
    switch self {
    case .heart: "heart.fill"
    case .stamp: "seal.fill"
    }
  }

  public var title: String {
    switch self {
    case .heart: "Heart"
    case .stamp: "Stamp"
    }
  }

  public var tint: Swatch {
    switch self {
    case .heart: Palette.clayLit
    case .stamp: Palette.gold
    }
  }
}
