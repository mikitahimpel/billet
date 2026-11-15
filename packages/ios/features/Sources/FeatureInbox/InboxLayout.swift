import Design

/// How the Inbox lays out: every state opens the sheet at full height, so the first page, an empty Inbox or an error
/// lands in the sheet the placeholder opened and nothing jumps. The list scrolls itself; a short state stands in the
/// middle of the free space.
public enum InboxLayout: Equatable {
  case short
  case list

  public init(_ sheet: InboxMachine.Sheet) {
    switch sheet {
    case .loaded(let page), .refreshing(let page), .stale(let page):
      self = page.items.isEmpty ? .short : .list
    case .idle, .loading: self = .list
    case .unpaired, .failed: self = .short
    }
  }

  public var size: SheetSize { .large }

  /// Both bring their own scroll view: the list's carries the notice above it, a short state's centres it.
  public var scrolls: Bool { false }
}
