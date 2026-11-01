import Foundation

/// One experiment the owner can switch on or off in Settings. The raw value is the key it is
/// stored under, beside the widget features.
///
/// An experiment that cannot get in the way of drawing, sending and reading notes starts on. The
/// ones that stand in for the partner, or change what the cat does, start off.
public enum LabExperiment: String, CaseIterable, Codable, Sendable, FeatureFlag {
  case fakePartner
  case overnightStay

  public enum Group: CaseIterable, Sendable {
    case demo
    case cat

    public var title: String {
      switch self {
      case .demo: "Try it alone"
      case .cat: "The cat"
      }
    }
  }

  public var group: Group {
    switch self {
    case .fakePartner: .demo
    case .overnightStay: .cat
    }
  }

  public var title: String {
    switch self {
    case .fakePartner: "Fake partner"
    case .overnightStay: "Overnight stay"
    }
  }

  public var detail: String {
    switch self {
    case .fakePartner:
      "A scripted partner on this phone sends notes, treats and hearts. Nothing is sent to anyone."
    case .overnightStay:
      "The cat stays with whoever got the last note. After you send one, a warm dent and paw prints wait until your partner sends one back."
    }
  }

  public var defaultOn: Bool {
    switch self {
    case .fakePartner: false
    case .overnightStay: true
    }
  }
}
