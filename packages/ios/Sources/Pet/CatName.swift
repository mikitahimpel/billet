import Foundation

/// The cat's name, as the room accepts it.
public enum CatName {
  public static let maxLength = 24

  /// `raw` trimmed, or `nil` when it is empty, longer than ``maxLength`` Unicode scalars, or holds a
  /// control character. The room counts scalars and applies the same rule.
  public static func clean(_ raw: String) -> String? {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.unicodeScalars.count <= maxLength,
      !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
    else { return nil }
    return name
  }
}
