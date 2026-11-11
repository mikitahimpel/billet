import Foundation

/// The app's look. Chosen in Settings → Labs and read once, at the first token, so every colour and
/// face below holds for the run and the two looks can be compared on one phone across a relaunch.
public enum Look: String, CaseIterable, Sendable {
  /// Cream and honey, SF Rounded: the look the app shipped with.
  case classic
  /// The landing's night: warm near-black, cream ink, amber, and a grotesque display face.
  case dusk

  public static let key = "design.look"

  public static let current: Look = {
    Look(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .classic
  }()

  public var title: String {
    switch self {
    case .classic: "Classic"
    case .dusk: "Dusk"
    }
  }
}
