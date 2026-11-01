import Foundation
import Pet
import Testing

@testable import Labs

@Suite struct PorchLightTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    return calendar
  }

  private func date(_ day: Int, _ hour: Int = 20) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)) ?? .now
  }

  @Test func itCoversTheNightsFromTheDayItWasLit() {
    let light = PorchLight(from: date(2), nights: 2, calendar: calendar)
    #expect(light.covered(calendar: calendar) == ["2026-11-02", "2026-11-03"])
  }

  @Test func itNeverCoversMoreThanThreeNights() {
    #expect(PorchLight(from: date(2), nights: 30, calendar: calendar).nights == PorchLight.longest)
    #expect(PorchLight(from: date(2), nights: 0, calendar: calendar).nights == 1)
  }

  @Test func itGoesOutTheMorningAfterTheLastNight() {
    let light = PorchLight(from: date(2), nights: 2, calendar: calendar)
    #expect(light.isOn(at: date(3, 23), calendar: calendar))
    #expect(!light.isOn(at: date(4, 0), calendar: calendar))
  }

  @Test func theLastNightLetsTheStreakReachBackAcrossIt() {
    var ledger = TreatLedger()
    ledger.give(device: "a", on: "2026-10-31")
    ledger.give(device: "b", on: "2026-10-31")
    let light = PorchLight(from: date(1), nights: 2, calendar: calendar)
    #expect(
      ledger.streak(
        today: "2026-11-03", calendar: calendar, paused: light.covered(calendar: calendar)) == 1)
    ledger.give(device: "a", on: "2026-11-03")
    ledger.give(device: "b", on: "2026-11-03")
    #expect(
      ledger.streak(
        today: "2026-11-03", calendar: calendar, paused: light.covered(calendar: calendar)) == 2)
  }

  @MainActor @Test func theStoreKeepsTheLightAndPutsItOut() {
    let defaults = UserDefaults(suiteName: "porch-\(UUID().uuidString)") ?? .standard
    let store = PorchLightStore(defaults: defaults)
    #expect(store.covered(now: date(2), calendar: calendar).isEmpty)
    store.leaveOn(nights: 3, now: date(2), calendar: calendar)
    #expect(PorchLightStore(defaults: defaults).light?.nights == 3)
    #expect(store.covered(now: date(2), calendar: calendar).count == 3)
    store.switchOff()
    #expect(PorchLightStore(defaults: defaults).light == nil)
  }
}
