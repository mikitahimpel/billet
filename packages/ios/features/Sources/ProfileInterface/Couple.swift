import Foundation

/// The pair on the server: which account holds each monogram.
public struct PairMembers: Codable, Hashable, Sendable {
  public var pairID: String
  /// User ids by monogram.
  public var users: [String: String]

  public init(pairID: String, users: [String: String]) {
    self.pairID = pairID
    self.users = users
  }
}

/// The two partners on this device and the day they got together. Monograms and names are for
/// display; once paired, `pair` ties each monogram to an account.
public struct Couple: Codable, Hashable, Sendable {
  /// Monograms, first partner first.
  public var partners: [String]
  public var togetherSince: Date
  /// Which partner is holding the phone: the signed-in account once paired, switched on the Us tab
  /// before that.
  public var viewer: String
  /// By monogram; the monograms stay their ids everywhere else.
  public var names: [String: String]? = nil
  /// Nil until this phone is paired on a server.
  public var pair: PairMembers? = nil

  public init(
    partners: [String], togetherSince: Date, viewer: String, names: [String: String]? = nil,
    pair: PairMembers? = nil
  ) {
    self.partners = partners
    self.togetherSince = togetherSince
    self.viewer = viewer
    self.names = names
    self.pair = pair
  }

  public var other: String { viewer == partners[0] ? partners[1] : partners[0] }

  /// The holder's own name, or their monogram until they set one. Each phone keeps only its holder's name, so
  /// the other one, unnamed here, is "Partner" rather than a letter that isn't theirs, paired or not.
  public func name(of partner: String) -> String {
    if let name = chosenName(of: partner) { return name }
    return isUnknownPartner(partner) ? "Partner" : partner
  }

  /// The partner whose name this phone doesn't have: drawn without an initial.
  public func isUnknownPartner(_ partner: String) -> Bool {
    partner != viewer && chosenName(of: partner) == nil
  }

  private func chosenName(of partner: String) -> String? {
    names?[partner].flatMap { $0.isEmpty ? nil : $0 }
  }

  /// Day one counts as day 1.
  public func daysTogether(on day: Date = .now) -> Int {
    let cal = Calendar.current
    let days =
      cal.dateComponents(
        [.day], from: cal.startOfDay(for: togetherSince), to: cal.startOfDay(for: day)
      )
      .day ?? 0
    return days + 1
  }

  /// First launch is day 1 until the couple sets their date.
  public static func starter(now: Date = .now) -> Couple {
    Couple(partners: ["L", "M"], togetherSince: Calendar.current.startOfDay(for: now), viewer: "L")
  }
}

extension Notification.Name {
  /// The couple was saved by another `CoupleStore`, so the one on screen reads it again.
  public static let coupleChanged = Notification.Name("com.ourio.app.couple-changed")
}
