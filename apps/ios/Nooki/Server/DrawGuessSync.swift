import FeatureGames
import Foundation
import Transport
import Wire

typealias DrawGuessSync = DrawGuessClient

extension DrawGuessClient {
    static func live(_ api: APIClient) -> DrawGuessClient {
        DrawGuessClient(
            fetch: api.riddles,
            upload: { (png) async throws(TransportError) in try await api.uploadImage(png).image },
            send: api.sendRiddle, guess: api.guessRiddle, hint: api.hintRiddle, giveUp: api.giveUpRiddle)
    }
}
