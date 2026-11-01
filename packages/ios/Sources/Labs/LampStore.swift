import Foundation
import Observation

/// The colour of this phone's lamp, kept in `defaults`, and the partner's as last reported.
@MainActor
@Observable
public final class LampStore {
  public private(set) var mine: LampColour
  public private(set) var theirs: PartnerGlow?
  /// When this phone's lamp was put out, if it has been.
  public private(set) var goodnight: Date?

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let key: String
  @ObservationIgnored private var goodnightKey: String { key + ".goodnight" }

  public init(defaults: UserDefaults = .standard, key: String = "labs.lampColour") {
    self.defaults = defaults
    self.key = key
    goodnight = defaults.object(forKey: key + ".goodnight") as? Date
    mine = defaults.string(forKey: key).flatMap(LampColour.init(rawValue:)) ?? .standard
  }

  /// True while this phone's lamp is out.
  public func mineOut(at now: Date) -> Bool {
    LightsOut.isOut(since: goodnight, now: now)
  }

  public var theirsOut: Bool { theirs.map { !$0.lampOn } ?? false }

  public func night(at now: Date) -> LightsOut.Night {
    LightsOut.night(mineOut: mineOut(at: now), theirsOut: theirsOut)
  }

  public func sayGoodnight(at now: Date) {
    goodnight = now
    defaults.set(now, forKey: goodnightKey)
  }

  public func wakeUp() {
    goodnight = nil
    defaults.removeObject(forKey: goodnightKey)
  }

  public func choose(_ colour: LampColour) {
    mine = colour
    defaults.set(colour.rawValue, forKey: key)
  }

  public func partnerGlows(_ glow: PartnerGlow) {
    theirs = glow
  }
}
