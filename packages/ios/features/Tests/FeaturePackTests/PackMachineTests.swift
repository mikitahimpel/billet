import PackInterface
import Testing

@testable import FeaturePack

typealias M = PackMachine

private func shape(_ cells: [(Int, Int)]) -> PackShape {
  PackShape(cells.map { PackCell(x: $0.0, y: $0.1) })
}

/// A suitcase of four by two: a bar each, and the cat's two squares.
private let mine = PackPiece(
  id: 1, content: .thing(.umbrella, of: .first), shape: shape([(0, 0), (1, 0), (2, 0)]))
private let yours = PackPiece(
  id: 2, content: .thing(.scarf, of: .second), shape: shape([(0, 0), (1, 0), (2, 0)]))
private let cat = PackPiece(id: 3, content: .cat, shape: shape([(0, 0), (0, 1)]))
private let level = PackLevel(width: 4, height: 2, pieces: [mine, yours, cat], solution: [:])
private let game = M.Game(seed: 1)

private func packing(_ packer: PackPacker, _ change: (inout PackCase) -> Void = { _ in }) -> M.State
{
  var suitcase = PackCase(level: level)
  change(&suitcase)
  return .packing(M.Turn(game: game, suitcase: suitcase, packer: packer))
}

private func step(_ state: M.State, _ events: M.Event...) -> M.State {
  events.reduce(state) { M.transition($0, $1).0 }
}

private func turn(_ state: M.State) -> M.Turn? {
  if case .packing(let turn) = state { turn } else { nil }
}

private func cell(_ x: Int, _ y: Int) -> PackCell { PackCell(x: x, y: y) }

@Suite struct PackMachineTests {
  @Test func theOpeningIsTheFirstPackerWithAnEmptySuitcase() {
    let opened = turn(M.opening(seed: 5))
    #expect(opened?.packer == .first)
    #expect(opened?.suitcase.placed.isEmpty == true)
    #expect(opened?.tray.count == 3)
    #expect(opened?.unseen.count == 3)
    #expect(opened?.suitcase.level == PackLevel.make(seed: 5))
  }

  @Test func aPickedPieceGoesDownWhereTheFingerPutsIt() {
    let (next, outputs) = M.transition(step(packing(.first), .picked(1)), .tapped(cell(1, 0)))
    #expect(turn(next)?.held == nil)
    #expect(turn(next)?.suitcase.placed[1] == PackPlacement(at: cell(1, 0), turns: 0))
    #expect(outputs == [.felt(.put)])
  }

  @Test func aTurnedPieceGoesDownTurned() {
    let wide = PackLevel(width: 4, height: 3, pieces: [mine, yours, cat], solution: [:])
    let start = M.State.packing(
      M.Turn(game: game, suitcase: PackCase(level: wide), packer: .first))
    let next = step(start, .picked(1), .turned, .tapped(cell(3, 0)))
    #expect(turn(next)?.suitcase.covered.keys.sorted() == [cell(3, 0), cell(3, 1), cell(3, 2)])
  }

  @Test func aPieceThatWillNotGoStaysInTheHandAndSaysWhy() {
    let (next, outputs) = M.transition(step(packing(.first), .picked(1)), .tapped(cell(2, 0)))
    #expect(turn(next)?.held == M.Held(id: 1, turns: 0))
    #expect(turn(next)?.refused == .sticksOut)
    #expect(turn(next)?.suitcase.placed.isEmpty == true)
    #expect(outputs == [.felt(.refused)])
  }

  @Test func theReasonGoesWhenThePieceIsTurnedOrPutBack() {
    let refused = step(packing(.first), .picked(1), .tapped(cell(2, 0)))
    #expect(turn(step(refused, .turned))?.refused == nil)
    #expect(turn(step(refused, .dropped))?.refused == nil)
    #expect(turn(step(refused, .dropped))?.held == nil)
  }

  @Test func aTapOnAPieceThatLiesThereLiftsItTurnedAsItLay() {
    let placed = packing(.first) { $0.put(mine, PackPlacement(at: cell(0, 0), turns: 0)) }
    let next = step(placed, .tapped(cell(2, 0)))
    #expect(turn(next)?.held == M.Held(id: 1, turns: 0))
    #expect(turn(next)?.suitcase.placed.isEmpty == true)
  }

  @Test func nobodyMovesTheOthersThings() {
    let placed = packing(.second) { $0.put(mine, PackPlacement(at: cell(0, 0), turns: 0)) }
    #expect(step(placed, .tapped(cell(0, 0))) == placed)
    #expect(step(placed, .picked(1)) == placed)
    #expect(step(packing(.first), .picked(2)) == packing(.first))
    #expect(step(packing(.first), .picked(3)) == packing(.first))
    #expect(step(packing(.first), .picked(99)) == packing(.first))
  }

