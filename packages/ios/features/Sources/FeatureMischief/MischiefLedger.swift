import Foundation
import MischiefInterface
import Wire

/// One toy mouse a partner hid, as the journal tells it.
public struct MischiefHide: Codable, Equatable, Hashable, Sendable, Identifiable {
  /// The journal entry's id; the find names it.
  public let id: String
  public let by: String
  public let spot: MischiefSpot
  public let line: String?
  public let at: Date
  public var found: Found?

  public init(
    id: String, by: String, spot: MischiefSpot, line: String?, at: Date, found: Found? = nil
  ) {
    self.id = id
    self.by = by
    self.spot = spot
    self.line = line
    self.at = at
    self.found = found
  }

  public struct Found: Codable, Equatable, Hashable, Sendable {
    public let by: String
    public let at: Date
    public let tries: Int
    public let seconds: Int
  }
}

public enum MischiefStatus: Equatable, Sendable {
  case hidden
  case found(MischiefHide.Found)
  /// Nobody looked for three days, so the cat found it and left it by the door.
  case turnedUp(Date)
  /// Its hider hid another since.
  case replaced
}

/// Every hide and find in the pair's journal. The journal itself is read for three days only, but a mouse waits as
/// long as it takes, so this is kept apart from it.
public struct MischiefLedger: Codable, Equatable, Sendable {
  public static let catFindsAfter: TimeInterval = 3 * 86_400
  /// Hides that are over and still remembered, newest first.
  public static let keepOver = 20
  private static let keepOrphans = 50

  private var hides: [String: MischiefHide] = [:]
  /// Finds that arrived before the hide they name.
  private var orphans: [String: MischiefHide.Found] = [:]

  public init() {}

  /// Takes one journal entry in. Returns whether it changed anything.
  @discardableResult
  public mutating func apply(_ entry: CatEntry, now: Date = .now) -> Bool {
    let at = Date(timeIntervalSince1970: Double(entry.at) / 1000)
    switch entry.event {
    case .mouseHidden(let id, let line):
      guard let spot = MischiefSpot(rawValue: id), hides[entry.id.rawValue] == nil else {
        return false
      }
      var hide = MischiefHide(
        id: entry.id.rawValue, by: entry.by.rawValue, spot: spot,
        line: line.flatMap(MischiefLine.clean), at: at)
      if let found = orphans.removeValue(forKey: hide.id), found.by != hide.by {
        hide.found = found
      }
      hides[hide.id] = hide
      prune(now: now)
      return true
    case .mouseFound(let hidden, _, let tries, let seconds):
      let found = MischiefHide.Found(by: entry.by.rawValue, at: at, tries: tries, seconds: seconds)
      guard var hide = hides[hidden.rawValue] else {
        guard orphans[hidden.rawValue] == nil else { return false }
        orphans[hidden.rawValue] = found
        if orphans.count > Self.keepOrphans {
          orphans.removeValue(forKey: orphans.keys.sorted().first ?? "")
        }
        return true
      }
      guard hide.found == nil, hide.by != found.by else { return false }
      hide.found = found
      hides[hide.id] = hide
      prune(now: now)
      return true
    case .fed, .petted, .played, .watered, .noteShared, .gamePlayed, .slept, .shooed:
      return false
    }
  }

  public func status(of hide: MischiefHide, now: Date) -> MischiefStatus {
    if let found = hide.found { return .found(found) }
    if hides.values.contains(where: { $0.by == hide.by && ($0.at, $0.id) > (hide.at, hide.id) }) {
      return .replaced
    }
    let turnedUp = hide.at.addingTimeInterval(Self.catFindsAfter)
    return now >= turnedUp ? .turnedUp(turnedUp) : .hidden
  }

  /// The mouse `user` has hidden and nobody has found.
  public func open(hiddenBy user: String, now: Date) -> MischiefHide? {
    hides.values.filter { $0.by == user && status(of: $0, now: now) == .hidden }.max {
      $0.at < $1.at
    }
  }

  /// Hides that ended, by a find or the cat, newest first.
  public func over(now: Date, limit: Int = 5) -> [(hide: MischiefHide, status: MischiefStatus)] {
    Array(
      hides.values.compactMap { hide -> (hide: MischiefHide, status: MischiefStatus, end: Date)? in
        switch status(of: hide, now: now) {
        case .found(let found): (hide, .found(found), found.at)
        case .turnedUp(let at): (hide, .turnedUp(at), at)
        case .hidden, .replaced: nil
        }
      }
      .sorted { $0.end > $1.end }
      .prefix(limit)
      .map { ($0.hide, $0.status) })
  }

  private mutating func prune(now: Date) {
    let finished = over(now: now, limit: .max).map(\.hide.id)
    for id in finished.dropFirst(Self.keepOver) { hides.removeValue(forKey: id) }
    let replaced = hides.values.filter { status(of: $0, now: now) == .replaced }
    for hide in replaced { hides.removeValue(forKey: hide.id) }
  }
}
