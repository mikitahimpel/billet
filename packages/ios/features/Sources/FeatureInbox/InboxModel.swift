import BilletKit
import Observation
import Synchronization
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
      // Two unstructured tasks, not a group: a group waits for a request that ignores cancellation.
      let first = FirstEvent()
      return await withCheckedContinuation { continuation in
        first.set(continuation)
        let load = Task {
          do throws(TransportError) {
            first.resume(.loaded(try await list(nil), request: request))
          } catch {
            first.resume(.loadFailed(Failure(error), request: request))
          }
        }
        Task {
          try? await Task.sleep(for: timeout)
          load.cancel()
          first.resume(.loadFailed(.unavailable, request: request))
        }
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

/// Resumes its continuation with the first event it is given; later ones are dropped.
private final class FirstEvent: Sendable {
  private let continuation = Mutex<CheckedContinuation<InboxMachine.Event?, Never>?>(nil)

  func set(_ continuation: CheckedContinuation<InboxMachine.Event?, Never>) {
    self.continuation.withLock { $0 = continuation }
  }

  func resume(_ event: InboxMachine.Event) {
    let waiting = continuation.withLock { value in
      defer { value = nil }
      return value
    }
    waiting?.resume(returning: event)
  }
}
