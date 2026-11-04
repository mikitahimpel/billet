import SwiftUI
import Testing

@testable import FeatureSettings

@MainActor
@Suite struct UnpairWarningTests {
  @Test func aFakePartnerRunHasNoPairCodeToForget() {
    #expect(!UsView<EmptyView>.unpairWarning(isFakePartner: true).contains("code"))
  }

  @Test func aRealPairIsToldAboutTheCode() {
    #expect(UsView<EmptyView>.unpairWarning(isFakePartner: false).contains("new code"))
  }
}
