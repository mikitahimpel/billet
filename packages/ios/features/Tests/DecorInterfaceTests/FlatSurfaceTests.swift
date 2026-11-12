import Testing

@testable import DecorInterface

@Suite struct FlatSurfaceTests {
  private let rug = FlatSurface(
    x: 0.1, z: 0.2, halfWidth: 0.3, halfDepth: 0.1, yaw: 0, top: 0.026)

  @Test func theFloorIsUnderAPointOffEveryPiece() {
    #expect(FlatSurface.height(atX: 0.5, z: 0.2, floor: 0.023, over: [rug]) == 0.023)
    #expect(FlatSurface.height(atX: 0, z: 0, floor: 0.023, over: []) == 0.023)
  }

  @Test func aPointOnThePieceIsAtItsTop() {
    #expect(FlatSurface.height(atX: 0.1, z: 0.2, floor: 0.023, over: [rug]) == 0.026)
    #expect(FlatSurface.height(atX: 0.39, z: 0.29, floor: 0.023, over: [rug]) == 0.026)
  }

  @Test func aTurnedPieceCoversItsTurnedFootprint() {
    var turned = rug
    turned.yaw = .pi / 2
    #expect(turned.contains(x: 0.1, z: 0.45))
    #expect(!turned.contains(x: 0.35, z: 0.2))
    #expect(FlatSurface.height(atX: 0.35, z: 0.2, floor: 0.023, over: [turned]) == 0.023)
    turned.yaw = .pi / 4
    #expect(turned.contains(x: 0.1 + 0.2, z: 0.2 - 0.2))
    #expect(!turned.contains(x: 0.1 + 0.2, z: 0.2 + 0.2))
  }

  @Test func theHighestOfOverlappingPiecesWins() {
    var cushion = rug
    cushion.top = 0.04
    cushion.halfWidth = 0.05
    #expect(FlatSurface.height(atX: 0.1, z: 0.2, floor: 0.023, over: [cushion, rug]) == 0.04)
    #expect(FlatSurface.height(atX: 0.3, z: 0.2, floor: 0.023, over: [cushion, rug]) == 0.026)
  }

  @Test func aPieceBelowTheFloorNeverLowersIt() {
    var thin = rug
    thin.top = 0.01
    #expect(FlatSurface.height(atX: 0.1, z: 0.2, floor: 0.023, over: [thin]) == 0.023)
  }
}
