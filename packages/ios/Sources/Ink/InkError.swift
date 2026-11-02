public enum InkError: Error, Hashable, Sendable {
  case invalidColor(String)
  case oddPointCount(strokeIndex: Int)
  case invalidParameters
  case overBudget(budget: Int, smallest: Int)
  /// A coordinate or width is NaN or infinite.
  case nonFinite(strokeIndex: Int)
  /// A coordinate or width is finite but far outside the unit square, or a width is negative.
  case outOfRange(strokeIndex: Int)
  /// The compact strokes could not be turned into JSON.
  case encodingFailed
}

/// The one colour form the contract allows: `#` and six hexadecimal digits.
public enum InkColor {
  public static func isValid(_ hex: String) -> Bool {
    let bytes = Array(hex.utf8)
    guard bytes.count == 7, bytes[0] == UInt8(ascii: "#") else { return false }
    return bytes.dropFirst().allSatisfy {
      ($0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9"))
        || ($0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "f"))
        || ($0 >= UInt8(ascii: "A") && $0 <= UInt8(ascii: "F"))
    }
  }
}
