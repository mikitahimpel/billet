import SwiftUI
import Design

/// The Us tab: the couple's plans. Countdown hero, love streak, three feature tiles, then shared lists; today's mood
/// is in its header. Every card is a `usCard`, every icon a `UsIcon`.
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
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
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
                .font(.nookiLargeTitle)
                .foregroundStyle(Ink.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .frame(height: 44)
    }

    private func tiles(upcoming: Int) -> some View {
        VStack(spacing: Space.m) {
            Button { state.usRoute = .dates } label: {
                DatesTile(matches: us.matches.count, next: us.plannedSorted.first { $0.rating == nil })
            }
            .buttonStyle(.plain)

            HStack(spacing: Space.m) {
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
                    .font(.nookiTitle)
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { state.usRoute = .newList } label: {
                    Label("New list", systemImage: "plus")
                        .font(.nookiHeadline)
                        .foregroundStyle(Ink.accentText)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)

            VStack(spacing: 0) {
                ForEach(Array(us.lists.enumerated()), id: \.element.id) { index, list in
                    if index > 0 { Divider().overlay(Ink.separator).padding(.leading, 58) }
                    Button { state.usRoute = .list(list.id) } label: { ListRow(list: list) }
                        .buttonStyle(.plain)
                }
            }
            .cardSurface()
        }
    }
}

// MARK: - Pieces

private struct CountdownHero: View {
    let next: Upcoming?
    let days: Int
    var onTap: () -> Void

    private func when(_ next: Upcoming) -> String {
        switch next.daysLeft {
        case 0: "Today"
        case 1: "Tomorrow"
        default: "In \(next.daysLeft) days"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                if let next { UsIcon(glyph: next.icon, size: 48) }
                VStack(alignment: .leading, spacing: 4) {
                    if let next {
                        Text(next.title)
                            .font(.nookiTitle)
                            .foregroundStyle(Ink.text)
                            .lineLimit(2)
                        // The one line about time: when it is and how far away, and no second count beside it.
                        Text("\(when(next)) · \(next.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                            .font(.nookiCallout)
                            .foregroundStyle(Ink.textSecondary)
                    } else {
                        Text("Nothing planned yet")
                            .font(.nookiTitle)
                            .foregroundStyle(Ink.text)
                        Text("Day \(days) together")
                            .font(.nookiCallout)
                            .foregroundStyle(Ink.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.nookiCaption.weight(.semibold))
                    .foregroundStyle(Ink.textTertiary)
            }
            .padding(18)
            .cardSurface(radius: Radius.hero, warm: true)
        }
        .buttonStyle(.plain)
    }
}

private struct DatesTile: View {
    let matches: Int
    let next: PlannedDate?

    var body: some View {
        HStack(spacing: 14) {
            UsIcon(glyph: .init(symbol: "dice.fill", tint: .blush), size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Date night")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Text(detail)
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.nookiCaption.weight(.semibold))
                .foregroundStyle(Ink.textTertiary)
        }
        .padding(14)
        .cardSurface()
    }

    private var detail: String {
        if let next, let idea = DateIdea.idea(next.ideaID) {
            return "Next: \(idea.title), \(next.date.formatted(.dateTime.day().month()))"
        }
        if matches > 0 { return "\(matches) \(matches == 1 ? "match" : "matches") waiting" }
        return "Swipe ideas together or let \(CatProfile.name()) pick"
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
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Text(detail)
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface()
    }
}

private struct ListRow: View {
    let list: UsList

    var body: some View {
        HStack(spacing: 12) {
            UsIcon(glyph: list.icon, size: 34)
            Text(list.title)
                .font(.nookiHeadline)
                .foregroundStyle(Ink.text)
            Spacer(minLength: 0)
            Text(counts)
                .font(.nookiCaption.monospacedDigit())
                .foregroundStyle(Ink.textSecondary)
            Image(systemName: "chevron.right")
                .font(.nookiCaption.weight(.semibold))
                .foregroundStyle(Ink.textTertiary)
        }
        .padding(.horizontal, Space.m)
        .frame(minHeight: 54)
        .contentShape(.rect)
    }

    private var counts: String {
        let open = list.open.count, done = list.finished.count
        if list.kind.isChecklist || done == 0 { return "\(open)" }
        return "\(open) · \(done) ✓"
    }
}
