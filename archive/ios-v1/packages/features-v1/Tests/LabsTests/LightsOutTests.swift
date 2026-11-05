import Foundation
import Testing

@testable import Labs

@Suite struct LightsOutTests {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func theCatCurlsUpOnlyWhenBothLampsAreOut() {
    #expect(LightsOut.night(mineOut: false, theirsOut: false) == .awake)
    #expect(LightsOut.night(mineOut: true, theirsOut: false) == .waitingOnThem)
    #expect(LightsOut.night(mineOut: false, theirsOut: true) == .waitingOnMe)
    #expect(LightsOut.night(mineOut: true, theirsOut: true) == .asleep)
  }

  @Test func aLampStaysOutForNineHoursThenComesOnByItself() {
    let goodnight = start
    #expect(LightsOut.isOut(since: goodnight, now: start.addingTimeInterval(60)))
    #expect(LightsOut.isOut(since: goodnight, now: start.addingTimeInterval(LightsOut.lasts - 1)))
    #expect(!LightsOut.isOut(since: goodnight, now: start.addingTimeInterval(LightsOut.lasts)))
  }

  @Test func aLampNeverSaidGoodnightToIsOn() {
    #expect(!LightsOut.isOut(since: nil, now: start))
  }

  @Test func aGoodnightInTheFutureIsNotYetOut() {
    #expect(!LightsOut.isOut(since: start.addingTimeInterval(10), now: start))
  }

  @MainActor @Test func theStoreKeepsGoodnightAndWakesUp() {
    let defaults = UserDefaults(suiteName: "lights-\(UUID().uuidString)") ?? .standard
    let store = LampStore(defaults: defaults)
    #expect(!store.mineOut(at: start))
    store.sayGoodnight(at: start)
    #expect(LampStore(defaults: defaults).mineOut(at: start.addingTimeInterval(5)))
    store.wakeUp()
    #expect(!LampStore(defaults: defaults).mineOut(at: start.addingTimeInterval(5)))
  }

  @MainActor @Test func thePartnersGoodnightComesFromTheirGlow() {
    let store = LampStore(
      defaults: UserDefaults(suiteName: "lights-\(UUID().uuidString)") ?? .standard)
    #expect(!store.theirsOut)
    store.partnerGlows(PartnerGlow(colour: .rose, lampOn: false))
    #expect(store.theirsOut)
    #expect(store.night(at: start) == .waitingOnMe)
    store.sayGoodnight(at: start)
    #expect(store.night(at: start) == .asleep)
  }
}
