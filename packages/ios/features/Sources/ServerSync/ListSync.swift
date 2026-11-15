import Transport
import Wire

/// The pair's shared lists in its room. Every call answers all of them as they are after it.
public nonisolated struct ListSync: Sendable {
  public var fetch: @Sendable () async throws(TransportError) -> ListsResponse
  public var change: @Sendable (ChangeListRequest) async throws(TransportError) -> ListsResponse

  public init(
    fetch: @escaping @Sendable () async throws(TransportError) -> ListsResponse,
    change: @escaping @Sendable (ChangeListRequest) async throws(TransportError) -> ListsResponse
  ) {
    self.fetch = fetch
    self.change = change
  }

  public static func live(_ api: APIClient) -> ListSync {
    ListSync(fetch: api.lists, change: api.changeList)
  }
}
