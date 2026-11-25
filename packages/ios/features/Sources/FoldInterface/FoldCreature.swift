import BilletKit
import Wire

/// What the two drew, unfolded.
public struct FoldCreature: Equatable, Sendable {
  public let top: [Stroke]
  public let bottom: [Stroke]

  public init(top: [Stroke], bottom: [Stroke]) {
    self.top = top
    self.bottom = bottom
  }

  public var strokes: [Stroke] { top + bottom }

  /// What the cat calls it. The same drawing always gets the same name, on both phones, and no two people
  /// have to agree on one or type anything.
  public var name: String {
    var random = SeededRandom(seed: FoldCreature.mark(of: strokes))
    func pick(_ words: [String]) -> String { words[Int(random.next() % UInt64(words.count))] }
    return "the \(pick(Self.kinds)) \(pick(Self.starts))\(pick(Self.ends))"
  }

  static let kinds = [
    "Lesser", "Greater", "Common", "Midnight", "Sofa", "Windowsill", "Long-necked", "Shy",
    "Biscuit", "Two-toed", "Woolly", "Upside-down",
  ]
  static let starts = [
    "Flum", "Wob", "Snor", "Bim", "Quib", "Mor", "Pif", "Zan", "Dood", "Glim", "Tum", "Nib",
  ]
  static let ends = ["bit", "ble", "fle", "kin", "dle", "snoot", "wump", "let", "zel", "pop"]

  /// FNV-1a over the points, each rounded to a thousandth of the sheet so a float's last bit changes
  /// nothing.
  static func mark(of strokes: [Stroke]) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    func mix(_ value: Int) {
      var bits = UInt64(bitPattern: Int64(value))
      for _ in 0..<8 {
        hash ^= bits & 0xff
        hash = hash &* 0x0000_0100_0000_01b3
        bits >>= 8
      }
    }
    for stroke in strokes {
      mix(stroke.points.count)
      for point in stroke.points {
        mix(Int((point.x * 1000).rounded()))
        mix(Int((point.y * 1000).rounded()))
      }
    }
    return hash
  }
}
