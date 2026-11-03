import CoreGraphics
import Foundation
import Pet
import RealityKit
import simd

/// What fingers and the decorate controls do to a room's ``DecorSession``, the same in every
/// room. A room supplies the floor under a finger and how its floor maps to the shop's.
@MainActor
struct DecorTouch {
  let session: DecorSession
  let renovator: RoomRenovator?
  /// The point on the plan's floor under a point in the view.
  let floor: (CGPoint) -> SIMD2<Float>?
  /// A footprint on the plan's floor in the shop's metres, and back.
  var toShop: (DecorBox) -> (x: Double, z: Double, yaw: Double) = {
    (Double($0.centre.x), Double($0.centre.y), Double($0.yaw))
  }
  /// The name the session knows a shop placement by.
  var name: (RoomLayout.Placement.ID) -> String = { $0 }

  /// A finger that went down on `entity` at `start` is now at `location`. Picks the piece up if
  /// that is where it went down, opening the room first through `enter` if it is closed. Returns
  /// whether the finger is moving a piece, so the room should not turn.
  @discardableResult
  func drag(_ entity: Entity, from start: CGPoint, to location: CGPoint, enter: () -> Void)
    -> Bool
  {
    if !session.isDragging {
      guard let name = session.piece(containing: entity), let point = floor(start) else {
        return false
      }
      if !session.isOn { enter() }
      session.isOn = true
      if session.selected != name { session.select(name: name) }
      session.beginDrag(at: point)
    }
    if let point = floor(location) { session.drag(to: point) }
    return true
  }

  func endDrag() { session.endDrag() }

  /// A tap while decorating picks up the piece tapped, or lets go of the one held.
  func tap(_ entity: Entity) {
    if let name = session.piece(containing: entity) {
      if session.selected == name { session.deselect() } else { session.select(name: name) }
    } else {
      session.deselect()
    }
  }

  /// Two fingers have turned by `angle` since they went down.
  func twist(by angle: Double) {
    guard session.selected != nil else { return }
    if !session.isTurning { session.beginTurn() }
    session.turn(by: Float(angle))
  }

  func endTwist() { session.endTurn() }

  func undo() {
    guard let step = session.undo() else { return }
    switch step {
    case .moved: break
    case .added(let id):
      try? renovator?.putAway(id)
    case .putAway(let itemID, let box):
      guard let renovator, let item = ShopCatalog.standard.item(itemID) else { return }
      let spot = toShop(box)
      _ = try? renovator.place(item, at: (spot.x, spot.z), yaw: spot.yaw)
    }
  }

  /// Sends the piece picked up back to the closet.
  func putAway() {
    guard let selected = session.selected, let piece = session.pieces[selected],
      let id = piece.placement, let box = session.plan.pieces[selected],
      let placement = renovator?.placement(id)
    else { return }
    session.deselect()
    do {
      try renovator?.putAway(id)
      session.record(.putAway(placement.item, box: box))
    } catch {}
  }

  /// Takes `item` from the closet and stands it at the open spot nearest `near`, picked up.
  func add(_ item: ShopItem, half: SIMD2<Float>, near: SIMD2<Float>) -> ShopError? {
    guard let renovator else { return nil }
    guard let spot = session.plan.openSpot(half: half, near: near) else { return .roomIsFull }
    let shop = toShop(DecorBox(centre: spot, half: half))
    do {
      let id = try renovator.place(item, at: (shop.x, shop.z))
      session.selectWhenRegistered = name(id)
      session.record(.added(id))
      return nil
    } catch {
      return error
    }
  }
}
