import BilletKit
import DecorInterface

/// Arranging the room: which owned pieces stand where, and the edit in progress. Screen state is
/// one case; a drag carries where the piece came from, so letting go somewhere that does not fit
/// puts it back.
public enum DecorMachine: Machine {
  /// What the arranging works on.
  public struct Book: Equatable, Sendable {
    public var layout: DecorLayout
    /// Every shop piece the pair owns, placeable or not.
    public var owned: Set<String>

    public init(layout: DecorLayout = DecorLayout(), owned: Set<String> = []) {
      self.layout = layout
      self.owned = owned
    }

    public var closet: [DecorItem] { layout.closet(owned: owned) }
  }

  public enum State: Equatable, Sendable {
    /// Not arranging; the room shows the layout as it is.
    case off(Book)
    /// Arranging, nothing chosen: the closet is open.
    case closet(Book)
    /// A piece in the room is chosen.
    case selected(Book, item: String)
    /// A piece is being dragged: where it stood and where the finger has it.
    case moving(Book, item: String, from: Placement, to: Placement)

    public var book: Book {
      switch self {
      case .off(let book), .closet(let book), .selected(let book, _), .moving(let book, _, _, _):
        book
      }
    }

    public var isArranging: Bool {
      switch self {
      case .off: false
      case .closet, .selected, .moving: true
      }
    }

    /// The piece chosen or dragged.
    public var selection: String? {
      switch self {
      case .off, .closet: nil
      case .selected(_, let item), .moving(_, let item, _, _): item
      }
    }

    /// Where the room draws the chosen piece: under the finger while it is dragged.
    public var layout: DecorLayout {
      switch self {
      case .moving(let book, _, _, let to): book.layout.putting(to)
      case .off(let book), .closet(let book), .selected(let book, _): book.layout
      }
    }

    /// False while a dragged piece is somewhere it does not fit.
    public var isValid: Bool {
      switch self {
      case .moving(let book, _, _, let to): book.layout.accepts(to)
      case .off, .closet, .selected: true
      }
    }

    /// Why a dragged piece does not fit, for the UI to say; `.fits` otherwise.
    public var verdict: DecorLayout.Verdict {
      switch self {
      case .moving(let book, _, _, let to): book.layout.verdict(to)
      case .off, .closet, .selected: .fits
      }
    }

    /// Whether the chosen piece can be turned.
    public var canTurn: Bool {
      guard case .selected(let book, let item) = self,
        let placement = book.layout.placement(of: item)
      else { return false }
      return placement.surface == .floor
    }
  }

  public enum Event: Equatable, Sendable {
    /// The shop's owned set changed, or was read.
    case owned(Set<String>)
    /// The room read from where it is kept.
    case loaded(DecorLayout)
    /// Start arranging, with `item` chosen when it is given: a piece in the closet goes into the room
    /// first.
    case opened(item: String?)
    case closed
    /// A piece in the closet was tapped.
    case closetTapped(String)
    /// A piece in the room was tapped.
    case roomTapped(String)
    /// Empty floor or wall was tapped.
    case emptyTapped
    case dragBegan(String)
    case dragged(Placement)
    case dropped
    case dragCancelled
    case turned
    case stored
  }

  public enum Output: Equatable, Sendable {
    case save(DecorLayout)
    case feedback(Feedback)
  }

  public enum Feedback: Equatable, Sendable {
    /// A piece went into the room.
    case placed
    /// There is no room for the piece in the closet's tap, or a turn that would not fit.
    case blocked
    /// A drag ended where it does not fit.
    case rejected
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.off, .owned(let owned)), (.closet, .owned(let owned)), (.selected, .owned(let owned)),
      (.moving, .owned(let owned)):
      return owning(owned, in: state)

    case (.off, .loaded(let layout)), (.closet, .loaded(let layout)),
      (.selected, .loaded(let layout)),
      (.moving, .loaded(let layout)):
      return loading(layout, in: state)

    case (.off(let book), .opened(let item)), (.closet(let book), .opened(let item)),
      (.selected(let book, _), .opened(let item)):
      return opening(item, in: book)

    case (.moving, .opened):
      return (state, [])

    case (.off, .closed):
      return (state, [])
    case (.closet(let book), .closed), (.selected(let book, _), .closed):
      return (.off(book), [])
    case (.moving(let book, _, _, _), .closed):
      return (.off(book), [])

    case (.closet(let book), .closetTapped(let item)),
      (.selected(let book, _), .closetTapped(let item)):
      return placing(item, in: book)

    case (.off, .closetTapped), (.moving, .closetTapped):
      return (state, [])

