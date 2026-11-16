import Foundation

/// What the server has of the pair: each member's display name and the pair's day.
public struct PairProfile: Equatable, Sendable {
  public var myName: String?
  public var partnerName: String?
  /// Set by a partner; nil until one does.
  public var togetherSince: Date?
  /// When the pair formed, which counts as day one until a partner sets the day.
  public var pairedAt: Date?

  public init(
    myName: String? = nil, partnerName: String? = nil, togetherSince: Date? = nil,
    pairedAt: Date? = nil
  ) {
    self.myName = myName
    self.partnerName = partnerName
    self.togetherSince = togetherSince
    self.pairedAt = pairedAt
  }

  /// What this phone tells the server after taking its profile.
  public enum Push: Equatable, Sendable {
    case name(String?)
    /// `ifUnset`: the day chosen before pairing, which never replaces a partner's.
    case day(Date, ifUnset: Bool)
  }

  public static let nameMaxScalars = 40

  /// The name as the server takes it: trimmed, no control characters, at most 40 characters; nil
  /// when nothing is left.
  public static func displayName(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let kept = String(
      String.UnicodeScalarView(
        raw.unicodeScalars.filter { $0.properties.generalCategory != .control }))
    let trimmed = String(
      String.UnicodeScalarView(
        kept.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.prefix(nameMaxScalars))
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// YYYY-MM-DD in `calendar`'s time zone.
  public static func localDay(_ date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
  }

  /// The start of that day in `calendar`'s time zone; nil for anything but YYYY-MM-DD.
  public static func date(localDay: String, calendar: Calendar = .current) -> Date? {
    let parts = localDay.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, localDay.count == 10 else { return nil }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }
}

extension Couple {
  /// Takes the server's profile into the couple: the partner's name and the pair's day win when
  /// the server has them. The holder's own name is theirs, so a name the server lacks or holds
  /// differently is pushed; with none here, the server's is kept. A day the holder chose before
  /// pairing is pushed for a pair that has none, else the pair counts from the day it formed.
  public func merging(_ server: PairProfile, calendar: Calendar = .current) -> (
    Couple, [PairProfile.Push]
  ) {
    var couple = self
    var pushes: [PairProfile.Push] = []
    var names = couple.names ?? [:]
    if let partnerName = PairProfile.displayName(server.partnerName) { names[other] = partnerName }
    let mine = PairProfile.displayName(names[viewer])
    if let mine {
      if mine != server.myName { pushes.append(.name(mine)) }
    } else if let theirs = PairProfile.displayName(server.myName) {
      names[viewer] = theirs
    }
    if names != (couple.names ?? [:]) { couple.names = names }
    if let day = server.togetherSince {
      couple.togetherSince = calendar.startOfDay(for: day)
      couple.togetherSinceChosen = nil
    } else if couple.togetherSinceChosen == true {
      pushes.append(.day(couple.togetherSince, ifUnset: true))
    } else if let pairedAt = server.pairedAt {
      couple.togetherSince = calendar.startOfDay(for: pairedAt)
    }
    return (couple, pushes)
  }
}
