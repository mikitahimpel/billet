import Foundation
import Pet
import Testing

@testable import Labs

@MainActor
@Suite struct PetLifeModelTests {
  private static let start = Date(timeIntervalSince1970: 1_793_620_800)

  private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_793_620_800)
  }

  private func model(
    _ me: String, clock: Clock, defaults: UserDefaults? = nil, partner: String? = nil
  ) -> PetLifeModel {
    let defaults = defaults ?? UserDefaults(suiteName: "life-\(UUID().uuidString)") ?? .standard
    return PetLifeModel(
      me: me, fallbackPartner: partner, defaults: defaults, clock: { clock.now })
  }

  @Test func twoPhonesHoldingTheSameEventsShowTheSameCat() {
    let clock = Clock()
    let a = model("a", clock: clock)
    let b = model("b", clock: clock)
    let fed = a.record(.feed)
    clock.now += 600
    let petted = b.record(.pet)
    clock.now += 600
    let noted = a.record(.note)
    // Each phone hears of the other's events later, and some twice.
    b.receive([noted, fed])
    a.receive([petted, petted])
    clock.now += 3600
    a.refresh()
    b.refresh()
    #expect(a.state == b.state)
    #expect(a.state.love.keys.sorted() == ["a", "b"])
  }

  @Test func eventsOutlastALaunch() {
    let clock = Clock()
    let defaults = UserDefaults(suiteName: "life-\(UUID().uuidString)") ?? .standard
    let first = model("a", clock: clock, defaults: defaults)
    first.record(.feed)
    let again = model("a", clock: clock, defaults: defaults)
    #expect(again.log == first.log)
  }

  @Test func theFakePartnerCountsBeforeItHasDoneAnything() {
    let clock = Clock()
    let alone = model("a", clock: clock, partner: "fake-partner")
    #expect(Set(alone.state.love.keys) == ["a", "fake-partner"])
    alone.receive([LifeEvent(kind: .pet, by: "fake-partner", at: clock.now)])
    #expect(alone.state.love["fake-partner", default: 0] > alone.state.love["a", default: 1])
  }

  @Test func theFastClockRunsAheadAndItsEventsStayApart() {
    let clock = Clock()
    let life = model("a", clock: clock)
    life.record(.feed)
    let fedNow = life.state.needs.full
    life.setSpeed(600)
    clock.now += 60
    #expect(abs(life.now.timeIntervalSince(Self.start) - 60 * 600) < 1)
    life.refresh()
    #expect(life.state.needs.full < fedNow - 0.3)
    life.debug(.feed, asPartner: false)
    #expect(life.debugEvents.count == 1)
    #expect(life.log.events.count == 1)
    life.setSpeed(1)
    #expect(life.debugEvents.isEmpty)
    #expect(abs(life.now.timeIntervalSince(clock.now)) < 1)
  }

  @Test func whileTimeIsFrozenNothingFalls() {
    let clock = Clock()
    let life = model("a", clock: clock)
    life.record(.feed)
    let fed = life.state.needs.full
    life.frozen = { [DateInterval(start: Self.start, duration: 86400)] }
    clock.now += 12 * 3600
    life.refresh()
    #expect(abs(life.state.needs.full - fed) < 1e-6)
  }
}
