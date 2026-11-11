import Foundation

/// How many of the cat's splats are drawn: every one costs a blended fragment pass and a place in the depth sort.
public enum SplatDetail: Int, CaseIterable, Comparable, Sendable, Codable {
  case full
  case balanced
  case light

  public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

  /// The share of splats kept.
  public var keep: Double {
    switch self {
    case .full: 1
    case .balanced: 0.55
    case .light: 0.4
    }
  }
}

/// Which splats can go without a visible hole.
public enum SplatPruning {
  /// How much a splat adds to the picture: its opacity times the area it covers, from the file's logit opacity and
  /// log scales. Big opaque splats carry the silhouette; small faint ones are the first to go.
  public static func importance(logitOpacity: Float, logScales: SIMD3<Float>) -> Float {
    let opacity = 1 / (1 + exp(-logitOpacity))
    let area = exp((logScales.x + logScales.y + logScales.z) * (2.0 / 3.0))
    return opacity * area
  }

  /// The indices of the `ceil(count * keep)` most important splats, in file order. Ties go to the lower index, so
  /// the same file always gives the same cut.
  public static func survivors(importance: [Float], keeping keep: Double) -> [Int] {
    guard keep < 1 else { return Array(importance.indices) }
    let wanted = min(importance.count, max(0, Int((Double(importance.count) * keep).rounded(.up))))
    return importance.indices
      .sorted { importance[$0] != importance[$1] ? importance[$0] > importance[$1] : $0 < $1 }
      .prefix(wanted)
      .sorted()
  }

  /// Added to every kept splat's log scale so the ones left cover what the cut ones did. Half the full volume
  /// compensation: the cut splats were the small, faint ones, and their overlap with the kept ones was large.
  public static func logScaleBoost(keeping keep: Double) -> Float {
    keep >= 1 ? 0 : Float(-log(keep) / 3 * 0.5)
  }
}
