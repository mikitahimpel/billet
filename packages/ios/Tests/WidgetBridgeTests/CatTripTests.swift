import Foundation
import Testing

@testable import WidgetBridge

@Suite struct CatTripTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func durationIsTheRevealPlusTheWalkWithinBounds() {
    #expect(CatTrip.expectedDuration(reveal: .seconds(3)) == 7)
    #expect(CatTrip.expectedDuration(reveal: .milliseconds(500)) == 6)
    #expect(CatTrip.expectedDuration(reveal: .seconds(60)) == 20)
  }

  @Test func aTripBeginsOnItsWayAndEndsHung() {
    let begun = CatTrip.begin(at: now, duration: 10)
    #expect(begun.phase == .onItsWay && !begun.hearted)
    #expect(begun.arrivesAt == now.addingTimeInterval(10))
    let early = CatTrip.hung(begun, at: now.addingTimeInterval(4))
    #expect(early.phase == .hung && early.arrivesAt == now.addingTimeInterval(4))
    let late = CatTrip.hung(begun, at: now.addingTimeInterval(40))
    #expect(late.arrivesAt == begun.arrivesAt)
  }

  @Test func aHeartIsRemembered() {
    let begun = CatTrip.begin(at: now, duration: 10)
    #expect(CatTrip.hearted(begun).hearted)
    #expect(CatTrip.hearted(begun).phase == begun.phase)
  }

  @Test func contentSurvivesTheJSONAPushWouldCarry() throws {
    let content = CatTrip.begin(at: now, duration: 10)
    let data = try JSONEncoder().encode(content)
    #expect(try JSONDecoder().decode(CatTrip.Content.self, from: data) == content)
  }
}
