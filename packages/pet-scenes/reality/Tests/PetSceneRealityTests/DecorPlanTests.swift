import Foundation
import Testing
import simd

@testable import PetSceneReality

@Suite struct DecorPlanTests {
  private func plan() -> DecorPlan {
    DecorPlan(
      minimum: [0, 0], maximum: [4, 3], grid: 0.25,
      fixed: ["bed": DecorBox(centre: [3, 0.5], half: [1, 0.5])],
      pieces: [
        "chair": DecorBox(centre: [0.5, 2.5], half: [0.25, 0.25]),
        "crate": DecorBox(centre: [2, 2], half: [0.5, 0.25]),
        "rug": DecorBox(centre: [2, 1.75], half: [1, 0.75]),
      ],
      flat: ["rug"])
  }

  private func near(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool { simd_distance(a, b) < 0.0001 }

  // MARK: Snapping

  @Test func pointsSnapToTheGrid() {
    #expect(near(plan().snapped([1.13, 0.37]), [1.25, 0.25]))
    #expect(near(plan().snapped([-0.12, 2.88]), [0, 3]))
  }

  @Test func turnsSnapToFifteenDegreesAndWrap() {
    let plan = plan()
    #expect(abs(plan.snapped(yaw: 0.3) - .pi / 12) < 0.0001)
    #expect(abs(plan.snapped(yaw: 0.05)) < 0.0001)
    #expect(abs(abs(plan.snapped(yaw: 3.1)) - .pi) < 0.0001)
    #expect(abs(plan.snapped(yaw: 2 * .pi + .pi / 2) - .pi / 2) < 0.0001)
  }

  @Test func aCandidateFollowsTheFingerOnTheGrid() throws {
    let move = try #require(plan().candidate(for: "chair", at: [1.1, 0.4], yaw: 0))
    #expect(near(move.box.centre, [1, 0.5]))
    #expect(move.fit == .free)
  }

  // MARK: Bounds

  @Test func aPiecePushedIntoAWallSlidesAlongIt() throws {
    let move = try #require(plan().candidate(for: "chair", at: [-2, 1.5], yaw: 0))
    #expect(near(move.box.centre, [0.25, 1.5]))
    #expect(move.fit == .free)
  }

  @Test func aPieceOutsideTheSurfaceDoesNotFit() {
    let box = DecorBox(centre: [3.9, 1.5], half: [0.25, 0.25])
    #expect(plan().fit(box, for: "chair") == .outside)
  }

  @Test func aTurnedPieceNeedsMoreRoomFromTheWall() throws {
    // Turned 45°, a 0.5 square reaches about 0.35 from its centre.
    let move = try #require(plan().candidate(for: "chair", at: [0, 1.5], yaw: .pi / 4))
    #expect(move.box.centre.x - move.box.reach.x >= -0.0005)
    #expect(move.box.reach.x > 0.34)
  }

  // MARK: Collision

  @Test func aPieceCantStandOnAnother() throws {
    let move = try #require(plan().candidate(for: "chair", at: [2, 2], yaw: 0))
    #expect(move.fit == .blocked("crate"))
  }

  @Test func aPieceCantStandOnSomethingFixed() throws {
    let move = try #require(plan().candidate(for: "chair", at: [3, 0.5], yaw: 0))
    #expect(move.fit == .blocked("bed"))
  }

  @Test func piecesThatOnlyTouchFit() throws {
    let move = try #require(plan().candidate(for: "chair", at: [1.25, 2], yaw: 0))
    #expect(move.fit == .free)
  }

  @Test func aPieceDoesNotBlockItself() throws {
    #expect(try #require(plan().candidate(for: "crate", at: [2.1, 2.1], yaw: 0)).fit == .free)
  }

  @Test func rugsLieUnderEverything() throws {
    #expect(try #require(plan().candidate(for: "chair", at: [2, 1.25], yaw: 0)).fit == .free)
    #expect(try #require(plan().candidate(for: "rug", at: [2, 1.5], yaw: 0)).fit == .free)
  }

  @Test func turnedBoxesOverlapOnlyWhereTheyReallyMeet() {
    let diamond = DecorBox(centre: [0, 0], half: [0.5, 0.5], yaw: .pi / 4)
    // The upright boxes around both would overlap, but the corner of this one misses the diamond.
    #expect(!diamond.overlaps(DecorBox(centre: [0.62, 0.62], half: [0.15, 0.15])))
    #expect(diamond.overlaps(DecorBox(centre: [0.6, 0], half: [0.15, 0.15])))
  }

  @Test func aTurnCanBlockWhereUprightFits() throws {
    var plan = plan()
    plan.pieces["shelf"] = DecorBox(centre: [1.75, 1.25], half: [0.75, 0.1])
    #expect(plan.candidate(for: "shelf", at: [1.75, 1.25], yaw: 0)?.fit == .free)
    #expect(plan.candidate(for: "shelf", at: [1.75, 1.25], yaw: .pi / 2)?.fit == .blocked("crate"))
  }

  @Test func anUnknownPieceHasNoCandidate() {
    #expect(plan().candidate(for: "piano", at: [1, 1], yaw: 0) == nil)
  }

  // MARK: Open spots

  @Test func aNewPieceGoesToTheNearestFreeSpot() throws {
    let spot = try #require(plan().openSpot(half: [0.25, 0.25], near: [2, 2]))
    let box = DecorBox(centre: spot, half: [0.25, 0.25])
    #expect(plan().fit(box, for: nil) == .free)
    #expect(simd_distance(spot, [2, 2]) < 0.8)
  }

  @Test func aFullSurfaceHasNoOpenSpot() {
    var plan = plan()
    plan.fixed["everything"] = DecorBox(centre: [2, 1.5], half: [2, 1.5])
    #expect(plan.openSpot(half: [0.25, 0.25], near: [1, 1]) == nil)
  }

  // MARK: Undo

  @Test func undoGivesBackTheStepsNewestFirst() {
    var history = DecorHistory<Int>()
    #expect(!history.canUndo)
    history.record(1)
    history.record(2)
    #expect(history.undo() == 2)
    #expect(history.undo() == 1)
    #expect(history.undo() == nil)
  }

  @Test func historyKeepsOnlyTheNewestSteps() {
    var history = DecorHistory<Int>(limit: 3)
    for step in 1...5 { history.record(step) }
    #expect(history.steps == [3, 4, 5])
  }
}
