import DecorInterface
import RaidInterface

extension RaidBoard {
  /// The living room as the pair arranged it. Wall pieces are not on the floor and are left out.
  public init(layout: DecorLayout) {
    let room = DecorRoom.home
    let pieces = layout.allPlacements(in: room).compactMap { placement -> RaidPiece? in
      guard placement.surface == .floor, let item = DecorItem.item(shopID: placement.item) else {
        return nil
      }
      let (width, depth) = DecorLayout.footprint(of: item, eighthTurns: placement.eighthTurns)
      return RaidPiece(
        id: item.id, title: item.base?.title ?? item.id,
        centre: RaidPoint(x: DecorGrid.metres(placement.u), z: DecorGrid.metres(placement.v)),
        halfX: width / 2, halfZ: depth / 2, height: item.height, isFlat: item.isFlat)
    }
    let spawn = layout.spawnSpot(in: room)
    self.init(pieces: pieces, start: RaidPoint(x: spawn.x, z: spawn.z))
  }
}
