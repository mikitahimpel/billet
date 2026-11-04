import Foundation

/// The cat's state as the owner's chart names it: three regions over the brain's vitality,
/// activity and interaction. It is a reading of ``CatBrainStack``, so it never moves on its own and
/// keeps the brain's dwell times and history.
public enum CatMind: String, CaseIterable, Codable, Hashable, Sendable {
  case idle, exploring, playing, grooming, eating, seekingAttention
  case loaf, napping, deepSleep
  case beingPetted, greetingPartner, sulking

  public enum Region: String, CaseIterable, Codable, Hashable, Sendable {
    case awake, resting, social
  }

  public var region: Region {
    switch self {
    case .idle, .exploring, .playing, .grooming, .eating, .seekingAttention: .awake
    case .loaf, .napping, .deepSleep: .resting
    case .beingPetted, .greetingPartner, .sulking: .social
    }
  }

  /// `Resting › Napping`, for the debug card.
  public var path: String { "\(region.rawValue.capitalized) › \(rawValue)" }

  /// Local hours a sleeping cat counts as deep asleep in: the night, `from` to `until`.
  public static let night: (from: Double, until: Double) = (22, 6)

  /// The state for `stack` at local `hour`.
  public init(_ stack: CatBrainStack, hour: Double) {
    if let interaction = stack.interaction {
      self = Self.social(interaction, step: stack.step)
      return
    }
    if stack.step == .sulk {
      self = .sulking
      return
    }
    if stack.vitality == .asleep {
      self = hour >= Self.night.from || hour < Self.night.until ? .deepSleep : .napping
      return
    }
    let mind = Self.activity(stack.step)
    // A drowsy cat that is only sitting about is loafing.
    self = stack.vitality == .drowsy && mind == .idle ? .loaf : mind
  }

  private static func social(_ interaction: CatInteraction, step: CatActivityStep) -> CatMind {
    switch interaction {
    case .petted, .held: .beingPetted
    case .greeting, .called: .greetingPartner
    case .toy, .batting, .followFinger: .playing
    case .fed: .eating
    }
  }

  private static func activity(_ step: CatActivityStep) -> CatMind {
    switch step {
    case .sit, .lookAround, .bellyUp, .watchWindow, .watchPartnerWindow, .startle, .curiousTilt:
      .idle
    case .loaf, .findNapSpot, .knead, .wake, .yawn: .loaf
    case .curl: .napping
    case .wander, .sniffObject, .inspectFurniture: .exploring
    case .groomPaw, .groomFlank, .groomTail, .lickLips: .grooming
    case .walkToBowl, .eat, .waitByBowl, .pawBowl, .beg, .yowl: .eating
    case .stalk, .pounce, .chase, .batObject, .zoomies, .scratch, .knockOff, .flop, .pushItem:
      .playing
    case .sitInCardigan, .sitOnDesk: .loaf
    case .seekYou, .rub, .slowBlink, .bringToy, .waitByDoor, .dropToy, .carryNote:
      .seekingAttention
    case .sulk: .sulking
    }
  }
}
