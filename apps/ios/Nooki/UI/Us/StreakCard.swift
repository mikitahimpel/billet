import SwiftUI

/// The love streak on the Us tab: flame and day count, today's state, best streak and the milestone badge.
struct StreakCard: View {
    let store: StreakStore

    var body: some View {
        // Ticks each minute so "hours left" and the midnight rollover stay current while the tab is open.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let streak = store.streak
        let status = streak.status(on: now)
        let days = streak.current(on: now)
        let milestone = streak.milestone(on: now)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Flame(days: days, lit: status == .done)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Love streak")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Ink.secondary)
                    Text(days == 1 ? "1 day" : "\(days) days")
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Ink.primary)
                        .contentTransition(.numericText())
                    Text(caption(status, now: now))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                StatusPill(status: status, now: now)
            }

            if status == .restorable {
                Button {
                    withAnimation(.snappy(duration: 0.3)) { store.restore() }
                } label: {
                    Label("Restore \(streak.count)-day streak", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Capsule().fill(.honeyGradient))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Badge(reached: milestone.reached)
                Spacer(minLength: 0)
                Label("Best \(streak.best)", systemImage: "trophy.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Ink.secondary)
            }

            if let next = milestone.next {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressCapsule(value: Double(days) / Double(next))
                    Text("\(next - days) to the \(next)-day badge")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Ink.secondary)
                }
            }
        }
        .padding(16)
        .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .animation(.snappy(duration: 0.3), value: days)
    }

    private func caption(_ status: LoveStreak.Status, now: Date) -> String {
        switch status {
        case .done: "You showed up today. See you tomorrow!"
        case .atRisk: "Pet \(CatProfile.name()) or leave a note to keep it going"
        case .restorable: "You missed a day. You can bring the flame back once a month"
        case .cold: "Do something together today to light the flame"
        }
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
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .opacity(lit || days == 0 ? 1 : 0.45)
            .symbolEffect(.bounce, value: days)
            .frame(width: 64, height: 64)
            .background(colors[1].opacity(lit ? 0.22 : 0.1), in: .circle)
            .shadow(color: colors[1].opacity(lit ? 0.55 : 0), radius: 12)
    }
}

private struct StatusPill: View {
    let status: LoveStreak.Status
    let now: Date

    var body: some View {
        switch status {
        case .done:
            pill("Today", symbol: "checkmark", tint: Color(hex: 0xA8D98A))
        case .atRisk:
            pill(hoursLeft, symbol: "hourglass", tint: Color.honey)
        case .restorable, .cold:
            EmptyView()
        }
    }

    /// Time until midnight, when an at-risk streak goes out.
    private var hoursLeft: String {
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        let hours = Int(midnight.timeIntervalSince(now) / 3600)
        return hours < 1 ? "<1h left" : "\(hours)h left"
    }

    private func pill(_ title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(tint.opacity(0.18), in: .capsule)
    }
}

/// The highest milestone reached; before the first one it shows what's ahead.
private struct Badge: View {
    let reached: Int?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: reached == nil ? "lock.fill" : "rosette")
            Text(reached.map { "\($0)-day badge" } ?? "First badge at \(LoveStreak.milestones[0]) days")
        }
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundStyle(reached == nil ? Ink.secondary : Color.honey)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background((reached == nil ? Color.white : Color.honey).opacity(0.14), in: .capsule)
    }
}
