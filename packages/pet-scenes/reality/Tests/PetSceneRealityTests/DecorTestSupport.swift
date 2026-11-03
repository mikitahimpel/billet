import RealityKit

@testable import PetSceneReality

@MainActor
extension NookiRenovation {
  /// Picks up the piece `entity` belongs to, carries it to `point` on the floor and lets go.
  @discardableResult
  func carry(_ entity: Entity, to point: SIMD2<Float>) -> Bool {
    guard decor.select(entity), let name = decor.selected, let box = decor.plan.pieces[name]
    else { return false }
    decor.beginDrag(at: box.centre)
    decor.drag(to: point)
    decor.endDrag()
    return true
  }

  /// Lets a second and a half go by.
  func settle() {
    for _ in 0..<90 { step(1.0 / 60, reduceMotion: false) }
  }
}
