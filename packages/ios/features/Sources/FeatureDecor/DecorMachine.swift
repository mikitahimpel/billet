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
    /// The layout before the player's last change, for Undo.
    public var undo: DecorLayout?
    /// What the last event came to, when the player should be told.
    public var notice: Notice?
    /// The room being arranged: its closet, its fit rules and its reset.
    public var space: DecorSpace = .living

    public var room: DecorRoom { space == .living ? .home : .bedroom }

    public init(layout: DecorLayout = DecorLayout(), owned: Set<String> = []) {
      self.layout = layout
      self.owned = owned
    }

    public var closet: [DecorItem] { layout.closet(owned: owned, in: room) }

    /// A piece the pair can place here: one it owns, or this room's own furniture.
    public func has(_ item: String) -> Bool {
      guard let known = DecorItem.item(shopID: item) else { return false }
      if let base = known.base { return base.space == space }
      return owned.contains(item)
    }
  }

  public enum Notice: Equatable, Sendable {
    /// A turn fits nowhere in the room; the piece can only be put away.
    case noRoomToTurn(String)
    /// The turn fitted only at another spot, which the piece slid to.
    case slid
    /// A drop swapped two pieces, or moved one aside.
    case swapped
    /// A drop fits nowhere.
    case rejected
    /// Putting it away would leave her no bed or sofa.
    case lastRest
    case reset
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

    /// False while a dragged piece is somewhere it does not fit and no swap or nudge makes room.
    public var isValid: Bool {
      switch self {
      case .moving(let book, _, _, let to):
        if case .rejected = book.layout.dropping(to, in: book.room) { false } else { true }
      case .off, .closet, .selected: true
      }
    }

    /// Why a dragged piece does not fit, for the UI to say; `.fits` otherwise.
    public var verdict: DecorLayout.Verdict {
      switch self {
      case .moving(let book, _, _, let to): book.layout.verdict(to, in: book.room)
      case .off, .closet, .selected: .fits
      }
    }

    /// Where the dragged piece stood before the finger took it.
    public var origin: Placement? {
      if case .moving(_, _, let from, _) = self { from } else { nil }
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
    /// The pair's layout as the server holds it (a partner's change, or this phone's own refused): it replaces the
    /// placements and leaves what was put in the closet.
    ///
    /// `stowed` is the room's own furniture it put away; nil from a server that does not know it, which leaves
    /// this phone's.
    case remote([Placement], stowed: Set<String>? = nil)
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
    /// A further 45 degrees.
    case turnedFine
    case stored
    /// The room's own furniture back where it stood, and what was bought where it goes by itself.
    case resetRoom
    /// The last change taken back.
    case undone
    /// The room on screen changed: what is chosen or dragged is let go and the closet is that room's.
    case roomChanged(DecorSpace)
  }

  public enum Output: Equatable, Sendable {
    /// Keep it and tell the server.
    case save(DecorLayout)
    /// Keep it on this phone only: it came from the server.
    case keep(DecorLayout)
    case feedback(Feedback)
  }

  public enum Feedback: Equatable, Sendable {
    /// A piece went into the room.
    case placed
    /// There is no room for the piece in the closet's tap.
    case blocked
    /// A drag ended where it does not fit.
    case rejected
    /// A turn did not fit where the piece stood, so it slid to the nearest spot that does.
    case slid
    /// No spot in the room fits the turned piece: it can only be put away.
    case noRoomToTurn
    /// A drop changed two pieces' places.
    case swapped
    /// Putting it away would leave her no bed or sofa.
    case lastRest
    case reset
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    let (next, outputs) = step(state, event)
    var book = next.book
    book.notice = nil
    for output in outputs {
      guard case .feedback(let feedback) = output else { continue }
      switch feedback {
      case .noRoomToTurn: book.notice = state.selection.map { .noRoomToTurn($0) }
      case .slid: book.notice = .slid
      case .swapped: book.notice = .swapped
      case .rejected: book.notice = .rejected
      case .lastRest: book.notice = .lastRest
      case .reset: book.notice = .reset
      case .placed, .blocked: break
      }
    }
    let changing: Bool
    switch event {
    case .closetTapped, .dropped, .turned, .turnedFine, .stored, .resetRoom: changing = true
    case .owned, .loaded, .remote, .opened, .closed, .roomTapped, .emptyTapped, .dragBegan,
      .dragged,
      .dragCancelled, .undone, .roomChanged:
      changing = false
    }
    if case .undone = event {
      book.undo = nil
    } else if !changing, next.book.layout != state.book.layout {
      book.undo = nil
    } else if changing, next.book.layout != state.book.layout {
      book.undo = state.book.layout
    } else {
      book.undo = state.book.undo
    }
    if book == next.book { return (next, outputs) }
    return (with(book, in: next), outputs)
  }

  private static func step(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.off, .owned(let owned)), (.closet, .owned(let owned)), (.selected, .owned(let owned)),
      (.moving, .owned(let owned)):
      return owning(owned, in: state)

    case (.off, .loaded(let layout)), (.closet, .loaded(let layout)),
      (.selected, .loaded(let layout)),
      (.moving, .loaded(let layout)):
      return loading(layout, in: state)

    case (.off, .remote(let spots, let stowed)), (.closet, .remote(let spots, let stowed)),
      (.selected, .remote(let spots, let stowed)), (.moving, .remote(let spots, let stowed)):
      return receiving(spots, stowed: stowed, in: state)

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
      return (.moving(book, item: item, from: from, to: DecorLayout.insideRoom(to)), [])

    case (.off, .dragged), (.closet, .dragged), (.selected, .dragged):
      return (state, [])

    case (.moving(let book, let item, _, let to), .dropped):
      var next = book
      switch book.layout.dropping(to, in: book.room) {
      case .rejected:
        return (.selected(book, item: item), [.feedback(.rejected)])
      case .fits(let layout):
        next.layout = layout
        return (.selected(next, item: item), [.save(layout)])
      case .slid(let layout, _):
        next.layout = layout
        return (.selected(next, item: item), [.save(layout), .feedback(.slid)])
      case .swapped(let layout, _), .nudged(let layout, _, _):
        next.layout = layout
        return (.selected(next, item: item), [.save(layout), .feedback(.swapped)])
      }

    case (.off, .dropped), (.closet, .dropped), (.selected, .dropped):
      return (state, [])

    case (.moving(let book, let item, _, _), .dragCancelled):
      return (.selected(book, item: item), [])

    case (.off, .dragCancelled), (.closet, .dragCancelled), (.selected, .dragCancelled):
      return (state, [])

    case (.selected(let book, let item), .turned), (.selected(let book, let item), .turnedFine):
      var next = book
      switch book.layout.turning(item, byEighths: event == .turnedFine ? 1 : 2, in: book.room) {
      case nil: return (state, [])
      case .turned(let layout):
        next.layout = layout
        return (.selected(next, item: item), [.save(layout)])
      case .slid(let layout, _):
        next.layout = layout
        return (.selected(next, item: item), [.save(layout), .feedback(.slid)])
      case .noRoom:
        return (state, [.feedback(.noRoomToTurn)])
      }

    case (.off, .turned), (.closet, .turned), (.moving, .turned), (.off, .turnedFine),
      (.closet, .turnedFine), (.moving, .turnedFine):
      return (state, [])

    case (.selected(let book, let item), .stored):
      guard book.layout.canStore(item) else { return (state, [.feedback(.lastRest)]) }
      var next = book
      next.layout = book.layout.storing(item)
      return (.closet(next), [.save(next.layout)])

    case (.off, .stored), (.closet, .stored), (.moving, .stored):
      return (state, [])

    case (.closet(let book), .resetRoom), (.selected(let book, _), .resetRoom):
      var next = book
      next.layout = book.layout.reset(owned: book.owned, in: book.room)
      guard next.layout != book.layout else { return (.closet(book), []) }
      return (.closet(next), [.save(next.layout), .feedback(.reset)])

    case (.off, .resetRoom), (.moving, .resetRoom):
      return (state, [])

    case (.closet(let book), .undone), (.selected(let book, _), .undone):
      guard let before = book.undo else { return (state, []) }
      var next = book
      next.layout = before
      return (.closet(next), [.save(before)])

    case (.off, .undone), (.moving, .undone):
      return (state, [])

    case (.off(var book), .roomChanged(let space)):
      book.space = space
      return (.off(book), [])
    case (.closet(var book), .roomChanged(let space)),
      (.selected(var book, _), .roomChanged(let space)),
      (.moving(var book, _, _, _), .roomChanged(let space)):
      // The shell says the room on screen again whenever its view settles; only another room lets go.
      guard book.space != space else { return (state, []) }
      book.space = space
      return (.closet(book), [])
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

  private static func receiving(_ spots: [Placement], stowed: Set<String>?, in state: State)
    -> (State, [Output])
  {
    var book = state.book
    let settled = book.layout.replacing(placements: spots, stowed: stowed).keeping(
      owned: book.owned
    )
    .settled(owned: book.owned)
    guard settled != book.layout else { return (state, []) }
    book.layout = settled
    let next: State
    switch state {
    case .moving(_, let item, _, _):
      next = book.layout.isPlaced(item) ? .selected(book, item: item) : .closet(book)
    case .off, .closet, .selected: next = with(book, in: state)
    }
    // A piece the server did not know of, such as a new purchase, goes up as a change.
    let known = Set(spots.map(\.item))
    let local = settled.placements.contains { !known.contains($0.item) }
    return (next, [local ? .save(settled) : .keep(settled)])
  }

  private static func opening(_ item: String?, in book: Book) -> (State, [Output]) {
    guard let item, book.has(item) else {
      return (.closet(book), [])
    }
    if book.layout.isPlaced(item) { return (.selected(book, item: item), []) }
    return placing(item, in: book)
  }

  private static func placing(_ item: String, in book: Book) -> (State, [Output]) {
    guard book.has(item), !book.layout.isPlaced(item) else {
      return book.layout.isPlaced(item) ? (.selected(book, item: item), []) : (.closet(book), [])
    }
    guard let spot = book.layout.defaultPlacement(for: item, in: book.room) else {
      return (.closet(book), [.feedback(.blocked)])
    }
    var next = book
    next.layout = book.layout.putting(spot)
    return (.selected(next, item: item), [.save(next.layout), .feedback(.placed)])
  }
}
