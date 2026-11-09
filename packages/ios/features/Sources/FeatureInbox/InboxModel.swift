import BilletKit
import Observation
import Transport
import Wire

/// Runs ``InboxMachine`` against the backend.
@MainActor
@Observable
public final class InboxModel {
  public typealias List =
    @Sendable (_ before: String?) async throws(TransportError) ->
    ActivityResponse
  public typealias MarkRead =
    @Sendable (MarkActivityReadRequest) async throws(TransportError) ->
    ActivityUnreadResponse

  private let store: Store<InboxMachine>

  public var sheet: InboxMachine.Sheet { store.state.sheet }
  public var unread: Int { store.state.unread }

  public init(list: @escaping List, markRead: @escaping MarkRead) {
    store = Store(initial: .initial) { output in
      await InboxMachine.run(output, list: list, markRead: markRead)
    }
  }

  public convenience init(api: APIClient) {
    self.init(list: api.listActivity, markRead: api.markActivityRead)
  }

  /// The first page again, then everything on it is read. Returns when both are done, for pull to
  /// refresh.
  public func open() async {
    store.send(.opened)
    await store.settled()
  }

  public func loadMore() { store.send(.reachedEnd) }

  public func unreadChanged(_ count: Int) { store.send(.counted(count)) }

  public func refreshCount() async {
    store.send(.countRequested)
    await store.settled()
  }
}

extension InboxMachine {
  static func run(_ output: Output, list: InboxModel.List, markRead: InboxModel.MarkRead) async
    -> Event?
  {
    switch output {
    case .loadFirst(let request):
      do {
        return .loaded(try await list(nil), request: request)
      } catch {
        return .loadFailed(Failure(error), request: request)
      }
    case .loadMore(let after):
      do {
        return .loadedMore(try await list(after), after: after)
      } catch {
        return .loadMoreFailed(after: after)
      }
    case .count:
      return (try? await list(nil)).map { .counted($0.unread) }
    case .markRead(let head):
      return (try? await markRead(MarkActivityReadRequest(upTo: head))).map { .counted($0.unread) }
    }
  }
}
