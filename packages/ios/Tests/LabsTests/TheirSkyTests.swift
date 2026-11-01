import Foundation
import Testing

@testable import Labs

@Suite struct TheirSkyTests {
  @Test func everyHourHasOneSkyAndTheDayIsCovered() {
    let skies = (0..<24).map(TheirSky.at(hour:))
    #expect(skies.count == 24)
    #expect(Set(skies) == Set(TheirSky.allCases))
  }

  @Test func theBoundariesFallWhereTheyAreSaid() {
    #expect(TheirSky.at(hour: 4) == .night)
    #expect(TheirSky.at(hour: 5) == .dawn)
    #expect(TheirSky.at(hour: 7) == .dawn)
    #expect(TheirSky.at(hour: 8) == .day)
    #expect(TheirSky.at(hour: 17) == .day)
    #expect(TheirSky.at(hour: 18) == .dusk)
    #expect(TheirSky.at(hour: 20) == .dusk)
    #expect(TheirSky.at(hour: 21) == .night)
    #expect(TheirSky.at(hour: 0) == .night)
  }

  @Test func theSameMomentIsADifferentSkyInAnotherZone() {
    // 12:00 UTC on 2 November 2026: noon in London, evening in Tokyo, 7 in the morning in New York.
    let noon = Date(timeIntervalSince1970: 1_793_620_800)
    #expect(TheirSky.over(timeZoneID: "Europe/London", at: noon) == .day)
    #expect(TheirSky.over(timeZoneID: "Asia/Tokyo", at: noon) == .night)
    #expect(TheirSky.over(timeZoneID: "America/New_York", at: noon) == .dawn)
    #expect(TheirSky.over(timeZoneID: "Pacific/Auckland", at: noon) == .night)
  }

  @Test func anUnknownZoneGivesNoSky() {
    #expect(TheirSky.over(timeZoneID: "Mars/Olympus", at: .now) == nil)
    #expect(TheirSky.over(timeZoneID: "", at: .now) == nil)
  }

  @Test func eachSkyHasWordsAndColours() {
    for sky in TheirSky.allCases {
      #expect(!sky.title.isEmpty)
      #expect(sky.colours.top != sky.colours.bottom)
    }
  }
}
