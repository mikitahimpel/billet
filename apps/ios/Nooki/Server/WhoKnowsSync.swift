import Transport
import Wire

/// The pair's Who knows who round in its room. Every call answers today's round as this user sees it after it.
struct WhoKnowsSync: Sendable {
    var fetch: @Sendable () async throws(TransportError) -> GuessResponse
    var answer: @Sendable (GuessAnswerRequest) async throws(TransportError) -> GuessResponse

    static func live(_ api: APIClient) -> WhoKnowsSync {
        WhoKnowsSync(fetch: api.guess, answer: api.answerGuess)
    }
}
