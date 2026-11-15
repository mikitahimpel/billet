import DecorInterface
import Transport
import Wire

extension DecorLayout {
  /// What the player did between `old` and this layout, as `docs/analytics.md` counts it: a piece
  /// that came into a room was placed, one that left for the closet was put away, one that stands
  /// elsewhere or turned was moved.
  public func events(since old: DecorLayout) -> [ClientEvent] {
    let before = old.shown
    let after = shown
    var events: [ClientEvent] = []
    for (item, placement) in after.sorted(by: { $0.key < $1.key }) {
      guard let id = ClientEvent.detail(from: item) else { continue }
      if let earlier = before[item] {
        if earlier != placement { events.append(ClientEvent(.roomItemMoved, detail: id)) }
      } else {
        events.append(ClientEvent(.roomItemPlaced, detail: id))
      }
    }
    for item in before.keys.sorted() where after[item] == nil {
      guard let id = ClientEvent.detail(from: item) else { continue }
      events.append(ClientEvent(.roomItemPutAway, detail: id))
    }
    return events
  }

  private var shown: [String: Placement] {
    Dictionary((placements + standing).map { ($0.item, $0) }, uniquingKeysWith: { a, _ in a })
  }
}

/// The layout the counts compare against. Only a save while the player is arranging is counted; a
/// save of the room settling around a new purchase or the partner's layout only moves the baseline.
@MainActor
final class DecorEventLog {
  private var last: DecorLayout
  private let events: EventReporter
  weak var store: DecorStore?

  init(_ layout: DecorLayout, events: EventReporter) {
    last = layout
    self.events = events
  }

  func saved(_ layout: DecorLayout) {
    if store?.state.isArranging == true {
      for event in layout.events(since: last) { events(event) }
    }
    last = layout
  }

  func kept(_ layout: DecorLayout) {
    last = layout
  }
}
