import Foundation
import Transport
import Wire

/// Writes what one of the couple did for the cat into the pair's journal (`POST /v1/cat/events`). The server folds
/// it into her needs and pays the coins, capped by day. `CatEventOutbox` keeps what it hasn't sent yet.
struct CatEventsClient: Sendable {
    var record: @Sendable (RecordCatEventRequest) async throws(TransportError) -> RecordCatEventResponse

    static let offline = CatEventsClient(record: { (_) async throws(TransportError) in throw .network("offline") })

    static func live(http: HTTPService, token: @escaping @Sendable () async -> String?) -> CatEventsClient {
        CatEventsClient(record: { (body) async throws(TransportError) in
            guard let token = await token() else { throw .api(.unauthorized) }
            let route = Routes.recordCatEvent
            var request = try HTTPRequest.json(route.method, path: route.path, body: body)
            request.headers[Routes.authorizationHeader] = Routes.bearerPrefix + token
            return try await http.perform(request, as: RecordCatEventResponse.self)
        })
    }
}
