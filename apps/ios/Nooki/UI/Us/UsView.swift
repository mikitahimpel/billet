import MomentsInterface
import OurioShared
import ProfileInterface
import SwiftUI
import Design
import UsInterface

/// Every card is a `Card` that starts with a `CardHeader`; only the hero is warm.
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

    private let hMargin: CGFloat = Space.l
    private var us: UsStore { state.us }

    var body: some View {
        let upcoming = us.upcoming(togetherSince: state.togetherSince)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                header
                CountdownHero(next: upcoming.first, days: state.daysTogether) { state.usRoute = .calendar }
                StreakCard(store: state.streak)
                tiles(upcoming: upcoming.count)
                games
                lists
            }
            .padding(.horizontal, hMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .softScrollEdges()
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
        HStack(alignment: .center, spacing: Space.m) {
            Text("Us")
                .font(.ourioLargeTitle)
                .foregroundStyle(Ink.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .frame(height: Size.control)
    }

    private func tiles(upcoming: Int) -> some View {
        VStack(spacing: Space.m) {
            Button { state.usRoute = .dates } label: {
                DatesTile(matches: us.matches.count, next: us.plannedSorted.first { $0.rating == nil })
            }
            .buttonStyle(PressScaleStyle())

            HStack(spacing: Space.m) {
                Button { state.usRoute = .wishlists } label: {
                    SmallTile(icon: .init(symbol: "gift.fill", tint: .coral), title: "Wishlists",
                              detail: "\(us.wishes(of: state.partners.0).count + us.wishes(of: state.partners.1).count) wishes")
                }
                .buttonStyle(PressScaleStyle())
                Button { state.usRoute = .calendar } label: {
                    SmallTile(icon: .init(symbol: "calendar", tint: .sky), title: "Calendar",
                              detail: "\(upcoming) coming up")
                }
                .buttonStyle(PressScaleStyle())
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var games: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Games")
                .font(.ourioTitle)
                .foregroundStyle(Ink.primary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Space.s)

            Button { state.usRoute = .whoKnows } label: {
                WhoKnowsTile(model: whoKnows, me: state.profile.name(of: state.viewer),
                             partner: state.profile.name(of: state.otherPartner))
            }
            .buttonStyle(PressScaleStyle())

            Button { state.usRoute = .drawGuess } label: {
                DrawGuessTile(model: drawGuess, partner: state.profile.name(of: state.otherPartner))
            }
            .buttonStyle(PressScaleStyle())
        }
    }

    private var lists: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("Lists")
                    .font(.ourioTitle)
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                PillButton("New list", symbol: "plus") { state.usRoute = .newList }
            }
            .padding(.top, Space.s)

            let layout = UsListsLayout(lists: us.lists, partner: state.otherPartner)
            ForEach(layout.cards) { list in
                Button { state.usRoute = .list(list.id) } label: { ListCard(list: list, state: state) }
                    .buttonStyle(PressScaleStyle())
            }

            if !layout.rows.isEmpty {
                GroupedSection {
                    ForEach(layout.rows) { list in
                        Button { state.usRoute = .list(list.id) } label: { ListRow(list: list) }
                            .buttonStyle(RowButtonStyle())
                    }
                }
            }

            Button { state.usRoute = .newList } label: { StartListCard() }
                .buttonStyle(PressScaleStyle())
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
            Card(warm: true) {
                if let next {
                    // The one line about time: when it is and how far away, and no second count beside it.
                    CardHeader(next.title, detail: "\(when(next)) · \(next.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))",
                               symbol: next.icon.symbol, tint: next.icon.tint.color)
                } else {
                    CardHeader("Nothing planned yet", detail: "Day \(days) together", symbol: "calendar.badge.plus")
                }
            }
        }
        .buttonStyle(PressScaleStyle())
    }
}

private struct DatesTile: View {
    let matches: Int
    let next: PlannedDate?

    var body: some View {
        Card {
            CardHeader("Date night", detail: detail, symbol: "dice.fill", tint: UsTint.blush.color)
        }
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
        Card {
            CardHeader("Who knows who") {
                CardArt(Image("WhoKnows-card"))
            } detail: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WhoKnowsModel.status(model.phase, remaining: model.remaining, partner: partner))
                        .foregroundStyle(model.phase == .revealed ? Ink.accentText : Ink.textSecondary)
                    if model.phase != .unpaired, let week = model.score?.week {
                        Text(WhoKnowsModel.scoreLine(week, me: me, partner: partner))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .accessibilityLabel("This week: \(me) \(week.mine), \(partner) \(week.partner)")
                    }
                }
            } trailing: {
                RowChevron()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DrawGuessTile: View {
    let model: DrawGuessModel
    let partner: String

    var body: some View {
        let phase = model.phase
        Card {
            CardHeader("Draw & guess") {
                CardArt(Image("DrawGuess-card"))
            } detail: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DrawGuessModel.status(phase, partner: partner, letters: model.theirs?.shape.reduce(0, +) ?? 0,
                                               lastEnded: model.lastEnded,
                                               endedMine: model.lastEnded.map(model.isMine) ?? false))
                        .foregroundStyle(phase == .guess ? Ink.accentText : Ink.textSecondary)
                    if phase != .unpaired, model.series > 0 {
                        Text(DrawGuessModel.seriesLine(model.series))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
            } trailing: {
                RowChevron()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SmallTile: View {
    let icon: UsGlyph
    let title: String
    let detail: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.s) {
                RowIcon(symbol: icon.symbol, tint: icon.tint.color, size: Size.cardMark)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title)
                        .font(.ourioHeadline)
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
