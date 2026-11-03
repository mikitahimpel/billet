import Foundation

/// Who stands behind the counter of the 3D shop. The raw value is what gets stored, so it stays
/// stable across releases.
public enum Shopkeeper: String, CaseIterable, Hashable, Sendable {
  /// A well-loved plush teddy bear with button eyes, a red bow tie and a patch on its belly.
  case teddy
  /// A round, friendly shopkeeper in a green apron, hair in a bun.
  case human

  /// Who keeps the shop before anyone chooses: the teddy, soft and cosy, whose button eyes and
  /// bow tie read at the size it is seen across the counter.
  public static let standard = Shopkeeper.teddy

  /// Keepers the shop once had. Someone who chose one of them gets the teddy.
  static let retired: Set<String> = ["tabby", "raccoon", "fox"]

  public var title: String {
    switch self {
    case .teddy: "Teddy bear"
    case .human: "Shopkeeper"
    }
  }

  public var detail: String {
    switch self {
    case .teddy: "A plush bear with button eyes, a bow tie and a patched belly."
    case .human: "A round, friendly shopkeeper in a green apron."
    }
  }
}

extension Shopkeeper: Codable {
  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    if let keeper = Shopkeeper(rawValue: raw) {
      self = keeper
    } else if Self.retired.contains(raw) {
      self = .teddy
    } else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "No shopkeeper \(raw)"))
    }
  }
}
