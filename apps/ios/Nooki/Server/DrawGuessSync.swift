import Foundation
import Transport
import Wire

/// The pair's Draw & guess riddles in their room. Every riddle call answers the riddle as this user sees it after it.
struct DrawGuessSync: Sendable {
    var fetch: @Sendable () async throws(TransportError) -> RiddlesResponse
    /// The drawing's PNG to the media store, before the riddle that names it.
    var upload: @Sendable (Data) async throws(TransportError) -> MediaKey
    var send: @Sendable (SendRiddleRequest) async throws(TransportError) -> Riddle
    var guess: @Sendable (RiddleId, IdempotencyKey, String) async throws(TransportError) -> GuessRiddleResponse
    var hint: @Sendable (RiddleId) async throws(TransportError) -> Riddle
    var giveUp: @Sendable (RiddleId) async throws(TransportError) -> Riddle

    static func live(_ api: APIClient) -> DrawGuessSync {
        DrawGuessSync(
            fetch: api.riddles,
            upload: { (png) async throws(TransportError) in try await api.uploadImage(png).image },
            send: api.sendRiddle, guess: api.guessRiddle, hint: api.hintRiddle, giveUp: api.giveUpRiddle)
    }
}
