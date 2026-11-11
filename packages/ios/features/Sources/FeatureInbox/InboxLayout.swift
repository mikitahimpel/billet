import Design

/// How tall the Inbox opens: a short state hugs its content like every other short sheet, the list
/// (and its placeholder while loading) takes the whole sheet and scrolls itself.
public enum InboxLayout: Equatable {
  case short
  case list

  public init(_ sheet: InboxMachine.Sheet) {
    switch sheet {
    case .loaded(let page), .refreshing(let page), .stale(let page):
      self = page.items.isEmpty ? .short : .list
    // Loading opens as the list does, so the first page lands without the sheet changing height.
    case .idle, .loading: self = .list
    case .unpaired, .failed: self = .short
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
