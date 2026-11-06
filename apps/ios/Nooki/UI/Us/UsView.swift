import SwiftUI

/// The Us tab: the couple's plans. Countdown hero, love streak, three feature tiles, the games, then shared lists;
/// today's mood is in its header. Every card is a `usCard`, every icon a `UsIcon`.
struct UsView: View {
    @Bindable var state: HomeState

    @Environment(ServerSession.self) private var session: ServerSession?
    /// The round for a build without a server, which has no partner to play with.
    @State private var unpaired = WhoKnowsModel(sync: nil, viewer: nil, catalog: [])
    @State private var unpairedRiddles = DrawGuessModel(sync: nil, viewer: nil, words: .bundled)

    enum Route: Identifiable, Hashable {
        case dates, whoKnows, drawGuess, wishlists, calendar, list(UUID), newList

        var id: String {
            switch self {
            case .dates: "dates"
            case .whoKnows: "who-knows"
            case .drawGuess: "draw-guess"
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
                games
                lists
            }
            .padding(.horizontal, hMargin)
            .padding(.top, 4)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .task(id: session?.isPaired) {
            await whoKnows.load()
            await drawGuess.load()
        }
        .sheet(item: $state.usRoute) { route in
            switch route {
            case .dates: DatesScreen(state: state)
            case .whoKnows: WhoKnowsScreen(state: state, model: whoKnows)
            case .drawGuess: DrawGuessScreen(state: state, model: drawGuess)
            case .wishlists: WishlistScreen(state: state)
            case .calendar: CalendarScreen(state: state)
            case .list(let id): ListScreen(state: state, listID: id)
            case .newList: NewListSheet(state: state) { state.usRoute = .list($0) }
            }
        }
    }

    private var whoKnows: WhoKnowsModel { session?.whoKnows ?? unpaired }
    private var drawGuess: DrawGuessModel { session?.drawGuess ?? unpairedRiddles }

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

    private var games: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Games")
                .font(.nookiTitle)
                .foregroundStyle(Ink.primary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 6)

            Button { state.usRoute = .whoKnows } label: {
                WhoKnowsTile(model: whoKnows, me: state.profile.name(of: state.viewer),
                             partner: state.profile.name(of: state.otherPartner))
            }
            .buttonStyle(.plain)

            Button { state.usRoute = .drawGuess } label: {
                DrawGuessTile(model: drawGuess, partner: state.profile.name(of: state.otherPartner))
            }
            .buttonStyle(.plain)
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

            let layout = UsListsLayout(lists: us.lists, partner: state.otherPartner)
            ForEach(layout.cards) { list in
                Button { state.usRoute = .list(list.id) } label: { ListCard(list: list, state: state) }
                    .buttonStyle(.plain)
            }

            if !layout.rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(layout.rows.enumerated()), id: \.element.id) { index, list in
                        if index > 0 { Divider().overlay(Ink.separator).padding(.leading, 58) }
                        Button { state.usRoute = .list(list.id) } label: { ListRow(list: list) }
                            .buttonStyle(.plain)
                    }
                }
                .usCard()
            }

            Button { state.usRoute = .newList } label: { StartListCard() }
                .buttonStyle(.plain)
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
            .usCard(radius: Radius.hero, warm: true)
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
        .usCard()
    }

    private var detail: String {
        if let next, let idea = DateIdea.idea(next.ideaID) {
            return "Next: \(idea.title), \(next.date.formatted(.dateTime.day().month()))"
        }
        if matches > 0 { return "\(matches) \(matches == 1 ? "match" : "matches") waiting" }
        return "Swipe ideas together or let \(CatProfile.name()) pick"
    }
}

private struct WhoKnowsTile: View {
    let model: WhoKnowsModel
    let me: String
    let partner: String

    var body: some View {
        HStack(spacing: 14) {
            Image("WhoKnows-card")
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: Radius.control, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Who knows who")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Text(WhoKnowsModel.status(model.phase, remaining: model.remaining, partner: partner))
                    .font(.nookiCaption)
                    .foregroundStyle(model.phase == .revealed ? Ink.accentText : Ink.textSecondary)
                if model.phase != .unpaired, let week = model.score?.week {
                    Text(WhoKnowsModel.scoreLine(week, me: me, partner: partner))
                        .font(.nookiMicro.monospacedDigit())
                        .foregroundStyle(Ink.textSecondary)
                        .contentTransition(.numericText())
                        .accessibilityLabel("This week: \(me) \(week.mine), \(partner) \(week.partner)")
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.nookiCaption.weight(.semibold))
                .foregroundStyle(Ink.textTertiary)
        }
        .padding(14)
        .usCard()
        .accessibilityElement(children: .combine)
    }
}

private struct DrawGuessTile: View {
    let model: DrawGuessModel
    let partner: String

    var body: some View {
        let phase = model.phase
        HStack(spacing: 14) {
            Image("DrawGuess-card")
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: Radius.control, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Draw & guess")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Text(DrawGuessModel.status(phase, partner: partner, letters: model.theirs?.shape.reduce(0, +) ?? 0,
                                           lastEnded: model.lastEnded,
                                           endedMine: model.lastEnded.map(model.isMine) ?? false))
                    .font(.nookiCaption)
                    .foregroundStyle(phase == .guess ? Ink.accentText : Ink.textSecondary)
                if phase != .unpaired, model.series > 0 {
                    Text(DrawGuessModel.seriesLine(model.series))
                        .font(.nookiMicro.monospacedDigit())
                        .foregroundStyle(Ink.textSecondary)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.nookiCaption.weight(.semibold))
                .foregroundStyle(Ink.textTertiary)
        }
        .padding(14)
        .usCard()
        .accessibilityElement(children: .combine)
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
        .usCard()
    }
}
