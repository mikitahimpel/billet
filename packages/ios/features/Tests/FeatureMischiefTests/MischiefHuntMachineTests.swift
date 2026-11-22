import Foundation
import MischiefInterface
import Testing

@testable import FeatureMischief

struct MischiefHuntMachineTests {
  typealias M = MischiefHuntMachine

  static let start = Date(timeIntervalSince1970: 1_000_000)
  static let hide = MischiefHide(
    id: "h1", by: "leo", spot: .basket, line: "behind you", at: start, found: nil)
  static func hunting(misses: [(MischiefSpot, Warmth)] = []) -> M.State {
    var state = M.State.hunting(M.Hunt(hide: hide, startedAt: start))
    for (spot, warmth) in misses {
      state = M.transition(state, .look(spot, warmth: warmth, at: start)).0
    }
    return state
  }
  static let found = M.State.found(M.Found(hide: hide, tries: 2, seconds: 40))

  @Test(arguments: [M.State.idle, MischiefHuntMachineTests.found])
  func aHuntBeginsFromIdleOrAfterAFind(state: M.State) {
    let (next, outputs) = M.transition(state, .begin(Self.hide, at: Self.start))
    #expect(next == Self.hunting())
    #expect(outputs.isEmpty)
  }

  @Test func aSecondBeginWhileHuntingChangesNothing() {
    let state = Self.hunting(misses: [(.sill, .cold)])
    let other = MischiefHide(
      id: "h2", by: "leo", spot: .sofa, line: nil, at: Self.start, found: nil)
    #expect(M.transition(state, .begin(other, at: Self.start)) == (state, []))
  }

  @Test(arguments: [
    (Warmth.cold, MischiefHint.away), (.cool, .curious), (.warm, .turns(toward: .basket)),
    (.hot, .sniffs(at: .basket)),
  ])
  func eachWarmthIsAHint(warmth: Warmth, hint: MischiefHint) {
    let (next, outputs) = M.transition(Self.hunting(), .look(.sill, warmth: warmth, at: Self.start))
    #expect(outputs == [.hint(hint)])
    guard case .hunting(let hunt) = next else {
      Issue.record("not hunting")
      return
    }
    #expect(hunt.misses == 1)
    #expect(hunt.last == .init(spot: .sill, warmth: warmth))
  }

  @Test func thirdMissLeadsThePlainWay() {
    var state = Self.hunting(misses: [(.sill, .cold), (.sofa, .cool)])
    var outputs: [M.Output]
    (state, outputs) = M.transition(state, .look(.tree, warmth: .cold, at: Self.start))
    #expect(outputs == [.hint(.leads(to: .basket))])
    (state, outputs) = M.transition(state, .look(.crate, warmth: .cold, at: Self.start))
    #expect(outputs == [.hint(.leads(to: .basket))])
  }

  @Test func theRightSpotFindsItAndCountsTriesAndSeconds() {
    let state = Self.hunting(misses: [(.sill, .cold), (.sofa, .cool)])
    let at = Self.start.addingTimeInterval(83.9)
    let (next, outputs) = M.transition(state, .look(.basket, warmth: .hot, at: at))
    let found = M.Found(hide: Self.hide, tries: 3, seconds: 83)
    #expect(next == .found(found))
    #expect(outputs == [.hint(.pounces(on: .basket)), .report(found)])
  }

  @Test func theTimeAndTriesAreBounded() {
    var state = Self.hunting()
    let spots = MischiefSpot.allCases.filter { $0 != .basket }
    for spot in spots { state = M.transition(state, .look(spot, warmth: .cold, at: Self.start)).0 }
    let late = Self.start.addingTimeInterval(10 * 86_400)
    let (next, _) = M.transition(state, .look(.basket, warmth: .hot, at: late))
    guard case .found(let found) = next else {
      Issue.record("not found")
      return
    }
    #expect(found.seconds == 86_400)
    #expect(found.tries == spots.count + 1)
  }

  @Test func lookingTwiceAtTheSameSpotIsIgnored() {
    let state = Self.hunting(misses: [(.sill, .cold)])
    #expect(M.transition(state, .look(.sill, warmth: .cold, at: Self.start)) == (state, []))
  }

  @Test(arguments: [M.State.idle, MischiefHuntMachineTests.found])
  func lookingWithoutAHuntIsRejected(state: M.State) {
    #expect(M.transition(state, .look(.sill, warmth: .cold, at: Self.start)) == (state, []))
  }

  @Test func leavingEndsTheHuntAndNothingIsLost() {
    let (next, outputs) = M.transition(Self.hunting(misses: [(.sill, .cold)]), .leave)
    #expect(next == .idle && outputs.isEmpty)
  }

  @Test(arguments: [M.State.idle, MischiefHuntMachineTests.found])
  func leavingWithoutAHuntIsRejected(state: M.State) {
    #expect(M.transition(state, .leave) == (state, []))
  }

  @Test func dismissingAFindGoesIdle() {
    #expect(M.transition(Self.found, .dismissed) == (.idle, []))
  }

  @Test(arguments: [M.State.idle, MischiefHuntMachineTests.hunting()])
  func dismissingWithoutAFindIsRejected(state: M.State) {
    #expect(M.transition(state, .dismissed) == (state, []))
  }

  @Test func theMouseEndingElsewhereStopsTheHunt() {
    #expect(M.transition(Self.hunting(), .hideEnded("h1")) == (.idle, []))
  }

  @Test func anotherMouseEndingChangesNothing() {
    let state = Self.hunting()
    #expect(M.transition(state, .hideEnded("h9")) == (state, []))
  }

  @Test(arguments: [M.State.idle, MischiefHuntMachineTests.found])
  func aHideEndingOutsideAHuntChangesNothing(state: M.State) {
    #expect(M.transition(state, .hideEnded("h1")) == (state, []))
  }
}