    case (.closet(let book), .roomTapped(let item)),
      (.selected(let book, _), .roomTapped(let item)):
      return book.layout.isPlaced(item) ? (.selected(book, item: item), []) : (state, [])

    case (.off, .roomTapped), (.moving, .roomTapped):
      return (state, [])

    case (.selected(let book, _), .emptyTapped):
      return (.closet(book), [])
    case (.off, .emptyTapped), (.closet, .emptyTapped), (.moving, .emptyTapped):
      return (state, [])

    case (.closet(let book), .dragBegan(let item)), (.selected(let book, _), .dragBegan(let item)):
      guard let from = book.layout.placement(of: item) else { return (state, []) }
      return (.moving(book, item: item, from: from, to: from), [])

    case (.off, .dragBegan), (.moving, .dragBegan):
      return (state, [])

    case (.moving(let book, let item, let from, _), .dragged(let to)):
      guard to.item == item else { return (state, []) }
      return (.moving(book, item: item, from: from, to: to), [])

    case (.off, .dragged), (.closet, .dragged), (.selected, .dragged):
      return (state, [])

    case (.moving(let book, let item, _, let to), .dropped):
      guard book.layout.accepts(to) else {
        return (.selected(book, item: item), [.feedback(.rejected)])
      }
      var next = book
      next.layout = book.layout.putting(to)
      return (.selected(next, item: item), [.save(next.layout)])

    case (.off, .dropped), (.closet, .dropped), (.selected, .dropped):
      return (state, [])

    case (.moving(let book, let item, _, _), .dragCancelled):
      return (.selected(book, item: item), [])

    case (.off, .dragCancelled), (.closet, .dragCancelled), (.selected, .dragCancelled):
      return (state, [])

    case (.selected(let book, let item), .turned):
      guard let placement = book.layout.placement(of: item), placement.surface == .floor else {
        return (state, [])
      }
      let turned = placement.turned
      guard book.layout.accepts(turned) else { return (state, [.feedback(.blocked)]) }
      var next = book
      next.layout = book.layout.putting(turned)
      return (.selected(next, item: item), [.save(next.layout)])

    case (.off, .turned), (.closet, .turned), (.moving, .turned):
      return (state, [])

    case (.selected(let book, let item), .stored):
      var next = book
      next.layout = book.layout.storing(item)
      return (.closet(next), [.save(next.layout)])

    case (.off, .stored), (.closet, .stored), (.moving, .stored):
      return (state, [])
    }
  }

  private static func with(_ book: Book, in state: State) -> State {
    switch state {
    case .off: .off(book)
    case .closet: .closet(book)
    case .selected(_, let item):
      book.layout.isPlaced(item) ? .selected(book, item: item) : .closet(book)
    case .moving(_, let item, let from, let to): .moving(book, item: item, from: from, to: to)
    }
  }

  private static func owning(_ owned: Set<String>, in state: State) -> (State, [Output]) {
    var book = state.book
    guard book.owned != owned else { return (state, []) }
    book.owned = owned
    let settled = book.layout.keeping(owned: owned).settled(owned: owned)
    let changed = settled != book.layout
    book.layout = settled
    return (with(book, in: state), changed ? [.save(settled)] : [])
  }

  private static func loading(_ layout: DecorLayout, in state: State) -> (State, [Output]) {
    var book = state.book
    let settled = layout.keeping(owned: book.owned).settled(owned: book.owned)
    guard settled != book.layout else { return (state, []) }
    book.layout = settled
    let next: State
    switch state {
    case .moving(_, let item, _, _):
      next = book.layout.isPlaced(item) ? .selected(book, item: item) : .closet(book)
    case .off, .closet, .selected: next = with(book, in: state)
    }
    return (next, settled == layout ? [] : [.save(settled)])
  }

  private static func opening(_ item: String?, in book: Book) -> (State, [Output]) {
    guard let item, book.owned.contains(item), DecorItem.item(shopID: item) != nil else {
      return (.closet(book), [])
    }
    if book.layout.isPlaced(item) { return (.selected(book, item: item), []) }
    return placing(item, in: book)
  }

  private static func placing(_ item: String, in book: Book) -> (State, [Output]) {
    guard book.owned.contains(item), !book.layout.isPlaced(item) else {
      return book.layout.isPlaced(item) ? (.selected(book, item: item), []) : (.closet(book), [])
    }
    guard let spot = book.layout.defaultPlacement(for: item) else {
      return (.closet(book), [.feedback(.blocked)])
    }
    var next = book
    next.layout = book.layout.putting(spot)
    return (.selected(next, item: item), [.save(next.layout), .feedback(.placed)])
  }
}
