import Transport
import Wire

/// The pair's shared lists in its room. Every call answers all of them as they are after it.
struct ListSync: Sendable {
    var fetch: @Sendable () async throws(TransportError) -> ListsResponse
    var change: @Sendable (ChangeListRequest) async throws(TransportError) -> ListsResponse

    static func live(_ api: APIClient) -> ListSync {
        ListSync(fetch: api.lists, change: api.changeList)
    }
}
