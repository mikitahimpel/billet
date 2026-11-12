#if canImport(UIKit)
  import MomentsInterface
  import WidgetInterface
  import WidgetUI
  import ProfileInterface
  import SwiftUI
  import Design
  import UsInterface

  /// One warm hero (days together and the streak), three square actions, the games as posters on a shelf, the lists as
  /// rows.
  public struct UsView: View {
    let state: any UsHost

    public enum Route: Identifiable, Hashable {
      case dates, whoKnows, drawGuess, wishlists, calendar
      case list(UUID)
      case newList

      public var id: String {
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

    public init(state: any UsHost) {
      self.state = state
    }

    public var body: some View {
      let upcoming = us.upcoming(togetherSince: state.togetherSince)
      TabPage {
        StreakCard(
          store: state.streak, daysTogether: state.daysTogether,
          partner: state.profile.name(of: state.otherPartner))
        tiles(next: upcoming.first)
          .padding(.bottom, Space.l)
        state.gamesSection()
          .padding(.bottom, Space.l)
        lists
      }
      .sheet(item: Binding(get: { state.usRoute }, set: { state.usRoute = $0 })) { route in
        switch route {
        case .dates: DatesScreen(state: state)
        case .whoKnows: state.gameScreen(.whoKnows)
        case .drawGuess: state.gameScreen(.drawGuess)
        case .wishlists: WishlistScreen(state: state)
        case .calendar: CalendarScreen(state: state)
        case .list(let id): ListScreen(state: state, listID: id)
        case .newList: NewListSheet(state: state) { state.usRoute = .list($0) }
        }
      }
    }

    private func tiles(next: Upcoming?) -> some View {
      let matches = us.matches.count
      let wishes = us.wishes(of: state.partners.0).count + us.wishes(of: state.partners.1).count
      return ActionTiles([
        ActionTile(
          "Dates", status: Self.matchesLine(matches), symbol: "dice.fill",
          tint: UsTint.blush.color
        ) { state.usRoute = .dates },
        ActionTile(
          "Wishlists", status: wishes == 1 ? "1 wish" : "\(wishes) wishes",
          symbol: "gift.fill", tint: UsTint.honey.color
        ) { state.usRoute = .wishlists },
        ActionTile(
          "Calendar", status: next.map(Self.when) ?? "Nothing yet",
          symbol: "calendar", tint: UsTint.sky.color
        ) { state.usRoute = .calendar },
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

    private var lists: some View {
      VStack(alignment: .leading, spacing: Space.m) {
        SectionHeader("Lists") {
          PillButton("New list", symbol: "plus") { state.usRoute = .newList }
        }
        let layout = UsListsLayout(lists: us.lists, partner: state.otherPartner)
        GroupedSection {
          ForEach(layout.cards + layout.rows) { list in
            Button {
              state.usRoute = .list(list.id)
            } label: {
              ListRow(list: list)
            }
            .buttonStyle(RowButtonStyle())
          }
          if us.lists.isEmpty {
            Button {
              state.usRoute = .newList
            } label: {
              Row(
                "Start a list", detail: "Gifts, recipes, a trip packing list…", symbol: "plus",
                tint: UsTint.honey.color
              ) { RowChevron() }
            }
            .buttonStyle(RowButtonStyle())
          }
        }
      }
    }
  }
#endif
