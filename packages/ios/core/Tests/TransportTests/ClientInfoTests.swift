import Foundation
import Testing

@testable import Transport

@Suite struct ClientInfoTests {
  static let system = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)

  @Test func joinsTheMarketingVersionAndTheBuild() {
    let info = ClientInfo(
      info: ["CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "14"], system: Self.system)
    #expect(info.appVersion == "1.2.0+14")
    #expect(info.os == "iOS 26.1")
    #expect(
      info.headers == [
        Routes.appVersionHeader: "1.2.0+14", Routes.osHeader: "iOS 26.1",
      ])
  }

  @Test func keepsAPatchVersion() {
    let system = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 2)
    #expect(ClientInfo(info: [:], system: system).os == "iOS 26.0.2")
  }

  @Test func leavesOutAMissingVersion() {
    let info = ClientInfo(info: [:], system: Self.system)
    #expect(info.appVersion == nil)
    #expect(info.headers == [Routes.osHeader: "iOS 26.1"])
  }

  /// The server accepts only `^\d+(\.\d+)*(\+\d+)?$` and `iOS <version>`, so a value the server
  /// would read as unknown would show up here first.
  @Test func matchesTheShapesTheServerAccepts() throws {
    let info = ClientInfo(
      info: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "12"], system: Self.system)
    #expect(
      try #/^\d{1,4}(\.\d{1,4}){0,3}(\+\d{1,8})?$/#.wholeMatch(in: info.appVersion ?? "") != nil)
    #expect(try #/^iOS \d{1,3}(\.\d{1,3}){0,2}$/#.wholeMatch(in: info.os) != nil)
  }
}
