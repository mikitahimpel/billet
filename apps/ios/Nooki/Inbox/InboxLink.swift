import Foundation
import Transport
import Wire

/// A room socket that only follows the Inbox's unread count while the app is in front: it asks for `ActivityUnread`
/// and nothing else. It resumes as if it held every note, so the server sends it no notes, and leaves the cat's
/// journal out, so no cat frames either; the canvas keeps its own socket for those.
@MainActor
final class InboxLink {
    /// The highest note `seq` a resume can name: past every note, so none is replayed.
    static let pastEveryNote = 9_007_199_254_740_991

    private var client: WebSocketClient?

    init(baseURL: URL, token: @escaping @Sendable () async -> String?, unread: @escaping @MainActor @Sendable (Int) -> Void) {
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
                guard case .activityUnread(let count) = message else { return }
                await unread(count)
            },
            followsActivity: true)
        client = WebSocketClient(dependencies: dependencies, lastSeq: Self.pastEveryNote)
    }

    func connect() { client?.connect() }

    func disconnect() { client?.disconnect() }
}
