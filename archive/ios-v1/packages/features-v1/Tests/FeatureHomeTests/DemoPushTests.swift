import Testing
import UserNotifications

@testable import FeatureHome

@Suite struct DemoPushTests {
  @Test func launchRegistersOnlyForSomeoneWhoSaidYes() {
    #expect(DemoPush.isAllowed(.authorized))
    #expect(DemoPush.isAllowed(.provisional))
    #expect(!DemoPush.isAllowed(.notDetermined))
    #expect(!DemoPush.isAllowed(.denied))
  }
}
