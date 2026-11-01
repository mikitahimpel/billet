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

  public init(device: String) {
    self.device = device
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

  public mutating func treatsReceived(_ days: [String: Set<String>]) {
    ledger.merge(days)
  }
}
