import Foundation
import Observation

/// A wrapped gift between the partners. The item travels by its catalog ID.
public struct Gift: Codable, Equatable, Identifiable, Sendable {
  public enum Direction: String, Codable, Sendable {
    /// Wrapped here and on its way to the partner's doormat.
    case outgoing
    /// On this phone's doormat.
    case incoming
  }

  public enum State: String, Codable, Sendable {
    case wrapped
    case opened
  }

  public let id: UUID
  public let itemID: String
  public let direction: Direction
  public var state: State

  public init(id: UUID = UUID(), itemID: String, direction: Direction, state: State = .wrapped) {
    self.id = id
    self.itemID = itemID
    self.direction = direction
    self.state = state
  }
}

/// The gifts on and off this phone's doormat. Opened gifts stay a moment as a record, up to a few.
public struct GiftBox: Codable, Equatable, Sendable {
  public static let keepOpened = 3

  public private(set) var gifts: [Gift]

  public init(gifts: [Gift] = []) {
    self.gifts = gifts
  }

  public mutating func add(_ gift: Gift) {
    guard !gifts.contains(where: { $0.id == gift.id }) else { return }
    gifts.append(gift)
    trim()
  }

  /// Opens a wrapped gift that is on this phone's doormat and returns its item. A gift opens once,
  /// and an outgoing gift is not this phone's to open.
  public mutating func unwrap(_ id: UUID) -> String? {
    guard let index = gifts.firstIndex(where: { $0.id == id }),
      gifts[index].direction == .incoming, gifts[index].state == .wrapped
    else { return nil }
    gifts[index].state = .opened
    let item = gifts[index].itemID
    trim()
    return item
  }

  /// The partner opened a gift this phone sent.
  public mutating func partnerOpened(_ id: UUID) {
    guard let index = gifts.firstIndex(where: { $0.id == id }),
      gifts[index].direction == .outgoing
    else { return }
    gifts[index].state = .opened
    trim()
  }

  public var waiting: [Gift] {
    gifts.filter { $0.direction == .incoming && $0.state == .wrapped }
  }

  private mutating func trim() {
    var opened = 0
    gifts = gifts.reversed().filter { gift in
      guard gift.state == .opened else { return true }
      opened += 1
      return opened <= Self.keepOpened
    }.reversed()
  }
}

/// The gift box, kept in `defaults`.
@MainActor
@Observable
public final class GiftBoxStore {
  public private(set) var box: GiftBox
  /// The gift unwrapped last, so a view can show the cat sitting in its box.
  public private(set) var lastUnwrapped: UUID?

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let key: String

  public init(defaults: UserDefaults = .standard, key: String = "labs.giftBox") {
    self.defaults = defaults
    self.key = key
    box =
      defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(GiftBox.self, from: $0) }
      ?? GiftBox()
  }

  public func add(_ gift: Gift) {
    box.add(gift)
    save()
  }

  /// The item inside, or nil when the gift cannot be opened.
  public func unwrap(_ id: UUID) -> String? {
    let item = box.unwrap(id)
    if item != nil {
      lastUnwrapped = id
      save()
    }
    return item
  }

  public func partnerOpened(_ id: UUID) {
    box.partnerOpened(id)
    save()
  }

  private func save() {
    defaults.set(try? JSONEncoder().encode(box), forKey: key)
  }
}
