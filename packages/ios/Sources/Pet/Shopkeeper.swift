import Foundation

/// Who stands behind the counter of the 3D shop. The raw value is what gets stored, so it stays
/// stable across releases.
public enum Shopkeeper: String, CaseIterable, Codable, Hashable, Sendable {
  /// An old ginger tabby in a cardigan, round glasses low on the nose.
  case tabby
  /// A raccoon in a green apron.
  case raccoon
  /// A fox in a teal apron and a yellow scarf.
  case fox

  /// Who keeps the shop before anyone chooses. The old tabby reads as a shopkeeper at a glance,
  /// and the glasses carry its face at the size it is seen across the counter.
  public static let standard = Shopkeeper.tabby

  public var title: String {
    switch self {
    case .tabby: "Old tabby"
    case .raccoon: "Raccoon"
    case .fox: "Fox"
    }
  }

  public var detail: String {
    switch self {
    case .tabby: "An old ginger cat in a cardigan and round glasses."
    case .raccoon: "A raccoon in a green apron."
    case .fox: "A fox in an apron and a yellow scarf."
    }
  }
}
