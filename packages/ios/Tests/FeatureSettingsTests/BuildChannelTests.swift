import StoreKit
import Testing

@testable import FeatureSettings

@Suite struct BuildChannelTests {
  @Test func testFlightAndXcodeBuildsShowLabs() {
    #expect(BuildChannel.isForTesting(environment: .sandbox))
    #expect(BuildChannel.isForTesting(environment: .xcode))
  }

  @Test func aStoreKitFailureStillShowsLabs() {
    #expect(BuildChannel.isForTesting(environment: nil))
  }

  @Test func theAppStoreHidesLabs() {
    #expect(!BuildChannel.isForTesting(environment: .production))
  }
}
