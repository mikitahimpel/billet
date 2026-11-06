import Foundation
import Transport
import WidgetBridge
import Wire

/// One card of the Pick tonight deck: a title still to watch on the pair's list, or one TMDB suggests.
nonisolated struct PickCard: Identifiable, Hashable {
    let title: PickTitle
    let name: String
    let media: ItemMedia?
    /// The list item it is, nil for a suggestion.
    let itemID: UUID?

    var id: String { PickTonightModel.key(title) }
}

/// The Pick tonight deck and the pair's session in its room. The deck is the To watch titles this user hasn't swiped
/// in the session, then TMDB's suggestions like the ones the pair wants. A ♥ from both partners within a day is a
/// match, answered to the swipe that made it and pushed over the socket to the partner's open screen.
@Observable
final class PickTonightModel {
    /// The server's switch for the feature; a pair without a variant has it.
    nonisolated static let flag = Experiment(key: "pick-tonight", variants: ["off", "on"])
    /// TMDB takes this many titles to suggest from.
    nonisolated static let maxSeeds = 5

    private(set) var deck: [PickCard] = []
    /// How many cards the partner swiped in the session.
    private(set) var partnerPicked = 0
    /// The match to celebrate, until it is planned or put away.
    private(set) var match: PickMatch?
    /// Whether the partner's swipe made `match`, so the push went to this phone rather than theirs.
    private(set) var matchByPartner = false
    private(set) var loading = true
    /// The room wasn't reachable; the deck shows the list alone and swipes are not counted.
    private(set) var offline = false

    @ObservationIgnored private let sync: PickTonightSync
    @ObservationIgnored private let titles: TitleSource?
    /// Matches already shown here, so a socket frame after the swipe's own answer doesn't show one twice.
    @ObservationIgnored private var shown: Set<String> = []

    init(sync: PickTonightSync, titles: TitleSource?) {
        self.sync = sync
        self.titles = titles
    }

    nonisolated static func isOn(_ flags: RemoteFlags) -> Bool {
        flags.variant(of: flag) != "off"
    }

    /// A string per card, the same for the same card from the list, the room or TMDB.
    nonisolated static func key(_ title: PickTitle) -> String {
        switch title {
        case .item(let item): "item:\(UUID(uuidString: item.rawValue)?.uuidString ?? item.rawValue)"
        case .title(let kind, let tmdb): "\(kind.rawValue):\(tmdb)"
        }
    }

    /// Reads the session and deals the deck from `list`. Offline, the deck is the list's titles still to watch.
    func load(_ list: UsList, partners: [String]) async {
        loading = true
        defer { loading = false }
        var swiped: Set<String> = []
        do throws(TransportError) {
            let session = try await sync.fetch()
            swiped = Set(session.swipes.map { Self.key($0.title) })
            partnerPicked = session.partnerPicked
            for match in session.matches { shown.insert(Self.matchKey(match)) }
            offline = false
        } catch {
            offline = true
        }
        deck = Self.deck(list, swiped: swiped, suggestions: [])
        let seeds = Self.seeds(list, partners: partners)
        guard !offline, !seeds.isEmpty, let titles, let suggested = try? await titles.recommendations(seeds) else {
            return
        }
        let dealt = Set(deck.map(\.id))
        deck += Self.deck(list, swiped: swiped, suggestions: suggested).filter { !dealt.contains($0.id) }
    }

    /// Takes `card` off the deck, for the swipe on it.
    func take(_ card: PickCard) {
        deck.removeAll { $0.id == card.id }
    }

    /// Sends the swipe on a card taken off the deck. Answers the match it made, also kept in `match`.
    @discardableResult
    func send(_ card: PickCard, _ choice: PickChoice) async -> PickMatch? {
        guard !offline else { return nil }
        let request = PickSwipeRequest(title: card.title, choice: choice, name: card.name, posterPath: card.media?.posterPath)
        guard let answer = try? await sync.swipe(request) else { return nil }
        partnerPicked = answer.partnerPicked
        guard let made = answer.match else { return nil }
        return show(made, byPartner: false)
    }

    /// A match the partner's swipe made, from the room's socket.
    @discardableResult
    func received(_ match: PickMatch) -> PickMatch? {
        show(match, byPartner: true)
    }

    func dismissMatch() {
        match = nil
    }

    private func show(_ made: PickMatch, byPartner: Bool) -> PickMatch? {
        guard shown.insert(Self.matchKey(made)).inserted else { return nil }
        matchByPartner = byPartner
        match = made
        return made
    }

    private nonisolated static func matchKey(_ match: PickMatch) -> String { "\(key(match.title))@\(match.at)" }

    /// The list's titles still to watch that this user hasn't swiped, newest first, then `suggestions` not on the
    /// list at all.
    nonisolated static func deck(_ list: UsList, swiped: Set<String>, suggestions: [TitleSummary]) -> [PickCard] {
        let listed = list.open.map { item in
            PickCard(title: .item(UsStore.key(item.id)), name: item.text, media: item.media, itemID: item.id)
        }
        let onList = Set(list.items.compactMap(\.media).map { key(.title(kind: $0.wireKind, tmdb: $0.tmdb)) })
        let suggested = suggestions.map { title in
            let kind: ItemMedia.Kind = switch title.kind {
            case .movie: .movie
            case .tv: .tv
            }
            return PickCard(title: .title(kind: title.kind, tmdb: title.tmdb), name: title.title,
                            media: ItemMedia(kind: kind, tmdb: title.tmdb, year: title.year, posterPath: title.posterPath),
                            itemID: nil)
        }
        return listed.filter { !swiped.contains($0.id) }
            + suggested.filter { !swiped.contains($0.id) && !onList.contains($0.id) }
    }

    /// What TMDB suggests from: the titles both partners want first, then the ones either wants, then the rest.
    nonisolated static func seeds(_ list: UsList, partners: [String]) -> [ListMedia] {
        let wanted = list.items.filter { $0.media != nil }.sorted {
            $0.wants.filter(partners.contains).count > $1.wants.filter(partners.contains).count
        }
        return wanted.prefix(maxSeeds).compactMap { $0.media.map(ListMedia.init) }
    }
}
