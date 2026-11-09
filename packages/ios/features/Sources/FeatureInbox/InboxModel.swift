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

  /// - Parameter timeout: How long the first page may take before the sheet says it couldn't load;
  ///   a stalled connection would otherwise keep it loading.
  public init(
    list: @escaping List, markRead: @escaping MarkRead, timeout: Duration = .seconds(15)
  ) {
    store = Store(initial: .initial) { output in
      await InboxMachine.run(output, list: list, markRead: markRead, timeout: timeout)
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
  static func run(
    _ output: Output, list: @escaping InboxModel.List, markRead: InboxModel.MarkRead,
    timeout: Duration
  ) async -> Event? {
    switch output {
    case .loadFirst(let request):
      return await withTaskGroup(of: Event.self) { group in
        group.addTask {
          do throws(TransportError) {
            return .loaded(try await list(nil), request: request)
          } catch {
            return .loadFailed(Failure(error), request: request)
          }
        }
        group.addTask {
          try? await Task.sleep(for: timeout)
          return .loadFailed(.unavailable, request: request)
        }
        let first = await group.next() ?? .loadFailed(.unavailable, request: request)
        group.cancelAll()
        return first
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
