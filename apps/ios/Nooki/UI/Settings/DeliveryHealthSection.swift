import Design
import OurioShared
import SwiftUI
import UIKit

struct DeliveryHealthSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var health: DeliveryHealth?

    var body: some View {
        GroupedSection(header: "Delivery",
                       footer: health?.pushesWork == false
                           ? "Turn notifications on so you hear when your partner sends something."
                           : "Checked each time you open Settings.") {
            if let health {
                Button(action: openSystemSettings) {
                    Row("Notifications", detail: health.pushDetail,
                        symbol: health.pushesWork ? "bell.badge.fill" : "bell.slash.fill",
                        tint: (health.pushesWork ? UsTint.sage : UsTint.coral).color) {
                        if !health.notificationsAllowed { RowChevron() }
                    }
                }
                .buttonStyle(PressScaleStyle())
                .disabled(health.notificationsAllowed)
                Row("Last push", detail: health.lastPushDetail, symbol: "paperplane.fill",
                    tint: UsTint.sky.color)
                Row("Widgets", detail: health.widgetDetail, symbol: "rectangle.on.rectangle.fill",
                    tint: UsTint.lilac.color)
            } else {
                Row("Checking…", symbol: "stethoscope", tint: UsTint.sky.color) { ProgressView() }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            health = await DeliveryHealth.check()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
