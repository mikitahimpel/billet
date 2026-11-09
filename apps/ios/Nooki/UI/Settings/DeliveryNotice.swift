import Design
import OurioShared
import SwiftUI

/// One calm row while this phone's alerts are off, so a partner's note is never missed without a word; nothing
/// otherwise. Checked again each time the app comes back, which is when someone returns from Settings.
struct DeliveryNotice: View {
    let partner: String
    /// Around the row only while it shows, so a hidden notice takes no room.
    var insets = EdgeInsets()

    @Environment(\.scenePhase) private var scenePhase
    @State private var line: String?

    var body: some View {
        // A stack rather than a Group: it stays in the tree with nothing in it, so the check below still runs.
        VStack(spacing: 0) {
            if let line {
                Button {
                    Task {
                        await DeliveryHealth.turnOn()
                        self.line = await DeliveryHealth.check().notice(partner: partner)
                    }
                } label: {
                    Row("Turn on notifications", detail: line, symbol: "bell.badge.fill", tint: UsTint.honey.color) {
                        RowChevron()
                    }
                }
                .buttonStyle(PressScaleStyle())
                .cardSurface()
                .transition(.opacity)
                .accessibilityIdentifier("deliveryNotice")
                .padding(insets)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            let next = await DeliveryHealth.check().notice(partner: partner)
            withAnimation(Motion.fade()) { line = next }
        }
    }
}
