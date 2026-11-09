import Design

/// How tall the Inbox opens: a short state hugs its content like every other short sheet, the list
/// takes the whole sheet and scrolls itself.
public enum InboxLayout: Equatable {
  case short
  case list

  public init(_ sheet: InboxMachine.Sheet) {
    switch sheet {
    case .loaded(let page), .refreshing(let page), .stale(let page):
      self = page.items.isEmpty ? .short : .list
    case .idle, .loading, .unpaired, .failed: self = .short
    }
  }

  public var size: SheetSize {
    switch self {
    case .short: .fit
    case .list: .large
    }
  }

  /// The list is a `List`, so the sheet must not wrap it in a second scroll view; a fitted sheet
  /// measures its content through that scroll view.
  public var scrolls: Bool {
    switch self {
    case .short: true
    case .list: false
    }
  }
}
