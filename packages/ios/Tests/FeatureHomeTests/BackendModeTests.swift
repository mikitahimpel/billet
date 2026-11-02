import Foundation
import Persistence
import Testing

@testable import FeatureHome

@Suite struct BackendModeTests {
  @Test func demoIsTheDefault() {
    #expect(BackendMode(info: nil) == .demo)
    #expect(BackendMode(info: [:]) == .demo)
    #expect(BackendMode(backend: "", baseURL: "") == .demo)
  }

  @Test func realNeedsAUsableURL() throws {
    #expect(
      BackendMode(backend: "real", baseURL: "https://api.example")
        == .real(baseURL: try #require(URL(string: "https://api.example"))))
    #expect(BackendMode(backend: "real", baseURL: "") == .demo)
    #expect(BackendMode(backend: "real", baseURL: nil) == .demo)
    #expect(BackendMode(backend: "real", baseURL: "ftp://api.example") == .demo)
    #expect(BackendMode(backend: "real", baseURL: "not a url") == .demo)
  }

  @Test func aTypoDoesNotSwitchToTheRealClient() {
    #expect(BackendMode(backend: "Real", baseURL: "https://api.example") == .demo)
    #expect(BackendMode(backend: "demo", baseURL: "https://api.example") == .demo)
  }

  @Test func theStageFollowsWhatIsSaved() {
    let record = AccountRecord(userID: "u", deviceID: "d", expiresAt: 1)
    #expect(RealStage(nil) == .signedOut)
    #expect(RealStage(("t", record)) == .unpaired)
    var paired = record
    paired.isPaired = true
    #expect(RealStage(("t", paired)) == .paired)
  }
}
