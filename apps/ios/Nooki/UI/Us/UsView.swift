import SwiftUI

/// The Us tab: the couple's plans. Countdown hero, love streak, three feature tiles, then shared lists.
struct UsView: View {
    @Bindable var state: HomeState

    enum Route: Identifiable, Hashable {
        case dates, wishlists, calendar, list(UUID), newList

        var id: String {
            switch self {
            case .dates: "dates"
            case .wishlists: "wishlists"
            case .calendar: "calendar"
            case .list(let id): "list-\(id)"
            case .newList: "new-list"
            }
        }
    }

    private let hMargin: CGFloat = 16
    /// Same tab bar clearance as the shop.
    private let bottomInset: CGFloat = 134
    private var us: UsStore { state.us }

    var body: some View {
        let upcoming = us.upcoming(togetherSince: state.togetherSince)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                CountdownHero(next: upcoming.first, days: state.daysTogether) { state.usRoute = .calendar }
                StreakCard(store: state.streak)
                tiles(upcoming: upcoming.count)
                lists
            }
            .padding(.horizontal, hMargin)
            .padding(.top, 4)
            .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(item: $state.usRoute) { route in
            switch route {
            case .dates: DatesScreen(state: state)
            case .wishlists: WishlistScreen(state: state)
            case .calendar: CalendarScreen(state: state)
            case .list(let id): ListScreen(state: state, listID: id)
            case .newList: NewListSheet(state: state) { state.usRoute = .list($0) }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Us")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.primary)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            Spacer(minLength: 0)
            ViewerSwitch(state: state)
            Button { state.showsSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .glass(.circle, interactive: true)
            .accessibilityLabel("Settings")
        }
        .frame(height: 44)
    }

    private func tiles(upcoming: Int) -> some View {
        VStack(spacing: 12) {
            Button { state.usRoute = .dates } label: {
                DatesTile(matches: us.matches.count, next: us.plannedSorted.first { $0.rating == nil })
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Button { state.usRoute = .wishlists } label: {
                    SmallTile(icon: .init(symbol: "gift.fill", tint: .coral), title: "Wishlists",
                              detail: "\(us.wishes(of: state.partners.0).count + us.wishes(of: state.partners.1).count) wishes")
                }
                .buttonStyle(.plain)
                Button { state.usRoute = .calendar } label: {
                    SmallTile(icon: .init(symbol: "calendar", tint: .sky), title: "Calendar",
                              detail: "\(upcoming) coming up")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var lists: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lists")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.primary)
                Spacer(minLength: 0)
                Button { state.usRoute = .newList } label: {
                    Label("New list", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.honey)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)

            VStack(spacing: 0) {
                ForEach(Array(us.lists.enumerated()), id: \.element.id) { index, list in
                    if index > 0 { Divider().overlay(Ink.hairline).padding(.leading, 56) }
                    Button { state.usRoute = .list(list.id) } label: { ListRow(list: list) }
                        .buttonStyle(.plain)
                }
            }
            .usCard()
        }
    }
}

// MARK: - Pieces

/// "Who's holding the phone" toggle; both partners share one device until sync lands.
private struct ViewerSwitch: View {
    let state: HomeState

    var body: some View {
        HStack(spacing: 4) {
            ForEach([state.partners.0, state.partners.1], id: \.self) { initial in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { state.viewer = initial }
                } label: {
                    Monogram(partner: initial, profile: state.profile, size: 32)
                        .opacity(state.viewer == initial ? 1 : 0.35)
                        .overlay(Circle().stroke(.white.opacity(state.viewer == initial ? 0.9 : 0), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Using as \(initial)")
            }
        }
        .padding(4)
        .glass(.capsule)
    }
}

private struct CountdownHero: View {
    let next: Upcoming?
    let days: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                if let next { UsIcon(glyph: next.icon, size: 48) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day \(days) together")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Ink.heroInk.opacity(0.7))
                    if let next {
                        Text(next.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Ink.heroInk)
                            .lineLimit(2)
                        Text(next.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.heroInk.opacity(0.7))
                    } else {
                        Text("Nothing planned yet")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Ink.heroInk)
                    }
                }
                Spacer(minLength: 0)
                if let next {
                    VStack(spacing: 0) {
                        Text(next.daysLeft == 0 ? "🎉" : "\(next.daysLeft)")
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        Text(next.daysLeft == 0 ? "today" : next.daysLeft == 1 ? "day" : "days")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Ink.heroInk)
                    .frame(width: 76, height: 76)
                    .background(.white.opacity(0.45), in: .circle)
                }
            }
            .padding(18)
            .background(
                LinearGradient(colors: [Color(hex: 0xF6C891), Color(hex: 0xD98A55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 28, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DatesTile: View {
    let matches: Int
    let next: PlannedDate?

    var body: some View {
        HStack(spacing: 14) {
            UsIcon(glyph: .init(symbol: "dice.fill", tint: .blush), size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text("Date night")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.primary)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Ink.secondary)
        }
        .padding(14)
        .usCard(radius: 24)
    }

    private var detail: String {
        if let next, let idea = DateIdea.idea(next.ideaID) {
            return "Next: \(idea.title), \(next.date.formatted(.dateTime.day().month()))"
        }
        if matches > 0 { return "\(matches) \(matches == 1 ? "match" : "matches") waiting" }
        return "Swipe ideas together or let Mochi pick"
    }
}

private struct SmallTile: View {
    let icon: UsGlyph
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UsIcon(glyph: icon, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.primary)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Ink.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .usCard(radius: 24)
    }
}

private struct ListRow: View {
    let list: UsList

    var body: some View {
        HStack(spacing: 12) {
            UsIcon(glyph: list.icon, size: 34)
            Text(list.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.primary)
            Spacer(minLength: 0)
            Text(counts)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Ink.secondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.secondary.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .contentShape(.rect)
    }

    private var counts: String {
        let open = list.open.count, done = list.finished.count
        if list.kind.isChecklist || done == 0 { return "\(open)" }
        return "\(open) · \(done) ✓"
    }
}
