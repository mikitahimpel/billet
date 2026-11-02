import Foundation

/// Who stands behind the counter of the 3D shop. The raw value is what gets stored, so it stays
/// stable across releases.
public enum Shopkeeper: String, CaseIterable, Codable, Hashable, Sendable {
  /// A well-loved plush teddy bear with button eyes, a red bow tie and a patch on its belly.
  case teddy
  /// A round, friendly shopkeeper in a green apron, hair in a bun.
  case human
  /// An old ginger tabby in a cardigan, round glasses low on the nose.
  case tabby
  /// A raccoon in a green apron.
  case raccoon
  /// A fox in a teal apron and a yellow scarf.
  case fox

  /// Who keeps the shop before anyone chooses: the teddy, soft and cosy, whose button eyes and
  /// bow tie read at the size it is seen across the counter.
  public static let standard = Shopkeeper.teddy

  public var title: String {
    switch self {
    case .teddy: "Teddy bear"
    case .human: "Shopkeeper"
    case .tabby: "Old tabby"
    case .raccoon: "Raccoon"
    case .fox: "Fox"
    }
  }

  public var detail: String {
    switch self {
    case .teddy: "A plush bear with button eyes, a bow tie and a patched belly."
    case .human: "A round, friendly shopkeeper in a green apron."
    case .tabby: "An old ginger cat in a cardigan and round glasses."
    case .raccoon: "A raccoon in a green apron."
    case .fox: "A fox in an apron and a yellow scarf."
    }
  }
}
