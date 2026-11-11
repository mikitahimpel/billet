import Foundation
#if canImport(simd)
  import simd
#endif

/// Notices a cat who is not where a room can show her and says what puts it right: her position is no number or
/// lies outside the room (snap her home), or nothing of her has been drawn for a while although the room is on
/// screen (show her again).
public struct CatWatch: Sendable {
  public enum Verdict: Equatable, Sendable {
    case fine
    case showAgain
    case snapHome
  }

  /// How far from the room's middle she may be along the floor, and the heights she may be at, in room units.
  public static let reach: Float = 2
  public static let heights: ClosedRange<Float> = -0.2...1.5

  public let patience: Double
  public private(set) var hiddenFor: Double = 0

  public init(patience: Double = 2) {
    self.patience = patience
  }

  public static func isInRoom(_ at: SIMD3<Float>) -> Bool {
    at.x.isFinite && at.y.isFinite && at.z.isFinite && abs(at.x) <= reach && abs(at.z) <= reach
      && heights.contains(at.y)
  }

  /// `isDrawn` is whether any of her splats is enabled, attached to this room and in its scene; a room that is not on
  /// screen passes true, so waiting there counts for nothing.
  public mutating func update(_ dt: Double, at: SIMD3<Float>, isDrawn: Bool) -> Verdict {
    guard Self.isInRoom(at) else {
      hiddenFor = 0
      return .snapHome
    }
    guard !isDrawn else {
      hiddenFor = 0
      return .fine
    }
    hiddenFor += dt
    guard hiddenFor >= patience else { return .fine }
    hiddenFor = 0
    return .showAgain
  }
}
