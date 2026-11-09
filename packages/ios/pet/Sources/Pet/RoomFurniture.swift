import Foundation

/// Which set of furniture fills the styled rooms, so sets can be compared in Labs. The raw value
/// is what gets stored, so it stays stable across releases.
public enum RoomFurniture: String, CaseIterable, Codable, Hashable, Sendable {
  /// Simple blocks.
  case original
  /// Soft and handmade: a quilted daybed under a knitted throw, books in a crate, leafy plants,
  /// polaroids, mugs, a jumper over a chair.
  case cosyNook
  /// Dark wood and mustard: a record player and speaker, posters, a patterned rug.
  case retroDen

  public static let standard = RoomFurniture.cosyNook

  public var title: String {
    switch self {
    case .original: "Original"
    case .cosyNook: "Cosy nook"
    case .retroDen: "Retro den"
    }
  }

  public var detail: String {
    switch self {
    case .original: "The first simple pieces."
    case .cosyNook: "Quilted daybed, knitted throw, books, plants and polaroids."
    case .retroDen: "Record player, speaker, posters and a patterned rug."
    }
  }
}
