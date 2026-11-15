import Design
import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import UIKit
import UsInterface

struct DeliveryHealthSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var report = Report.checking

    private enum Report: Equatable {
        case checking
        case checked(DeliveryHealth)
    }

    private var lines: DeliveryHealth.Lines {
        switch report {
        case .checking: DeliveryHealth.checking
        case .checked(let health): health.lines
        }
    }

    /// Only the system's Settings turns alerts back on, so the row opens it once they are known to be off.
    private var opensSettings: Bool {
        switch report {
        case .checking: false
        case .checked(let health): !health.notificationsAllowed
        }
    }

    private var footer: String {
        switch report {
        case .checked(let health) where !health.pushesWork:
            "Turn notifications on so you hear when your partner sends something."
        case .checking, .checked:
            "Checked each time you open Settings."
        }
    }

    var body: some View {
        GroupedSection(header: "Delivery", footer: footer) {
            Button(action: openSystemSettings) {
                row(lines.notifications) {
                    if opensSettings {
                        RowChevron()
                    } else if report == .checking {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!opensSettings)
            row(lines.lastPush) {}
            row(lines.widgets) {}
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            report = .checked(await DeliveryHealth.check())
        }
    }

    private func row<Trailing: View>(
        _ line: DeliveryHealth.Line, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Row(line.title, detail: line.detail, symbol: line.symbol, tint: line.tint.color, trailing: trailing)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
