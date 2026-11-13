import Foundation
import Testing

@testable import DecorInterface

@Suite struct DecorFlushTests {
  /// The room with nothing of its own standing, so only the piece under test is in it.
  private let empty = DecorLayout(stored: Set(DecorItem.baseItems.map(\.id)))

  private func floor(_ id: String, _ u: Int, _ v: Int, turns: Int = 0) -> Placement {
    Placement(item: id, surface: .floor, u: u, v: v, eighthTurns: turns)
  }

  private func edges(_ placement: Placement) -> (left: Double, back: Double) {
    let item = DecorItem.item(shopID: placement.item)!
    let span = DecorLayout.span(of: placement, item: item)!
    return (span.x - span.halfX, span.z - span.halfZ)
  }

  @Test func aPieceWithinACellOfTheWallIsDrawnAgainstIt() {
    for turns in 0..<8 {
      let placement = floor("bookcase", 0, -8, turns: turns)
      let layout = empty.putting(placement)
      let shift = layout.flushShift(of: placement)
      let back = edges(placement).back + shift.dz
      #expect(abs(back + 0.5) < 1e-9 || shift.dz == 0, "turn \(turns)")
      #expect(shift.dx == 0)
    }
    let tight = floor("bookcase", 0, -8)
    #expect(abs(edges(tight).back + empty.flushShift(of: tight).dz + 0.5) < 1e-9)
  }

  @Test func aPieceInTheCornerLiesFlushOnBothWalls() {
    let placement = floor("teatable", -7, -7)
    let shift = empty.putting(placement).flushShift(of: placement)
    #expect(abs(edges(placement).left + shift.dx + 0.5) < 1e-9)
    #expect(abs(edges(placement).back + shift.dz + 0.5) < 1e-9)
  }

  @Test func aPieceAFullCellOrMoreFromTheWallStaysWhereItIs() {
    let placement = floor("bookcase", 0, -7)
    #expect(empty.putting(placement).flushShift(of: placement).dz == 0)
  }

  @Test func aPieceLiesFlushAgainstAnotherOneBehindItAndNeverIntoIt() {
    // The yarn lies from z -0.476 to -0.424; the bookcase's back is 7 mm in front of it.
    let yarn = floor("yarn", 0, -9)
    let placement = floor("bookcase", 0, -7)
    let layout = empty.putting(yarn).putting(placement)
    let shift = layout.flushShift(of: placement)
    #expect(abs(edges(placement).back + shift.dz - (-0.424)) < 1e-9)
  }

  @Test func theRoomsOwnFurnitureAtHomeStaysWhereItWasModelled() {
    for item in DecorItem.baseItems(in: .living) {
      let home = DecorLayout().placement(of: item.id)!
      let shift = DecorLayout().flushShift(of: home)
      #expect(shift.dx == 0 && shift.dz == 0, "\(item.id)")
    }
  }

  @Test func aWallPieceCanSitFlushAgainstTheWindowFrameAndNotOverlapIt() {
    // `print` is 0.174 wide; the window on the left wall spans z -0.2 to 0.24.
    let beside = Placement(item: "print", surface: .leftWall, u: -6)
    #expect(empty.verdict(beside) == .fits)
    let shift = empty.putting(beside).flushShift(of: beside)
    let item = DecorItem.item(shopID: "print")!
    let high = DecorGrid.metres(-6) + shift.dz + item.width / 2
    #expect(abs(high - (0.02 - 0.22)) < 1e-9, "its edge touches the frame")

    let over = Placement(item: "print", surface: .leftWall, u: -5)
    #expect(empty.verdict(over) == .occupied)
    let other = Placement(item: "print", surface: .leftWall, u: 0)
    #expect(empty.verdict(other) == .occupied)
  }

  @Test func aWallPieceNearACornerOfTheWindowOnTheBackWallLiesFlushToo() {
    // The shelf on the back wall spans x -0.06 to 0.14.
    let beside = Placement(item: "print", surface: .backWall, u: 5)
    let verdict = empty.verdict(beside)
    if verdict == .fits {
      let shift = empty.putting(beside).flushShift(of: beside)
      let low = DecorGrid.metres(5) + shift.dx - DecorItem.item(shopID: "print")!.width / 2
      #expect(low >= 0.14 - 1e-9 && low < 0.14 + 0.05)
    }
  }

  @Test func flushNeverMovesAPieceOutOfTheRoomOrOntoAnother() {
    for u in stride(from: -9, through: 9, by: 3) {
      for v in stride(from: -9, through: 9, by: 3) {
        let placement = floor("armchair", u, v)
        guard empty.verdict(placement) == .fits else { continue }
        let shift = empty.putting(placement).flushShift(of: placement)
        let box = edges(placement)
        #expect(box.left + shift.dx >= -0.5 - 1e-9)
        #expect(box.back + shift.dz >= -0.5 - 1e-9)
        #expect(shift.dx <= 0 && shift.dz <= 0)
      }
    }
  }
}
