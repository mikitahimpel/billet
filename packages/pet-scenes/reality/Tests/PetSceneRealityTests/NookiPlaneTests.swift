import Foundation
import Testing
import simd

@testable import PetSceneReality

@Suite struct NookiPlaneTests {
  private static let cat = SIMD3<Float>(0.05, 0.5, 0.12)
  private static let deliveryLength = 9.0
  /// When the delivery's own timeline has the cat back in bed.
  private static let timelineEnds = 7.8

  @Test func untouchedCatCatchesItAfterAFewSeconds() {
    let flight = NookiPlaneFlight()
    #expect(!flight.isCaught(at: 2.3))
    #expect(flight.isCaught(at: NookiPlaneFlight.catCatchesAt))
    #expect(NookiPlaneFlight.catCatchesAt >= 2)
  }

  @Test func aTapCatchesItSoon() {
    var flight = NookiPlaneFlight()
    flight.tap(at: 1)
    #expect(!flight.isCaught(at: 1.2))
    #expect(flight.isCaught(at: 1 + NookiPlaneFlight.swoopLength))
  }

  @Test func aTapAfterTheCatchChangesNothing() {
    var flight = NookiPlaneFlight()
    flight.tap(at: 3)
    #expect(flight == NookiPlaneFlight())
  }

  @Test func theFirstTapCounts() {
    var flight = NookiPlaneFlight()
    flight.tap(at: 0.5)
    flight.tap(at: 0.6)
    #expect(flight.tappedAt == 0.5)
  }

  @Test(arguments: [nil, 0.0, 1.0, 2.0] as [Double?])
  func everyCatchFinishesInsideTheDelivery(tappedAt: Double?) {
    var flight = NookiPlaneFlight()
    if let tappedAt { flight.tap(at: tappedAt) }
    #expect(flight.choreographyTime(Self.deliveryLength) >= Self.timelineEnds)
  }

  @Test func theTimelineWaitsDuringTheFlightAndPicksUpAtTheCatch() {
    let flight = NookiPlaneFlight()
    #expect(flight.choreographyTime(2) == flight.choreographyTime(2.3))
    #expect(flight.choreographyTime(3) > flight.choreographyTime(2.4))
  }

  @Test func theTimelineNeverJumpsBackward() {
    var flight = NookiPlaneFlight()
    flight.tap(at: 0.8)
    var last = 0.0
    for tick in 0..<540 {
      let time = flight.choreographyTime(Double(tick) / 60)
      #expect(time >= last)
      last = time
    }
  }

  @Test func thePlaneStartsOutsideAndEndsInTheRoom() {
    let flight = NookiPlaneFlight()
    #expect(flight.pose(at: 0, cat: Self.cat).position.x > 0.7)
    let end = flight.pose(at: NookiPlaneFlight.catCatchesAt, cat: Self.cat).position
    #expect(simd_distance(end, Self.cat) < 0.1)
  }

  @Test func theFlightHasNoJumps() {
    let flight = NookiPlaneFlight()
    var last = flight.pose(at: 0, cat: Self.cat).position
    for tick in 1..<144 {
      let next = flight.pose(at: Double(tick) / 60, cat: Self.cat).position
      #expect(simd_distance(next, last) < 0.05)
      #expect(next.x.isFinite && next.y.isFinite && next.z.isFinite)
      last = next
    }
  }

  @Test func aTappedPlaneSwoopsToCat() {
    var flight = NookiPlaneFlight()
    flight.tap(at: 1)
    let end = flight.pose(at: 1 + NookiPlaneFlight.swoopLength, cat: Self.cat).position
    #expect(simd_distance(end, Self.cat) < 0.001)
  }

  @Test func catLeapsOnlyForAPlaneNobodyTapped() {
    var flight = NookiPlaneFlight()
    #expect(flight.leap(2.2) > 0)
    #expect(flight.leap(1) == 0)
    flight.tap(at: 1)
    #expect(flight.leap(2.2) == 0)
  }
}
