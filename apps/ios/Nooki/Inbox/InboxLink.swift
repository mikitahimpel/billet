import Foundation
import Transport
import Wire

/// The room socket kept while the app is in front: Inbox unread count, partner photos, reactions, shop and lists,
/// check-ins, the love streak, Who knows who, Draw & guess riddles. Resumes after the last note the photos saw and the cat's last
/// journal entry this phone holds, so both partners' care reaches her here.
@MainActor
final class InboxLink {
    private var client: WebSocketClient?

    struct Handlers {
        var unread: @MainActor @Sendable (Int) -> Void
        /// A photo note arrived; the photos page from their own cursor, so the frame only says when.
        var photo: @MainActor @Sendable () -> Void
        /// A text note arrived; the text notes page from their own cursor too.
        var text: @MainActor @Sendable () -> Void
        /// A drawing arrived, with the room's `seq` for it.
        var drawing: @MainActor @Sendable (Int, Note) -> Void
        var reaction: @MainActor @Sendable (NoteReaction) -> Void
        var lastReactionRev: @MainActor @Sendable () -> Int?
        var shop: @MainActor @Sendable (ShopResponse) -> Void
        var lists: @MainActor @Sendable ([SharedList]) -> Void
        var mood: @MainActor @Sendable (PartnerCheckIn) -> Void
        var match: @MainActor @Sendable (PickMatch) -> Void
        /// The partner's count of locked answers in the Who knows who round of that day.
        var guessProgress: @MainActor @Sendable (_ round: String, _ answered: Int) -> Void
        var guessRevealed: @MainActor @Sendable (_ round: String, [GuessReveal], GuessScore) -> Void
        /// A Draw & guess riddle as this user sees it after a send, try, hint or give-up.
        var riddle: @MainActor @Sendable (Riddle) -> Void
        /// The pair's streak after either partner counted a day or restored it, and once on each resume.
        var streak: @MainActor @Sendable (PairStreak) -> Void
        /// One entry of the cat's journal, either partner's.
        var catEntry: @MainActor @Sendable (CatEntry) -> Void
        /// The last journal entry held, read as each socket opens; nil follows no cat frames.
        var lastCatSeq: @MainActor @Sendable () -> Int?
        var presence: @MainActor @Sendable (PartnerPresence) -> Void
        /// The socket opened, the first time or after a drop; it resumes, but a pull catches what it can't.
        var opened: @MainActor @Sendable () -> Void
    }

    /// When a frame last came; any frame says the socket is alive.
    private var lastHeard: ContinuousClock.Instant?

    init(baseURL: URL, token: @escaping @Sendable () async -> String?, lastSeq: Int?, handlers: Handlers) {
        let dependencies = WebSocketDependencies(
            open: { () async throws(TransportError) -> WebSocketConnection in
                guard let token = await token() else { throw .api(.unauthorized) }
                guard let request = URLRequest.socket(baseURL: baseURL, token: token) else {
                    throw .network("invalid socket URL")
                }
                let connection = try await WebSocketConnection.urlSession(request, session: .shared)
                await handlers.opened()
                return connection
            },
            sleep: { try? await Task.sleep(for: $0) },
            deliver: { [weak self] message in
                await self?.heard()
                switch message {
                case .activityUnread(let count): await handlers.unread(count)
                case .noteReceived(_, .photo): await handlers.photo()
                case .noteReceived(_, .text): await handlers.text()
                case .noteReceived(let seq, let note): await handlers.drawing(seq, note)
                case .reactionChanged(let change): await handlers.reaction(change)
                case .shopChanged(let shop): await handlers.shop(shop)
                case .listsChanged(let lists): await handlers.lists(lists)
                case .moodChanged(let checkIn): await handlers.mood(checkIn)
                case .matchFound(let match): await handlers.match(match)
                case .guessProgress(let round, let answered): await handlers.guessProgress(round, answered)
                case .guessRevealed(let round, let reveal, let score): await handlers.guessRevealed(round, reveal, score)
                case .riddleChanged(let riddle): await handlers.riddle(riddle)
                case .streakChanged(let streak): await handlers.streak(streak)
                case .catEntryAdded(let entry): await handlers.catEntry(entry)
                case .presence(let presence): await handlers.presence(presence)
                case .stroke, .strokeBegin, .strokePoints, .strokeEnd, .strokeDropped,
                     .clear, .catSaved:
                    break
                }
            },
            followsActivity: true,
            lastReactionRev: { await handlers.lastReactionRev() },
            lastCatSeq: { await handlers.lastCatSeq() },
            followsShop: true,
            followsLists: true,
            followsMoods: true,
            followsGuess: true,
            followsRiddle: true,
            followsStreak: true)
        client = WebSocketClient(dependencies: dependencies, lastSeq: lastSeq)
    }

    var isConnected: Bool {
        guard case .connected = client?.state.phase else { return false }
        return true
    }

    func connect() { client?.connect() }

    private func heard() { lastHeard = .now }

    /// Heard from within `quietLimit`, or else answering a ping; a socket that doesn't answer is opened again.
    func isHealthy(quietLimit: Duration) async -> Bool {
        guard isConnected, let client else { return false }
        if let lastHeard, ContinuousClock.now - lastHeard < quietLimit { return true }
        guard await client.ping() else { return false }
        heard()
        return true
    }

    func disconnect() { client?.disconnect() }
}
