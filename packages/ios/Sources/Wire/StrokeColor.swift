/// The one colour form the contract allows: `#` and six hexadecimal digits, as in the schema's
/// `Color` pattern `^#[0-9A-Fa-f]{6}$`.
enum StrokeColor {
  static func isValid(_ hex: String) -> Bool {
    let bytes = Array(hex.utf8)
    guard bytes.count == 7, bytes[0] == UInt8(ascii: "#") else { return false }
    return bytes.dropFirst().allSatisfy {
      ($0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9"))
        || ($0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "f"))
        || ($0 >= UInt8(ascii: "A") && $0 <= UInt8(ascii: "F"))
    }
  }
}