  @Test func theFirstHandsOverOnlyWithAllTheirThingsIn() {
    #expect(step(packing(.first), .handedOver) == packing(.first))
    let placed = packing(.first) { $0.put(mine, PackPlacement(at: cell(0, 0), turns: 0)) }
    guard case .handover(let handover) = step(placed, .handedOver) else {
      Issue.record("not handed over")
      return
    }
    #expect(handover.to == .second)
    #expect(handover.suitcase.isIn(1))
    let taken = turn(step(.handover(handover), .took))
    #expect(taken?.packer == .second)
    #expect(taken?.tray.map(\.id) == [2, 3])
    #expect(taken?.unseen.isEmpty == true)
  }

  @Test func withEverythingInTheSuitcaseClosesSnug() {
    let packed = packing(.second) {
      $0.put(mine, PackPlacement(at: cell(0, 0), turns: 0))
      $0.put(yours, PackPlacement(at: cell(0, 1), turns: 0))
      $0.put(cat, PackPlacement(at: cell(3, 0), turns: 0))
    }
    let (next, outputs) = M.transition(packed, .zipped)
    guard case .closed(let closed) = next else {
      Issue.record("not closed")
      return
    }
    #expect(closed.ending == .snug)
    #expect(outputs == [.felt(.zipped)])
  }

  @Test func withoutRoomForTheCatSheSitsOnTop() {
    let packed = packing(.second) {
      $0.put(mine, PackPlacement(at: cell(0, 0), turns: 0))
      $0.put(yours, PackPlacement(at: cell(1, 1), turns: 0))
    }
    guard case .closed(let closed) = step(packed, .zipped) else {
      Issue.record("not closed")
      return
    }
    #expect(closed.ending == .catOnTop)
  }

  @Test func theSuitcaseDoesNotCloseWithAThingLeftOut() {
    let packed = packing(.second) { $0.put(mine, PackPlacement(at: cell(0, 0), turns: 0)) }
    #expect(step(packed, .zipped) == packed)
    let first = packing(.first) { $0.put(mine, PackPlacement(at: cell(0, 0), turns: 0)) }
    #expect(step(first, .zipped) == first)
  }

  @Test func sentBackTheSecondsThingsComeOutAndTheFirstPacksAgain() {
    let packed = packing(.second) {
      $0.put(mine, PackPlacement(at: cell(0, 0), turns: 0))
      $0.put(yours, PackPlacement(at: cell(0, 1), turns: 0))
      $0.put(cat, PackPlacement(at: cell(3, 0), turns: 0))
    }
    guard case .handover(let handover) = step(packed, .sentBack) else {
      Issue.record("not sent back")
      return
    }
    #expect(handover.to == .first)
    #expect(handover.game.repacks == 1)
    #expect(handover.suitcase.placed.keys.sorted() == [1])
    #expect(step(packing(.first), .sentBack) == packing(.first))
  }

  @Test func theCatSaysWhetherTheRestStillFitsUntilTheSuitcaseChanges() {
    let roomy = packing(.first) { $0.put(mine, PackPlacement(at: cell(0, 0), turns: 0)) }
    #expect(turn(step(roomy, .askedCat))?.nose == .fits)
    var blocked = PackCase(
      level: PackLevel(width: 3, height: 2, pieces: [mine, yours, cat], solution: [:]))
    blocked.put(mine, PackPlacement(at: cell(0, 0), turns: 0))
    let asked = step(
      .packing(M.Turn(game: game, suitcase: blocked, packer: .first)), .askedCat)
    #expect(turn(asked)?.nose == .tooTight)
    #expect(turn(step(asked, .tapped(cell(0, 0))))?.nose == nil)
  }

  @Test func againOpensTheNextSuitcase() {
    let closed = M.State.closed(
      M.Closed(game: game, suitcase: PackCase(level: level), ending: .snug))
    let next = turn(step(closed, .again))
    #expect(next?.game.round == 1)
    #expect(next?.game.repacks == 0)
    #expect(next?.packer == .first)
    #expect(next?.suitcase.level == PackLevel.make(seed: 2))
  }

  static let handover = M.State.handover(
    M.Handover(game: game, suitcase: PackCase(level: level), to: .second))
  static let closed = M.State.closed(
    M.Closed(game: game, suitcase: PackCase(level: level), ending: .catOnTop))

  static let rejected: [(M.State, M.Event)] =
    [(packing(.first), .took), (packing(.first), .again), (packing(.first), .turned)]
    + [
      .picked(1), .turned, .tapped(PackCell(x: 0, y: 0)), .dropped, .askedCat, .handedOver,
      .sentBack, .zipped, .again,
    ].map { (handover, $0) }
    + [
      .picked(1), .turned, .tapped(PackCell(x: 0, y: 0)), .dropped, .askedCat, .handedOver,
      .sentBack, .took, .zipped,
    ].map { (closed, $0) }

  @Test(arguments: rejected)
  func eventsOutOfPlaceChangeNothing(state: M.State, event: M.Event) {
    let (next, outputs) = M.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }
}
