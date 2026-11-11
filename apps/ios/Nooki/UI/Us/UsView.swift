import MomentsInterface
import WidgetInterface
import WidgetUI
import ProfileInterface
import SwiftUI
import Design
import UsInterface

/// One warm hero (days together and the streak), three square actions, the games as posters on a shelf, the lists as
/// rows.
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

    private var us: UsStore { state.us }

    var body: some View {
        let upcoming = us.upcoming(togetherSince: state.togetherSince)
        TabPage {
            StreakCard(store: state.streak, daysTogether: state.daysTogether)
            tiles(next: upcoming.first)
                .padding(.bottom, Space.l)
            games
                .padding(.bottom, Space.l)
            lists
        }
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

    private func tiles(next: Upcoming?) -> some View {
        let matches = us.matches.count
        let wishes = us.wishes(of: state.partners.0).count + us.wishes(of: state.partners.1).count
        return ActionTiles([
            ActionTile("Dates", status: Self.matchesLine(matches), symbol: "dice.fill",
                       tint: UsTint.blush.color) { state.usRoute = .dates },
            ActionTile("Wishlists", status: wishes == 1 ? "1 wish" : "\(wishes) wishes",
                       symbol: "gift.fill", tint: UsTint.honey.color) { state.usRoute = .wishlists },
            ActionTile("Calendar", status: next.map(Self.when) ?? "Nothing yet",
                       symbol: "calendar", tint: UsTint.sky.color) { state.usRoute = .calendar },
        ])
    }

    private static func matchesLine(_ matches: Int) -> String {
        switch matches {
        case 0: "Swipe ideas"
        case 1: "1 match"
        default: "\(matches) matches"
        }
    }

    private static func when(_ next: Upcoming) -> String {
        switch next.daysLeft {
        case 0: "Today"
        case 1: "Tomorrow"
        default: "In \(next.daysLeft) days"
        }
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var games: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("Games")
            let partner = state.profile.name(of: state.otherPartner)
            let posters = Group {
                let whoKnowsStatus = WhoKnowsModel.status(whoKnows.phase, remaining: whoKnows.remaining,
                                                          partner: partner)
                PosterCard("Who knows who", status: whoKnowsStatus, emphasis: whoKnows.phase == .revealed,
                           action: { state.usRoute = .whoKnows }) {
                    GamePoster(game: .whoKnows)
                }
                PosterCard("Draw & guess", status: drawGuessStatus(partner: partner),
                           emphasis: drawGuess.phase == .guess, action: { state.usRoute = .drawGuess }) {
                    GamePoster(game: .drawGuess)
                }
            }
            if typeSize.isAccessibilitySize {
                VStack(spacing: Space.m) { posters }
            } else {
                // Three fifths of the width each, so the next poster peeks in from the edge.
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Space.m) {
                        posters.containerRelativeFrame(.horizontal, count: 5, span: 3, spacing: Space.m)
                    }
                    // Each poster as tall as its art and words, not the height the scroll view offers.
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }

    private func drawGuessStatus(partner: String) -> String {
        DrawGuessModel.status(drawGuess.phase, partner: partner,
                              letters: drawGuess.theirs?.shape.reduce(0, +) ?? 0, lastEnded: drawGuess.lastEnded,
                              endedMine: drawGuess.lastEnded.map(drawGuess.isMine) ?? false)
    }

    private var lists: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("Lists") {
                PillButton("New list", symbol: "plus") { state.usRoute = .newList }
            }
            let layout = UsListsLayout(lists: us.lists, partner: state.otherPartner)
            GroupedSection {
                ForEach(layout.cards + layout.rows) { list in
                    Button { state.usRoute = .list(list.id) } label: { ListRow(list: list) }
                        .buttonStyle(RowButtonStyle())
                }
                if us.lists.isEmpty {
                    Button { state.usRoute = .newList } label: {
                        Row("Start a list", detail: "Gifts, recipes, a trip packing list…", symbol: "plus",
                            tint: UsTint.honey.color) { RowChevron() }
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
        }
    }
}
