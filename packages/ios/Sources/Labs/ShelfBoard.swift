import CoreGraphics
import FeatureInbox
import Foundation

/// Where everything stands on the shelf board: the newest note forward, the rest along the shelves
/// newest first, and numbered empty slots for the next days of the streak after the last note.
struct ShelfBoard: Equatable {
  /// A note on a shelf. Its lean and height come from its id, so it stays as it is as notes arrive.
  struct Placement: Equatable, Identifiable {
    let note: NoteRecord
    let tilt: Double
    let isTall: Bool
    /// Older paper, a shade warmer, so a long shelf is not all one sheet.
    let isWarmPaper: Bool

    var id: UUID { note.id }

    init(note: NoteRecord) {
      self.note = note
      let bytes = withUnsafeBytes(of: note.id.uuid) { Array($0) }
      let steps = Double(bytes[0] % 7) / 6
      let lean = ShelfBoard.smallestTilt + steps * ShelfBoard.tiltRange
      tilt = bytes[1].isMultiple(of: 2) ? lean : -lean
      isTall = bytes[2].isMultiple(of: 3)
      isWarmPaper = bytes[3].isMultiple(of: 3)
    }
  }

  enum Item: Equatable, Identifiable {
    case note(Placement)
    /// An empty place for this day of the streak.
    case slot(day: Int)

    var id: String {
      switch self {
      case .note(let placement): placement.id.uuidString
      case .slot(let day): "slot-\(day)"
      }
    }
  }

  struct Shelf: Equatable, Identifiable {
    let id: Int
    let items: [Item]
    /// The whole week of the streak this shelf marks, once the streak has reached it.
    let milestone: Int?
  }

  static let smallestTilt = 0.8
  static let largestTilt = 3.5
  private static let tiltRange = largestTilt - smallestTilt
  /// Always at least this many days are left open, so the shelf looks ahead.
  static let leastSlots = 2
  static let gap: CGFloat = 10
  static let daysInMilestone = 7
  /// Below this many notes to a shelf, the cups need a shelf of their own.
  static let leastForCupsBeside = 3

  /// The note in front. `nil` until the first note exists.
  let forward: Placement?
  /// The shelf over the note in front.
  let above: Shelf?
  /// The shelves under the note in front.
  let below: [Shelf]
  /// How many things stand on a shelf.
  let capacity: Int
  let cupsBeside: Bool

  /// - Parameters:
  ///   - streak: The days the streak has reached. Slots start the day after.
  ///   - width: The usable width of a shelf.
  ///   - noteWidth: The width of a note on a shelf, which grows with the text size.
  init(notes: [NoteRecord], streak: Int, width: CGFloat, noteWidth: CGFloat) {
    let capacity = max(1, Int((width + Self.gap) / (max(noteWidth, 1) + Self.gap)))
    let newestFirst = notes.sorted { $0.date > $1.date }.map(Placement.init)
    let days = max(streak, 0)
    let onShelves = Array(newestFirst.dropFirst()).map(Item.note)
    var rows = Self.rows(of: onShelves, capacity: capacity)

    let open = capacity - (rows.last?.count ?? capacity)
    let leastSlots = min(Self.leastSlots, capacity)
    var slots = open >= leastSlots ? open : open + capacity
    if rows.isEmpty { slots = capacity }
    let items = (0..<slots).map { Item.slot(day: days + 1 + $0) }
    rows = Self.rows(of: rows.flatMap(\.self) + items, capacity: capacity)

    let shelves = rows.enumerated().map { index, row in
      let week = index * Self.daysInMilestone
      return Shelf(id: index, items: row, milestone: week > 0 && week <= days ? week : nil)
    }
    forward = newestFirst.first
    above = shelves.count > 1 ? shelves[0] : nil
    below = shelves.count > 1 ? Array(shelves.dropFirst()) : shelves
    self.capacity = capacity
    cupsBeside = capacity >= Self.leastForCupsBeside
  }

  /// The width of a note on a shelf of `width`. It grows with the text size, but a drawing holds no
  /// text, so it stops where two notes still fit side by side.
  static func noteWidth(scaled: CGFloat, width: CGFloat) -> CGFloat {
    min(scaled, (width - gap) / 2)
  }

  /// The gap that spreads a full shelf from edge to edge of `width`, never less than ``gap``.
  func spacing(width: CGFloat, noteWidth: CGFloat) -> CGFloat {
    guard capacity > 1 else { return Self.gap }
    let spare = width - CGFloat(capacity) * noteWidth
    return max(Self.gap, spare / CGFloat(capacity - 1))
  }

  /// Every shelf in the order it stands on the wall.
  var shelves: [Shelf] {
    (above.map { [$0] } ?? []) + below
  }

  private static func rows(of items: [Item], capacity: Int) -> [[Item]] {
    stride(from: 0, to: items.count, by: capacity).map {
      Array(items[$0..<min($0 + capacity, items.count)])
    }
  }
}
