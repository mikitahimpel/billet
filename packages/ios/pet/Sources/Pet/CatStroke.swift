import Foundation
#if canImport(simd)
  import simd
#endif

public enum PetZone: String, CaseIterable, Hashable, Sendable {
  case head
  case chin
  case back
  /// Only while the cat lies on its back.
  case belly
}

/// Which way a stroke runs against the lie of the fur.
public enum StrokeDirection: Hashable, Sendable {
  /// From the head towards the tail, the way cats like it.
  case withFur
  case againstFur
  /// Side to side, or too short to tell.
  case across
}

/// The cat as it is drawn on screen this frame: its head and the root of its tail, in view points
/// with y down, and how large it looks. Rooms project these from the cat's place each frame.
public struct CatBodyOnScreen: Hashable, Sendable {
  public var head: SIMD2<Double>
  public var tail: SIMD2<Double>
  /// How far from the line between head and tail a finger still touches the cat.
  public var girth: Double
  public var isOnBack: Bool

  public init(head: SIMD2<Double>, tail: SIMD2<Double>, girth: Double, isOnBack: Bool = false) {
    self.head = head
    self.tail = tail
    self.girth = girth
    self.isOnBack = isOnBack
  }

  /// How far along the body `point` is, 0 at the head and 1 at the tail, and how far off the line.
  private func place(of point: SIMD2<Double>) -> (along: Double, off: SIMD2<Double>) {
    let axis = tail - head
    let length = simd_length_squared(axis)
    guard length > 0.0001 else { return (0, point - head) }
    let along = simd_dot(point - head, axis) / length
    let nearest = head + axis * min(max(along, 0), 1)
    return (along, point - nearest)
  }

  /// Whether a finger at `point` is on the cat. The head counts a little beyond the body's ends.
  public func contains(_ point: SIMD2<Double>) -> Bool {
    let (along, off) = place(of: point)
    return along > -0.25 && along < 1.1 && simd_length(off) <= girth
  }

  /// The zone under `point`. The front third is the head, and under it the chin; on its back
  /// the middle is the belly.
  public func zone(at point: SIMD2<Double>) -> PetZone {
    let (along, off) = place(of: point)
    if along < 0.3 {
      // Below the head on screen, and not on top of it: the chin.
      return off.y > girth * 0.35 && along > -0.1 ? .chin : .head
    }
    if isOnBack, along < 0.85 { return .belly }
    return .back
  }

  /// Which way a finger moving by `delta` runs along the fur. Short moves read as across.
  public func direction(of delta: SIMD2<Double>) -> StrokeDirection {
    let axis = tail - head
    let travel = simd_length(delta)
    guard travel > 2, simd_length(axis) > 0.001 else { return .across }
    let along = simd_dot(delta / travel, simd_normalize(axis))
    if along > 0.55 { return .withFur }
    if along < -0.55 { return .againstFur }
    return .across
  }
}
