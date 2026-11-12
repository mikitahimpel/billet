import Foundation
import Persistence
import ProfileInterface

/// What happened on the widgets and controls while the app was closed: pets waiting to reach Mochi and the date idea
/// the widget last drew.
public nonisolated struct WidgetActivity: Codable, Hashable, Sendable {
  public var lastPet: Date?
  /// Pets from outside the app that Mochi hasn't felt yet; the app takes them on its next launch.
  public var pendingPets = 0
  public var ideaID: Int?
  public var lastFed: Date?
  /// Meals from outside the app that her room hasn't seen yet.
  public var pendingFeeds = 0

  public init(
    lastPet: Date? = nil, pendingPets: Int = 0, ideaID: Int? = nil, lastFed: Date? = nil,
    pendingFeeds: Int = 0
  ) {
    self.lastPet = lastPet
    self.pendingPets = pendingPets
    self.ideaID = ideaID
    self.lastFed = lastFed
    self.pendingFeeds = pendingFeeds
  }

  /// A file saved before meals existed has no such keys.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    lastPet = try c.decodeIfPresent(Date.self, forKey: .lastPet)
    pendingPets = try c.decodeIfPresent(Int.self, forKey: .pendingPets) ?? 0
    ideaID = try c.decodeIfPresent(Int.self, forKey: .ideaID)
    lastFed = try c.decodeIfPresent(Date.self, forKey: .lastFed)
    pendingFeeds = try c.decodeIfPresent(Int.self, forKey: .pendingFeeds) ?? 0
  }

  /// How long the widget shows Mochi purring after a pet.
  public static let purrLength: TimeInterval = 60

  private static let file = "Couple/widget-activity.json"

  public static func load() -> WidgetActivity {
    SharedFile.read(WidgetActivity.self, from: file) ?? WidgetActivity()
  }

  public func save() { SharedFile.write(self, to: Self.file) }

  public func isPurring(at date: Date) -> Bool {
    guard let lastPet else { return false }
    return date >= lastPet && date < lastPet.addingTimeInterval(Self.purrLength)
  }

  public mutating func pet(at date: Date = .now) {
    lastPet = date
    pendingPets += 1
  }

  public mutating func takePendingPets() -> Int {
    defer { pendingPets = 0 }
    return pendingPets
  }

  public mutating func feed(at date: Date = .now) {
    lastFed = date
    pendingFeeds += 1
  }

  public mutating func takePendingFeeds() -> Int {
    defer { pendingFeeds = 0 }
    return pendingFeeds
  }
}
