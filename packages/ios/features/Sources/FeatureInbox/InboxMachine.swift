import BilletKit
import Transport
import Wire

/// The pair's activity, newest first: pages from the server, the unread count for the header's
/// badge, and the read mark for this person.
///
/// `request` counts first-page loads, so an answer to an earlier one changes nothing.
public enum InboxMachine: Machine {
  /// What the sheet has loaded.
  public struct Page: Equatable, Sendable {
    public var items: [ActivityItem]
    /// The cursor of the next, older page; nil on the last one.
    public var next: String?
    /// The newest item's cursor, as the server gave it with the first page: the read mark moves up
    /// to it.
    var head: String?
    /// Items that were unread when the Inbox was last opened; they stay marked until it is opened
    /// again.
    public var fresh: Set<String>

    public init(
      items: [ActivityItem], next: String? = nil, head: String? = nil, fresh: Set<String> = []
    ) {
      self.items = items
      self.next = next
      self.head = head
      self.fresh = fresh
    }
  }

  public enum Sheet: Equatable, Sendable {
    case idle
    case loading
    /// No partner yet: the server has no room to read from.
    case unpaired
    /// Nothing could be loaded.
    case failed
    case loaded(Page)
    /// Opened again; the last page shows until the new one arrives.
    case refreshing(Page)
    /// Loading again failed; the last page stays.
    case stale(Page)

    /// The page the sheet lists, if it lists one.
    public var page: Page? {
      switch self {
      case .loaded(let page), .refreshing(let page), .stale(let page): page
      case .idle, .loading, .unpaired, .failed: nil
      }
    }
  }

  public struct State: Equatable, Sendable {
    public var sheet: Sheet
    public var unread: Int
    var request: Int
    /// The cursor of the older page being loaded.
    var loadingAfter: String?

    public static let initial = State(sheet: .idle, unread: 0, request: 0, loadingAfter: nil)
  }

  public enum Failure: Equatable, Sendable {
    case unpaired
    case unavailable

    public init(_ error: TransportError) {
      self = error == .api(.notFound) ? .unpaired : .unavailable
    }
  }

  public enum Event: Equatable, Sendable {
    /// The sheet opened or was pulled to refresh.
    case opened
    /// The last row came into view.
    case reachedEnd
    /// Only the count, for the badge while the Inbox is closed.
    case countRequested
    /// The count the room socket reports, or the server after a read mark or a count.
    case counted(Int)
    case loaded(ActivityResponse, request: Int)
    case loadFailed(Failure, request: Int)
    case loadedMore(ActivityResponse, after: String)
    case loadMoreFailed(after: String)
  }

  public enum Output: Equatable, Sendable {
    case loadFirst(request: Int)
    case loadMore(after: String)
    case count
    case markRead(upTo: String)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    var next = state
    switch event {
    case .opened:
      next.request += 1
      next.loadingAfter = nil
      if let page = state.sheet.page, !page.items.isEmpty {
        next.sheet = .refreshing(page)
      } else {
        next.sheet = .loading
      }
      return (next, [.loadFirst(request: next.request)])

    case .reachedEnd:
      guard case .loaded(let page) = state.sheet, let after = page.next,
        state.loadingAfter == nil
      else { return (state, []) }
      next.loadingAfter = after
      return (next, [.loadMore(after: after)])

    case .countRequested:
      return (state, [.count])

    case .counted(let count):
      next.unread = count
      return (next, [])

    case .loaded(let response, let request):
      guard request == state.request, state.sheet.isLoadingFirst else { return (state, []) }
      let page = Page(
        items: response.items, next: response.next,
        head: response.head ?? response.items.first?.cursor,
        fresh: unreadIDs(in: response.items, count: response.unread))
      next.sheet = .loaded(page)
      next.unread = response.unread
      guard response.unread > 0, let head = page.head else { return (next, []) }
      return (next, [.markRead(upTo: head)])

    case .loadFailed(let failure, let request):
      guard request == state.request, state.sheet.isLoadingFirst else { return (state, []) }
      switch failure {
      case .unpaired:
        next.sheet = .unpaired
      case .unavailable:
        if let page = state.sheet.page, !page.items.isEmpty {
          next.sheet = .stale(page)
        } else {
          next.sheet = .failed
        }
      }
      return (next, [])

    case .loadedMore(let response, let after):
      guard after == state.loadingAfter, case .loaded(var page) = state.sheet else {
        return (state, [])
      }
      let known = Set(page.items.map(\.id))
      page.items += response.items.filter { !known.contains($0.id) }
      page.next = response.next
      next.sheet = .loaded(page)
      next.loadingAfter = nil
      return (next, [])

    case .loadMoreFailed(let after):
      guard after == state.loadingAfter else { return (state, []) }
      next.loadingAfter = nil
      return (next, [])
    }
  }

  /// The newest `count` items someone else made: the server counts only those above the read mark,
  /// and they are always the newest.
  public static func unreadIDs(in items: [ActivityItem], count: Int) -> Set<String> {
    Set(items.lazy.filter { $0.actor != .me }.prefix(count).map(\.id))
  }
}

extension InboxMachine.Sheet {
  var isLoadingFirst: Bool {
    switch self {
    case .loading, .refreshing: true
    case .idle, .unpaired, .failed, .loaded, .stale: false
    }
  }
}
