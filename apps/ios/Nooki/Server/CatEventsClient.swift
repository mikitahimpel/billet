import Foundation
import Transport
import Wire

/// The pair's cat in its room: the profile (`GET`/`PUT /v1/cat`), the journal of what both partners did
/// (`GET /v1/cat/journal`), and this phone's own events (`POST /v1/cat/events`). The server folds the journal into
/// her needs and pays the coins, capped by day.
struct CatEventsClient: Sendable {
    var record: @Sendable (RecordCatEventRequest) async throws(TransportError) -> RecordCatEventResponse
    var load: @Sendable () async throws(TransportError) -> CatResponse
    /// Adopts the cat on the first save; a later one renames her.
    var adopt: @Sendable (SaveCatRequest) async throws(TransportError) -> CatResponse
    /// Journal entries after `seq`, oldest first, at most `journalPage` of them.
    var journal: @Sendable (_ after: Int) async throws(TransportError) -> [CatEntry]

    /// The server's longest journal page.
    static let journalPage = 100

    static let offline = CatEventsClient(
        record: { (_) async throws(TransportError) in throw .network("offline") },
        load: { () async throws(TransportError) in throw .network("offline") },
        adopt: { (_) async throws(TransportError) in throw .network("offline") },
        journal: { (_) async throws(TransportError) in throw .network("offline") })

    static func live(http: HTTPService, token: @escaping @Sendable () async -> String?) -> CatEventsClient {
        @Sendable func signed(_ request: HTTPRequest) async throws(TransportError) -> HTTPRequest {
            guard let token = await token() else { throw .api(.unauthorized) }
            var request = request
            request.headers[Routes.authorizationHeader] = Routes.bearerPrefix + token
            return request
        }
        return CatEventsClient(
            record: { (body) async throws(TransportError) in
                let route = Routes.recordCatEvent
                let request = try HTTPRequest.json(route.method, path: route.path, body: body)
                return try await http.perform(try await signed(request), as: RecordCatEventResponse.self)
            },
            load: { () async throws(TransportError) in
                let request = HTTPRequest(method: Routes.getCat.method, path: Routes.getCat.path)
                return try await http.perform(try await signed(request), as: CatResponse.self)
            },
            adopt: { (body) async throws(TransportError) in
                let route = Routes.saveCat
                let request = try HTTPRequest.json(route.method, path: route.path, body: body)
                return try await http.perform(try await signed(request), as: CatResponse.self)
            },
            journal: { (after) async throws(TransportError) in
                let route = Routes.listCatJournal
                let request = HTTPRequest(
                    method: route.method, path: route.path + "?after=\(after)&limit=\(journalPage)")
                return try await http.perform(try await signed(request), as: CatJournalResponse.self).entries
            })
    }
}
