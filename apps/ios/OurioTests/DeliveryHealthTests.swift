import Foundation
import Testing
import UsInterface
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

    @Test func the_delivery_rows_are_the_same_three_before_and_after_the_check() {
        let checking = DeliveryHealth.checking.all
        let checked = health(allowed: false).lines.all
        #expect(checking.count == 3)
        #expect(checking.map(\.title) == checked.map(\.title))
        #expect(checking.allSatisfy { $0.detail == "Checking…" })
        #expect(checked.map(\.detail) == [health(allowed: false).pushDetail, "None yet", "None on your Home Screen"])
    }

    @Test func the_notifications_row_is_calm_when_pushes_work_and_warns_when_they_do_not() {
        #expect(health().lines.notifications.tint == .sage)
        #expect(health().lines.notifications.symbol == "bell.badge.fill")
        #expect(health(allowed: false).lines.notifications.tint == .coral)
        #expect(health(token: false).lines.notifications.symbol == "bell.slash.fill")
    }

    @Test func names_the_partner_only_while_alerts_are_off() {
        #expect(health(allowed: false).notice(partner: "Ilya") == "You won't hear when Ilya sends something.")
        #expect(health().notice(partner: "Ilya") == nil)
        #expect(health(token: false).notice(partner: "Ilya") == nil)
    }
}
