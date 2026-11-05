import Foundation
import Transport
import Wire

/// The room socket the app keeps while it is in front, outside the canvas: the Inbox's unread count, the partner's
/// photos as they are sent, and reactions to photos. It resumes after the last note the photos looked at and leaves
/// the cat's journal out, so no cat frames; the canvas keeps its own socket for those.
@MainActor
final class InboxLink {
    private var client: WebSocketClient?

    struct Handlers {
        var unread: @MainActor @Sendable (Int) -> Void
        /// A photo note arrived; the photos page from their own cursor, so the frame only says when.
        var photo: @MainActor @Sendable () -> Void
        var reaction: @MainActor @Sendable (NoteReaction) -> Void
        var lastReactionRev: @MainActor @Sendable () -> Int?
    }

    init(baseURL: URL, token: @escaping @Sendable () async -> String?, lastSeq: Int?, handlers: Handlers) {
        let dependencies = WebSocketDependencies(
            open: { () async throws(TransportError) -> WebSocketConnection in
                guard let token = await token() else { throw .api(.unauthorized) }
                guard let request = URLRequest.socket(baseURL: baseURL, token: token) else {
                    throw .network("invalid socket URL")
                }
                return try await WebSocketConnection.urlSession(request, session: .shared)
            },
            sleep: { try? await Task.sleep(for: $0) },
            deliver: { message in
                switch message {
                case .activityUnread(let count): await handlers.unread(count)
                case .noteReceived(_, .photo): await handlers.photo()
                case .reactionChanged(let change): await handlers.reaction(change)
                case .noteReceived, .stroke, .presence, .strokeBegin, .strokePoints, .strokeEnd, .strokeDropped,
                     .clear, .catEntryAdded, .catSaved:
                    break
                }
            },
            followsActivity: true,
            lastReactionRev: { await handlers.lastReactionRev() })
        client = WebSocketClient(dependencies: dependencies, lastSeq: lastSeq)
    }

    func connect() { client?.connect() }

    func disconnect() { client?.disconnect() }
}
