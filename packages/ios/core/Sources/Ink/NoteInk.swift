import Foundation
import Wire

/// A note's `ink` field: base64 of the compact stroke JSON.
public enum NoteInk {
  /// A socket frame carries far more than a push, so drawings keep their detail.
  private static let budget = 256 * 1024

  public static func encode(_ strokes: [Stroke]) throws -> String {
    let compact = try InkEncoder.encodeWithinBudget(
      strokes, parameters: InkEncoder.Parameters(budget: budget))
    return try JSONEncoder().encode(compact).base64EncodedString()
  }

  public static func decode(_ ink: String) throws -> [Stroke] {
    guard let data = Data(base64Encoded: ink) else { throw CocoaError(.coderReadCorrupt) }
    return try InkDecoder.decode(JSONDecoder().decode(CompactStrokes.self, from: data))
  }
}
