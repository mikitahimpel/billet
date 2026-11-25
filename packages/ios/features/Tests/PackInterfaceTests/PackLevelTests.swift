import Testing

@testable import PackInterface

private func shape(_ cells: [(Int, Int)]) -> PackShape {
  PackShape(cells.map { PackCell(x: $0.0, y: $0.1) })
}

@Suite struct PackShapeTests {
  @Test func anOutlineIsPushedToTheCornerAndReadInOrder() {
    let ell = shape([(3, 5), (3, 4), (4, 5)])
    #expect(ell.cells == [PackCell(x: 0, y: 0), PackCell(x: 0, y: 1), PackCell(x: 1, y: 1)])
    #expect(ell.width == 2)
    #expect(ell.height == 2)
    #expect(ell.anchor == PackCell(x: 0, y: 0))
  }

  @Test func fourQuarterTurnsBringItBack() {
    let ess = shape([(1, 0), (2, 0), (0, 1), (1, 1)])
    #expect(ess.turned(4) == ess)
    #expect(ess.turned(1) != ess)
    #expect(ess.turned(2) == ess)
    #expect(ess.turned(-1) == ess.turned(3))
  }

  @Test func aQuarterTurnOfABarStandsItUp() {
    let bar = shape([(0, 0), (1, 0), (2, 0)])
    #expect(bar.turned(1) == shape([(0, 0), (0, 1), (0, 2)]))
  }

  @Test func theTurnsOfAnOutlineAreEachCountedOnce() {
    #expect(shape([(0, 0), (1, 0), (0, 1), (1, 1)]).turns.count == 1)
    #expect(shape([(0, 0), (1, 0), (2, 0)]).turns.count == 2)
    #expect(shape([(0, 0), (0, 1), (1, 1)]).turns.count == 4)
  }

  @Test func theAnchorIsAlwaysASquareOfTheOutline() {
    let tee = shape([(1, 0), (0, 1), (1, 1), (2, 1)])
    for quarters in 0..<4 {
      let turned = tee.turned(quarters)
      #expect(turned.cells.contains(turned.anchor))
      #expect(turned.anchor.y == 0)
    }
  }
}

@Suite struct PackLevelTests {
  @Test func theSameSeedMakesTheSameLevel() {
    #expect(PackLevel.make(seed: 7) == PackLevel.make(seed: 7))
    #expect(PackLevel.make(seed: 7) != PackLevel.make(seed: 8))
  }

  @Test(arguments: 0..<200)
  func everyLevelHasThreeThingsEachAndTheCatAndAWayToPackThem(seed: Int) {
    let level = PackLevel.make(seed: UInt64(seed))
    #expect(level.pieces.count == 7)
    #expect(level.pieces.filter { $0.belongs(to: .first) }.count == 3)
    #expect(level.pieces.filter { $0.belongs(to: .second) }.count == 3)
    #expect(level.pieces.filter(\.isCat).count == 1)
    #expect(level.pieces.first(where: \.isCat)?.shape.cells.count == 4)
    #expect(level.pieces.allSatisfy { (3...5).contains($0.shape.cells.count) })
    #expect(Set(level.pieces.map(\.id)).count == 7)

    var suitcase = PackCase(level: level)
    for piece in level.pieces {
      let placement = level.solution[piece.id]
      #expect(placement != nil)
      if let placement { #expect(suitcase.put(piece, placement) == nil) }
    }
    #expect(suitcase.loose.isEmpty)
    #expect(suitcase.covered.count == level.pieces.reduce(0) { $0 + $1.shape.cells.count })
  }

  @Test func noTwoThingsInALevelShareAName() {
    for seed in 0..<50 {
      let names = PackLevel.make(seed: UInt64(seed)).pieces.compactMap { piece -> PackThing? in
        switch piece.content {
        case .thing(let thing, _): thing
        case .cat: nil
        }
      }
      #expect(Set(names).count == names.count)
    }
  }
}

@Suite struct PackCaseTests {
  private let bar = PackPiece(
    id: 1, content: .thing(.umbrella, of: .first), shape: shape([(0, 0), (1, 0), (2, 0)]))
  private let block = PackPiece(
    id: 2, content: .thing(.books, of: .second), shape: shape([(0, 0), (1, 0), (0, 1), (1, 1)]))
  private let loaf = PackPiece(
    id: 3, content: .cat, shape: shape([(0, 0), (1, 0), (0, 1), (1, 1)]))

  private func suitcase(width: Int, height: Int, _ pieces: [PackPiece]) -> PackCase {
    PackCase(level: PackLevel(width: width, height: height, pieces: pieces, solution: [:]))
  }

  @Test func aPieceThatSticksOutIsRefused() {
    var packed = suitcase(width: 3, height: 2, [bar])
    let problem = packed.put(bar, PackPlacement(at: PackCell(x: 1, y: 0), turns: 0))
    #expect(problem == .sticksOut)
    #expect(packed.loose == [bar])
    #expect(packed.put(bar, PackPlacement(at: PackCell(x: 0, y: -1), turns: 0)) == .sticksOut)
  }

  @Test func aPieceOnAnotherIsRefusedAndNamesIt() {
    var packed = suitcase(width: 4, height: 3, [bar, block])
    #expect(packed.put(bar, PackPlacement(at: PackCell(x: 0, y: 0), turns: 0)) == nil)
    let problem = packed.put(block, PackPlacement(at: PackCell(x: 2, y: 0), turns: 0))
    #expect(problem == .onTop(of: 1))
    #expect(packed.put(block, PackPlacement(at: PackCell(x: 2, y: 1), turns: 0)) == nil)
    #expect(packed.covered[PackCell(x: 3, y: 2)] == 2)
  }

  @Test func aPieceMayBeMovedOverWhereItLay() {
    var packed = suitcase(width: 4, height: 1, [bar])
    packed.put(bar, PackPlacement(at: PackCell(x: 0, y: 0), turns: 0))
    #expect(packed.put(bar, PackPlacement(at: PackCell(x: 1, y: 0), turns: 0)) == nil)
    #expect(packed.covered.keys.sorted() == (1...3).map { PackCell(x: $0, y: 0) })
  }

  @Test func aTurnedPieceCoversTheTurnedSquares() {
    let packed = suitcase(width: 3, height: 3, [bar])
    let cells = packed.cells(of: bar, PackPlacement(at: PackCell(x: 2, y: 0), turns: 1))
    #expect(cells == (0...2).map { PackCell(x: 2, y: $0) })
  }

  @Test func liftingAPieceFreesItsSquares() {
    var packed = suitcase(width: 3, height: 1, [bar])
    packed.put(bar, PackPlacement(at: PackCell(x: 0, y: 0), turns: 0))
    packed.lift(1)
    #expect(packed.covered.isEmpty)
    #expect(!packed.isIn(1))
  }

  @Test func theRestStillFitsOnlyWhileThereIsAWay() {
    var packed = suitcase(width: 4, height: 3, [bar, block, loaf])
    #expect(packed.stillFits)
    // The bar across the middle leaves two rows of one, and no room for a block.
    packed.put(bar, PackPlacement(at: PackCell(x: 0, y: 1), turns: 0))
    #expect(!packed.stillFits)
    packed.put(bar, PackPlacement(at: PackCell(x: 0, y: 0), turns: 0))
    #expect(packed.stillFits)
  }

  @Test func tooManySquaresNeverFit() {
    let packed = suitcase(width: 3, height: 2, [block, loaf])
    #expect(!packed.stillFits)
  }
}
