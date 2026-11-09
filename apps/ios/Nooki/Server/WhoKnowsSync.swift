import FeatureGames
import Transport
import Wire

typealias WhoKnowsSync = WhoKnowsClient

extension WhoKnowsClient {
    static func live(_ api: APIClient) -> WhoKnowsClient {
        WhoKnowsClient(fetch: api.guess, answer: api.answerGuess)
    }
}
