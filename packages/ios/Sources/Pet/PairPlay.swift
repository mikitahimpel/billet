import DesignSystem
import Foundation

/// The play between two partners, kept apart from any scene so every scene can show it the same way.
///
/// Scenes read this and draw; they never decide who is waited on or what the streak is.
public struct PairPlay: Equatable, Sendable {
  public let device: String
  public private(set) var ledger = TreatLedger()
  /// Counts up each time this device pets the cat. A view reacts to each change.
  public private(set) var petsGiven = 0
  /// Counts up each time the partner's pet arrives.
  public private(set) var petsReceived = 0
  /// The reaction each note has received, by note ID. Both phones hold the same table.
  public private(set) var reactions: [UUID: Reaction] = [:]
  /// The name the pair gave the cat, once either of them has chosen one.
  public private(set) var catName: String?
  /// Where the room's light switch stands. The room keeps the last press from either partner.
  public private(set) var roomLight = RoomLight.standard

  /// What outlasts a launch for a pair with no room to ask.
  public struct Saved: Codable, Equatable, Sendable {
    public var ledger: TreatLedger
    public var reactions: [UUID: Reaction]
    public var catName: String?
    /// Missing from what older releases saved, which read as ``RoomLight/standard``.
    public var roomLight: RoomLight?
  }

  public var saved: Saved {
    Saved(ledger: ledger, reactions: reactions, catName: catName, roomLight: roomLight)
  }

  public init(device: String, saved: Saved? = nil) {
    self.device = device
    if let saved {
      ledger = saved.ledger
      reactions = saved.reactions
      catName = saved.catName
      roomLight = saved.roomLight ?? .standard
    }
  }

  public func status(on day: String) -> TreatLedger.Status {
    ledger.status(for: device, on: day)
  }

  public func streak(today: String, calendar: Calendar) -> Int {
    ledger.streak(today: today, calendar: calendar)
  }

  public mutating func petGiven() {
    petsGiven += 1
  }

  public mutating func petReceived() {
    petsReceived += 1
  }

  /// Records this device's treat for `day`. Returns false when it already gave one that day.
  public mutating func treatGiven(on day: String) -> Bool {
    guard status(on: day) == .neither || status(on: day) == .waitingOnMe else { return false }
    ledger.give(device: device, on: day)
    return true
  }

  /// Records the reaction this device sent to `note`.
  public mutating func reactionGiven(to note: UUID, _ reaction: Reaction) {
    reactions[note] = reaction
  }

  /// Takes the room's table and returns the reactions it added or changed.
  public mutating func reactionsReceived(_ table: [UUID: Reaction]) -> [UUID: Reaction] {
    let changed = table.filter { reactions[$0.key] != $0.value }
    reactions.merge(table) { _, new in new }
    return changed
  }

  /// Takes the name the room reports. The room keeps the first name, so it overrides a local one.
  public mutating func named(_ name: String) {
    catName = name
  }

  /// Sets the room's light, from this phone's switch or from the room's report.
  public mutating func light(_ light: RoomLight) {
    roomLight = light
  }

  public mutating func treatsReceived(_ days: [String: Set<String>]) {
    ledger.merge(days)
  }
}
