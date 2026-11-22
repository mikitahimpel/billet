import Foundation

/// The few words tucked in with a hidden mouse.
public enum MischiefLine {
  /// Unicode scalars, as the server counts them.
  public static let maxScalars = 40

  /// What the field keeps while the hider types: no control characters, at most `maxScalars`.
  public static func clip(_ text: String) -> String {
    String(
      String.UnicodeScalarView(text.unicodeScalars.filter { !isControl($0) }.prefix(maxScalars)))
  }

  /// What is sent: trimmed, clipped, and nil when nothing is left.
  public static func clean(_ text: String) -> String? {
    let line = clip(text).trimmingCharacters(in: .whitespacesAndNewlines)
    return line.isEmpty ? nil : line
  }

  private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
    scalar.properties.generalCategory == .control
  }
}
