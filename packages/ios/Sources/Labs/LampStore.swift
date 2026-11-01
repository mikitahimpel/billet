import Foundation
import Observation

/// The colour of this phone's lamp, kept in `defaults`, and the partner's as last reported.
@MainActor
@Observable
public final class LampStore {
  public private(set) var mine: LampColour
  public private(set) var theirs: PartnerGlow?

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let key: String

  public init(defaults: UserDefaults = .standard, key: String = "labs.lampColour") {
    self.defaults = defaults
    self.key = key
    mine = defaults.string(forKey: key).flatMap(LampColour.init(rawValue:)) ?? .standard
  }

  public func choose(_ colour: LampColour) {
    mine = colour
    defaults.set(colour.rawValue, forKey: key)
  }

  public func partnerGlows(_ glow: PartnerGlow) {
    theirs = glow
  }
}
