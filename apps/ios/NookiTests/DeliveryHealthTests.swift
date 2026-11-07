import Foundation
import Testing
@testable import Billet

@Suite struct DeliveryHealthTests {
    private func health(allowed: Bool = true, token: Bool = true, widgets: Int = 0) -> DeliveryHealth {
        DeliveryHealth(notificationsAllowed: allowed, hasPushToken: token, lastPush: nil, widgetCount: widgets)
    }

    @Test func fails_when_notifications_are_off() {
        let off = health(allowed: false)
        #expect(!off.pushesWork)
        #expect(off.pushDetail.hasPrefix("Off"))
    }

    @Test func fails_without_a_push_token() {
        #expect(!health(token: false).pushesWork)
    }

    @Test func works_with_permission_and_token() {
        let on = health()
        #expect(on.pushesWork)
        #expect(on.pushDetail == "On")
    }

    @Test func says_when_no_push_has_arrived_and_how_many_widgets_there_are() {
        #expect(health().lastPushDetail == "None yet")
        #expect(health(widgets: 0).widgetDetail == "None on your Home Screen")
        #expect(health(widgets: 1).widgetDetail == "1 on your Home Screen")
        #expect(health(widgets: 3).widgetDetail == "3 on your Home Screen")
    }

    @Test func remembers_the_last_push() {
        let value = health()
        var withPush = value
        withPush.lastPush = .now
        #expect(withPush.lastPushDetail != "None yet")
    }
}
