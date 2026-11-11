import DecorInterface
import Testing
import Wire

@testable import FeatureDecor

@Suite struct DecorSyncPlanTests {
  private let chair = Placement(item: "armchair", surface: .floor, u: -2, v: 6)
  private let print = Placement(item: "print", surface: .backWall, u: 6)

  @Test func agreeingLayoutsNeedNoChange() {
    #expect(DecorSyncPlan.changes(from: [chair, print], to: [print, chair]).isEmpty)
  }

  @Test func aNewPieceIsPlacedAndAMovedOneIsPlacedAgain() {
    let moved = Placement(item: "armchair", surface: .floor, u: 0, v: 6)
    let changes = DecorSyncPlan.changes(from: [chair], to: [moved, print])
    #expect(changes == [.place(DecorSyncPlan.wire(moved)), .place(DecorSyncPlan.wire(print))])
  }

  @Test func aPieceTakenBackIsUnplaced() {
    #expect(
      DecorSyncPlan.changes(from: [chair, print], to: [print])
        == [.unplace(RoomItemId("armchair"))])
  }

  @Test func theWireShapeRoundTrips() {
    #expect(DecorSyncPlan.placement(DecorSyncPlan.wire(chair)) == chair)
    #expect(DecorSyncPlan.placements([DecorSyncPlan.wire(print)]) == [print])
  }

  @Test func aPlacementThisBuildDoesNotKnowIsLeftOut() {
    let odd = RoomPlacement(
      item: RoomItemId("armchair"), surface: "ceiling", u: 0, v: 0, quarterTurns: 0)
    let unknown = RoomPlacement(
      item: RoomItemId("hammock"), surface: "floor", u: 0, v: 0, quarterTurns: 0)
    #expect(DecorSyncPlan.placements([odd, unknown, DecorSyncPlan.wire(chair)]) == [chair])
  }
}
