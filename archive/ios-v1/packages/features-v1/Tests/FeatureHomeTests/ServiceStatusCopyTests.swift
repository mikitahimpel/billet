import Foundation
import Testing
import Wire

@testable import FeatureHome

@Suite struct ServiceStatusCopyTests {
  private static let until = Date(timeIntervalSince1970: 1_793_745_000)  // 2026-11-03 22:30 UTC
  private static let british = Locale(identifier: "en_GB")

  private static func zone(_ identifier: String) throws -> TimeZone {
    try #require(TimeZone(identifier: identifier))
  }

  @Test func untilIsShownInTheUsersTimeZone() throws {
    let now = Self.until.addingTimeInterval(-3_600)
    #expect(
      ServiceStatusCopy.backAround(
        Self.until, now: now, timeZone: try Self.zone("UTC"), locale: Self.british)
        == "Back around 22:30")
    #expect(
      ServiceStatusCopy.backAround(
        Self.until, now: now, timeZone: try Self.zone("Europe/Berlin"), locale: Self.british)
        == "Back around 23:30")
  }

  @Test func untilOnAnotherDayThereNamesTheDay() throws {
    let now = Self.until.addingTimeInterval(-12 * 3_600)
    let line = try #require(
      ServiceStatusCopy.backAround(
        Self.until, now: now, timeZone: try Self.zone("Asia/Tokyo"), locale: Self.british))
    #expect(line.hasPrefix("Back around Wednesday"))
    #expect(line.hasSuffix("7:30"))
  }

  @Test func noUntilOrOneAlreadyGoneSaysNothing() throws {
    let utc = try Self.zone("UTC")
    #expect(
      ServiceStatusCopy.backAround(nil, now: Self.until, timeZone: utc, locale: Self.british)
        == nil)
    #expect(
      ServiceStatusCopy.backAround(
        Self.until, now: Self.until.addingTimeInterval(60), timeZone: utc, locale: Self.british)
        == nil)
  }

  @Test func theAppsOwnStringWinsOverTheServersText() {
    let message = StatusMessage(key: "maintenance.default", text: "From the server.")
    #expect(
      ServiceStatusCopy.text(message, strings: { $0 == "maintenance.default" ? "Ours." : nil })
        == "Ours.")
    #expect(ServiceStatusCopy.text(message, strings: { _ in nil }) == "From the server.")
  }

  @Test func maintenanceWithoutAMessageRests() {
    #expect(
      ServiceStatusCopy.maintenanceMessage(
        MaintenanceStatus(active: true), strings: { _ in nil })
        == ServiceStatusCopy.restingMessage)
  }

  @Test func theUpdateLinkFallsBackToTestFlight() throws {
    #expect(UpdateLink(info: nil) == .testFlight)
    #expect(UpdateLink("") == .testFlight)
    #expect(UpdateLink("ftp://example.com/billet") == .testFlight)
    #expect(UpdateLink("not a link") == .testFlight)
    #expect(UpdateLink.testFlight.url?.scheme == "itms-beta")
    let store = try #require(URL(string: "itms-apps://apps.apple.com/app/id1"))
    #expect(UpdateLink(info: ["BilletUpdateURL": store.absoluteString]) == .url(store))
  }
}
