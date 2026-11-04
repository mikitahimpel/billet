import Foundation
import RealityKit
import Testing

@testable import PetSceneReality

/// The marker under a piece being moved shows over the rugs, never in or under them.
@MainActor
@Suite struct DecorMarkerTests {
  @Test func theStyledRoomsMarkerFloatsOverEveryRug() {
    for kind in [GenzPiece.Kind.patternRug, .roundRug] {
      let top = GenzKit().build(GenzPiece(kind)).visualBounds(relativeTo: nil).max.y
      #expect(GenzRoom.markerHeight > top + 0.01, "\(kind) tops out at \(top)")
    }
  }

}

/// What the decorate controls name and how they answer a piece being picked up and set down.
@Suite struct DecorStatusTests {
  private func status(_ selected: String?, holding: Bool = false) -> DecorStatus {
    var status = DecorStatus()
    status.selected = selected
    status.isHolding = holding
    return status
  }

  @Test func pickingUpAndSettingDownEachGiveOneGrip() {
    #expect(status("pouf-0").grip(from: status(nil)) == .pickUp)
    #expect(status("pouf-0", holding: true).grip(from: status(nil)) == .pickUp)
    #expect(status("pouf-0").grip(from: status("pouf-0", holding: true)) == .drop)
    #expect(status(nil).grip(from: status("pouf-0")) == .drop)
    #expect(status("rug-1").grip(from: status("pouf-0")) == .pickUp)
  }

  @Test func movingWithoutLettingGoGivesNone() {
    var moved = status("pouf-0", holding: true)
    moved.isBlocked = true
    #expect(moved.grip(from: status("pouf-0", holding: true)) == nil)
    #expect(status(nil).grip(from: status(nil)) == nil)
  }

  @Test func aPieceIsNamedByItsKind() {
    #expect(GenzRoom.title(ofDecorName: "\(GenzPiece.Kind.knitPouf.rawValue)-3") == "Knitted pouf")
    #expect(GenzRoom.title(ofDecorName: "not a piece") == nil)
    #expect(GenzRoom.title(ofDecorName: "nothing-2") == nil)
  }
}

@Suite struct DecorRingTests {
  /// The ring is brightest along its rim and faint in the middle, so the piece stays in view.
  @Test func theRingGlowsAtItsRimAndIsFaintInside() throws {
    let image = try #require(DecorSession.ringImage(pixels: 128))
    let data = try #require(image.dataProvider?.data as Data?)
    let row = image.bytesPerRow
    func alpha(_ x: Int, _ y: Int) -> UInt8 { data[y * row + x] }
    let rim = alpha(64, Int(128 * 0.15))
    #expect(rim > 200)
    #expect(alpha(64, 64) < 60)
    #expect(alpha(0, 0) < 10)
  }
}
