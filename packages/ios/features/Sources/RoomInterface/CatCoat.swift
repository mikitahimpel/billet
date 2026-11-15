import Foundation

/// Mochi's coat, picked in onboarding. Grey is the original; every other coat recolours it. The
/// id, name and pictures live here so every feature can name a coat.
public enum CatCoat: String, CaseIterable, Sendable {
  case grey, ginger, cream, tuxedo, black, calico

  public static let key = "catCoat"

  /// The coats the picker shows. Tuxedo and calico stay decodable for a phone that picked them,
  /// but are not offered: their renders read badly.
  public static let offered: [CatCoat] = [.grey, .ginger, .cream, .black]

  public static func current(in defaults: UserDefaults = .standard) -> CatCoat {
    defaults.string(forKey: key).flatMap(CatCoat.init(rawValue:)) ?? .grey
  }

  public var title: String {
    switch self {
    case .grey: "Grey tabby"
    case .ginger: "Ginger"
    case .cream: "Cream"
    case .tuxedo: "Tuxedo"
    case .black: "Black"
    case .calico: "Calico"
    }
  }

  /// The card in the onboarding carousel: the seated cat in this coat, on transparency.
  public var portrait: String { "Coat-\(rawValue)" }

  /// Her round avatar in this coat: the original for grey, the others rendered the same way.
  public var avatar: String { self == .grey ? "MochiPortrait" : "MochiPortrait-\(rawValue)" }

  /// The poses that have coats; each is `<pose>.ply` with its `.skin` and `.rig.json` beside it.
  public static let poses = ["Mochi", "MochiStanding", "MochiLoaf", "MochiSleep"]
}
