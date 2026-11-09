import Foundation
import Testing

@testable import Wire

@Suite struct ServiceStatusWireTests {
  private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }

  private func version(_ text: String) throws -> AppVersion {
    try #require(AppVersion(text))
  }

  // MARK: decoding

  @Test func theMaintenanceGoldenDecodesInFull() throws {
    let url = fixturesDirectory.appending(path: "StatusResponse/maintenance.json")
    let status = try JSONDecoder().decode(StatusResponse.self, from: Data(contentsOf: url)).status
    #expect(status.maintenance.active)
    #expect(
      status.maintenance.message
        == StatusMessage(key: "maintenance.default", text: "billet is resting for a little while."))
    #expect(status.maintenance.untilDate == Date(timeIntervalSince1970: 1_793_745_000))
    #expect(status.minVersion == AppVersion("1.0"))
    #expect(status.notice == nil)
  }

  @Test func theUpdateAndNoticeGoldenDecodesInFull() throws {
    let url = fixturesDirectory.appending(path: "StatusResponse/update-and-notice.json")
    let status = try JSONDecoder().decode(StatusResponse.self, from: Data(contentsOf: url)).status
    #expect(!status.maintenance.active)
    #expect(status.minVersion?.parts == [1, 2, 0])
    #expect(status.minVersion?.build == 14)
    #expect(status.notice?.key == "notice.slow-notes")
  }

  @Test func theFlagsAnswerCarriesTheStatusWhenSent() throws {
    let url = fixturesDirectory.appending(path: "FlagsResponse/with-status.json")
    let flags = try JSONDecoder().decode(FlagsResponse.self, from: Data(contentsOf: url))
    #expect(flags.status?.maintenance.active == true)
    #expect(try decode(FlagsResponse.self, #"{"flags":[]}"#).status == nil)
  }

  @Test func fieldsThisClientDoesNotKnowAreIgnored() throws {
    let status = try decode(
      StatusResponse.self,
      #"{"status":{"maintenance":{"active":false,"reason":"x"},"banner":{"a":1}},"etag":"1"}"#)
    #expect(status.status == .normal)
  }

  @Test(arguments: [
    "2026-11-03T22:30Z", "2026-11-03T22:30:00Z", "2026-11-03T22:30:00.5Z",
    "2026-11-03T22:30:00.500Z",
  ])
  func untilTakesTheContractsForms(_ until: String) throws {
    let maintenance = try decode(
      MaintenanceStatus.self, #"{"active":true,"until":"\#(until)"}"#)
    let date = try #require(maintenance.untilDate)
    #expect(abs(date.timeIntervalSince1970 - 1_793_745_000) < 1)
  }

  @Test func fractionsOfASecondAreKept() throws {
    let date = try #require(MaintenanceStatus.instant("2026-11-03T22:30:00.25Z"))
    #expect(abs(date.timeIntervalSince1970 - 1_793_745_000.25) < 0.001)
  }

  @Test(arguments: [
    "", "tomorrow", "2026-11-03", "2026-11-03T22:30:00", "2026-11-03T22:30:00+01:00",
    "2026-13-03T22:30Z", "2026-02-30T22:30Z", "2026-11-03T24:00Z", "2026-11-03T22:30:00.1234Z",
  ])
  func anUntilThatIsNotAUTCInstantIsRejected(_ until: String) {
    #expect(throws: DecodingError.self) {
      try decode(MaintenanceStatus.self, #"{"active":true,"until":"\#(until)"}"#)
    }
  }

  @Test(arguments: [
    #"{"key":"","text":"a"}"#, #"{"key":"a","text":""}"#, #"{"key":"a"}"#,
  ])
  func aMessageNeedsAKeyAndText(_ json: String) {
    #expect(throws: DecodingError.self) { try decode(StatusMessage.self, json) }
  }

  @Test func maintenanceNeedsItsSwitch() {
    #expect(throws: DecodingError.self) { try decode(AppStatus.self, #"{"notice":null}"#) }
  }

  @Test(arguments: ["", "v1", "1.2.3.4.5", "1..2", "1.2+", "+3", "12345", "1.2+123456789"])
  func aMinVersionThatIsNotAVersionIsRejected(_ minVersion: String) {
    #expect(throws: DecodingError.self) {
      try decode(
        AppStatus.self, #"{"maintenance":{"active":false},"minVersion":"\#(minVersion)"}"#)
    }
  }

  @Test func aMaintenanceResponseMustSayMaintenance() {
    #expect(throws: DecodingError.self) {
      try decode(
        MaintenanceResponse.self, #"{"error":"busy","status":{"maintenance":{"active":true}}}"#)
    }
  }

  // MARK: versions

  @Test func missingPartsCountAsZero() throws {
    #expect(try version("1.2").compare(version("1.2.0")) == .orderedSame)
    #expect(try version("1").compare(version("1.0.0.0")) == .orderedSame)
    #expect(try version("1.2").compare(version("1.2.1")) == .orderedAscending)
  }

  @Test func partsCompareAsNumbersNotText() throws {
    #expect(try version("1.10").compare(version("1.9")) == .orderedDescending)
    #expect(try version("0.9.12").isOlder(than: version("0.10")))
    #expect(try version("01.2").compare(version("1.2")) == .orderedSame)
  }

  @Test func theBuildCountsOnlyWhenBothHaveOne() throws {
    #expect(try version("1.2.0+13").isOlder(than: version("1.2.0+14")))
    #expect(try !version("1.2.0+15").isOlder(than: version("1.2.0+14")))
    #expect(try version("1.2.0+3").compare(version("1.2")) == .orderedSame)
    #expect(try version("1.2").compare(version("1.2+99")) == .orderedSame)
    #expect(try !version("1.3+1").isOlder(than: version("1.2+99")))
  }

  @Test func aVersionEncodesAsItCame() throws {
    let encoded = try JSONEncoder().encode(version("1.2.0+14"))
    #expect(String(decoding: encoded, as: UTF8.self) == #""1.2.0+14""#)
  }
}
