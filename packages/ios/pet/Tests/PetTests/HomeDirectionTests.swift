import Foundation
import Testing

@testable import Pet

@Suite struct DayLightTests {
  @Test(arguments: [
    (3.0, DayLight.Phase.night), (5.0, .morning), (9.9, .morning), (10.0, .day), (16.5, .day),
    (17.0, .goldenHour), (20.9, .goldenHour), (21.0, .night), (23.9, .night),
  ])
  func eachHourHasItsPhase(_ hour: Double, _ phase: DayLight.Phase) {
    #expect(DayLight.at(hour: hour).phase == phase)
  }

  @Test func pretendingAnHourMovesEveryZoneTogether() throws {
    let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let noon = try #require(ISO8601DateFormatter().date(from: "2026-11-02T11:30:00Z"))
    let night = DayLight.pretending(noon, hour: 23, in: berlin)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = berlin
    #expect(calendar.component(.hour, from: night) == 23)
    #expect(calendar.component(.minute, from: night) == 30)
    #expect(DayLight.at(night, in: berlin).phase == .night)
    #expect(DayLight.at(night, in: tokyo).phase == .morning)
    #expect(DayLight.pretending(noon, hour: nil, in: berlin) == noon)
  }

  @Test func theSunPeaksAroundNoonAndIsGoneAtNight() {
    #expect(DayLight.at(hour: 2).sun == 0)
    #expect(DayLight.at(hour: 23).sun == 0)
    #expect(DayLight.at(hour: 13).sun > 0.99)
    #expect(DayLight.at(hour: 8).sun < DayLight.at(hour: 12).sun)
  }

  @Test func aLowSunIsWarmerThanTheMiddayOne() {
    #expect(DayLight.at(hour: 19).warmth > DayLight.at(hour: 13).warmth)
    #expect(DayLight.at(hour: 7).warmth > DayLight.at(hour: 13).warmth)
  }

  @Test func theLampIsOnFromGoldenHourUntilMorning() {
    #expect(DayLight.at(hour: 22).lampOn)
    #expect(DayLight.at(hour: 18).lampOn)
    #expect(!DayLight.at(hour: 12).lampOn)
    #expect(!DayLight.at(hour: 7).lampOn)
  }

  @Test func aTimeZoneMovesTheHour() throws {
    let noonInLondon = try #require(
      ISO8601DateFormatter().date(from: "2026-06-01T11:00:00Z"))
    let london = try #require(TimeZone(identifier: "Europe/London"))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    #expect(DayLight.at(noonInLondon, in: london).phase == .day)
    #expect(DayLight.at(noonInLondon, in: tokyo).phase == .goldenHour)
  }
}

@MainActor
@Suite struct CatDirectorTests {
  @Test func nothingIsSentAtFirst() {
    #expect(CatDirector().latest == nil)
  }

  @Test func theSameCueTwiceReadsAsNew() {
    let director = CatDirector()
    director.send(.lookAtCamera)
    let first = director.latest
    director.send(.lookAtCamera)
    #expect(director.latest?.cue == .lookAtCamera)
    #expect(director.latest != first)
  }
}
