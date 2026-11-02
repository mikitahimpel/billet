import Testing

@testable import FeatureSettings

@MainActor
@Suite struct LogOutWarningTests {
  @Test func aFakePartnerRunHasNoPairCodeToForget() {
    #expect(!SettingsView.logOutWarning(isFakePartner: true).contains("code"))
  }

  @Test func aRealPairIsToldAboutTheCode() {
    #expect(SettingsView.logOutWarning(isFakePartner: false).contains("new code"))
  }
}
