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
                // Side by side while "days together" keeps its line; the ring goes under it at the largest sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: Space.m) {
                        together
                        Spacer(minLength: 0)
                        ring(days: days, lit: status == .done, next: next)
                    }
                    VStack(alignment: .leading, spacing: Space.m) {
                        together
                        ring(days: days, lit: status == .done, next: next)
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

    private var together: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(daysTogether, format: .number)
                .font(.ourioHeroDigits)
                .foregroundStyle(Ink.text)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            Text(daysTogether == 1 ? "day together" : "days together")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.textSecondary)
        }
    }

    private func ring(days: Int, lit: Bool, next: Int?) -> some View {
        VStack(spacing: Space.xs) {
            ProgressRing(
                value: next.map { Double(days) / Double($0) } ?? 1,
                tint: Color(light: .honeyDeep, dark: .honeyBright)
            ) {
                VStack(spacing: 0) {
                    Flame(days: days, lit: lit)
                    Text(days, format: .number)
                        .font(.ourioTitleDigits)
                        .foregroundStyle(Ink.text)
                        .contentTransition(.numericText())
                }
            }
            Text("day streak")
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Its lead words in full ink, the rest quieter.
    private func line(_ status: LoveStreak.Status, days: Int, next: Int?) -> Text {
        let lead: String, rest: String
        switch status {
        case .done:
            lead = "Day \(days) is in."
            rest = next.map { " Badge at day \($0)." } ?? " See you tomorrow."
        case .atRisk:
            lead = "Keep it going."
            rest = " Pet \(CatProfile.name()) or leave a note."
        case .restorable:
            lead = "You missed a day."
            rest = " You can bring the flame back once a month."
        case .cold:
            lead = "Light the flame"
            rest = " together today."
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

/// Flame that warms with the streak: orange, pink from 30 days, purple from 100. At 0 it is an outline, a flame
/// waiting to be lit; while today doesn't count yet it is a little quieter.
private struct Flame: View {
    let days: Int
    let lit: Bool

    private var colors: [Color] {
        if days >= 100 { return [Color(hex: 0xD9B8FF), Color(hex: 0x8A5CFF)] }
        if days >= 30 { return [Color(hex: 0xFFB3C4), Color(hex: 0xFF5C8A)] }
        return [Color(hex: 0xFFD27A), Color(hex: 0xFF6A3D)]
    }

    var body: some View {
        Group {
            if days == 0 {
                Image(systemName: "flame")
                    .foregroundStyle(Ink.textSecondary)
            } else {
                Image(systemName: "flame.fill")
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .opacity(lit ? 1 : 0.65)
            }
        }
        .font(.ourioLargeTitleDigits)
        .accessibilityHidden(true)
    }
}
