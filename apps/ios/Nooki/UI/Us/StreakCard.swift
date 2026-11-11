import MomentsInterface
import WidgetInterface
import WidgetUI
import ProfileInterface
import SwiftUI
import Design
import UsInterface

/// The top of Us: the couple's days together in one big number, and the love streak in a ring that fills toward its
/// next badge, with one line on what today needs.
struct StreakCard: View {
    let store: StreakStore
    let daysTogether: Int

    var body: some View {
        // Ticks each minute so the midnight rollover shows while the tab is open.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let streak = store.streak
        let status = streak.status(on: now)
        let days = streak.current(on: now)
        let next = streak.milestone(on: now).next

        return Card(warm: true) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .center, spacing: Space.m) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(daysTogether, format: .number)
                            .ourioScaledFont(size: 56, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                            .monospacedDigit()
                            .foregroundStyle(Ink.text)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        Text(daysTogether == 1 ? "day together" : "days together")
                            .font(.ourioHeadline)
                            .foregroundStyle(Ink.textSecondary)
                    }
                    Spacer(minLength: 0)
                    ProgressRing(value: next.map { Double(days) / Double($0) } ?? 1) {
                        VStack(spacing: 0) {
                            Flame(days: days, lit: status == .done)
                            Text(days, format: .number)
                                .font(.ourioTitle.monospacedDigit())
                                .foregroundStyle(Ink.text)
                                .contentTransition(.numericText())
                        }
                    }
                }
                line(status, days: days, next: next)
                    .fixedSize(horizontal: false, vertical: true)
                if status == .restorable {
                    Button {
                        Task { await store.restore() }
                    } label: {
                        Label("Restore \(streak.count)-day streak", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label(days: days, next: next))
        .animation(.snappy(duration: 0.3), value: days)
    }

    /// Its lead words in full ink, the rest quieter.
    private func line(_ status: LoveStreak.Status, days: Int, next: Int?) -> Text {
        let lead: String, rest: String
        switch status {
        case .done:
            lead = "Day \(days) is in."
            rest = next.map { " Badge at day \($0)." } ?? " See you tomorrow."
        case .atRisk:
            lead = "Keep the flame going."
            rest = " Pet \(CatProfile.name()) or leave a note today."
        case .restorable:
            lead = "You missed a day."
            rest = " You can bring the flame back once a month."
        case .cold:
            lead = "Light the flame."
            rest = " Do something together today."
        }
        return Text(lead).font(.ourioCallout.weight(.semibold)).foregroundStyle(Ink.text)
            + Text(rest).font(.ourioCallout).foregroundStyle(Ink.textSecondary)
    }

    private func label(days: Int, next: Int?) -> String {
        let together = daysTogether == 1 ? "1 day together" : "\(daysTogether) days together"
        let streak = days == 1 ? "1-day streak" : "\(days)-day streak"
        guard let next else { return "\(together). \(streak)." }
        let left = next - days
        return "\(together). \(streak), \(left) \(left == 1 ? "day" : "days") to the \(next)-day badge."
    }
}

// MARK: - Pieces

/// Flame that warms with the streak: orange, pink from 30 days, purple from 100. Fades while today doesn't count yet.
private struct Flame: View {
    let days: Int
    let lit: Bool

    private var colors: [Color] {
        if days == 0 { return [Color(hex: 0xBFB3AA), Color(hex: 0x8C7D72)] }
        if days >= 100 { return [Color(hex: 0xD9B8FF), Color(hex: 0x8A5CFF)] }
        if days >= 30 { return [Color(hex: 0xFFB3C4), Color(hex: 0xFF5C8A)] }
        return [Color(hex: 0xFFD27A), Color(hex: 0xFF6A3D)]
    }

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.ourioHeadline)
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .opacity(lit || days == 0 ? 1 : 0.45)
            .accessibilityHidden(true)
    }
}
