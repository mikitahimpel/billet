import Testing

@testable import Design

@Suite struct TileButtonTests {
  @Test func aPieceInTheRoomIsDrawnLikeAPieceToPlace() {
    #expect(TileButton.Face.inRoom.chrome == .outline)
    #expect(TileButton.Face.place.chrome == .outline)
  }

  @Test func eachFaceHasItsChrome() {
    #expect(TileButton.Face.price(90, was: 120).chrome == .honey)
    #expect(TileButton.Face.price(90, was: nil).chrome == .honey)
    #expect(TileButton.Face.short(missing: 40).chrome == .ring)
    #expect(TileButton.Face.owned.chrome == .label)
  }
}
