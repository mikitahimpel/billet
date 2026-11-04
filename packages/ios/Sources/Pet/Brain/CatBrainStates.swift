import Foundation

/// How awake the cat is: the slow region of its brain, following the day rhythm of its life.
public enum CatVitality: String, CaseIterable, Codable, Hashable, Sendable {
  case awake
  case drowsy
  case asleep
}

/// The compound states of the activity region. Each holds a few steps, played as a short script.
public enum CatActivityGroup: String, CaseIterable, Codable, Hashable, Sendable {
  case idle
  case explore
  case rest
  case groom
  case eat
  case play
  case watch
  case social
  case mischief
  /// Entered only by something happening, never chosen by utility.
  case react

  public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

  /// The groups utility chooses among.
  public static let chosen: [CatActivityGroup] = allCases.filter { $0 != .react }
}

/// The leaf states of the activity region. Each belongs to one group.
public enum CatActivityStep: String, CaseIterable, Codable, Hashable, Sendable {
  case sit, loaf, lookAround
  /// Happy and full: it rolls onto its back, belly up, and purrs.
  case bellyUp
  case wander, sniffObject, inspectFurniture
  case findNapSpot, knead, curl, wake
  /// Sleepy: a big yawn before it goes to find its spot.
  case yawn
  case groomPaw, groomFlank, groomTail
  case walkToBowl, eat, lickLips
  /// Mealtime as the pair keeps it: the cat sits by the bowl and looks at you.
  case waitByBowl
  /// Hungry: it paws at the empty bowl.
  case pawBowl
  /// Hungry: it sits up in front of you and begs with a paw, following your finger.
  case beg
  /// A tantrum: it arches and yowls at you.
  case yowl
  /// A tantrum: it bats the mug off the seat.
  case knockOff
  /// A tantrum: it flops over onto its side in despair, tail lashing.
  case flop
  case stalk, pounce, chase, batObject, zoomies
  /// Bored: it scratches the cushion.
  case scratch
  case watchWindow, watchPartnerWindow
  case seekYou, rub, slowBlink, bringToy, waitByDoor
  /// It carries the toy to you and drops it at your feet.
  case dropToy
  /// Lonely: it sits with its back to you, and the first touch is ignored.
  case sulk
  case pushItem, sitInCardigan, sitOnDesk
  case startle, curiousTilt
  /// A note came: the cat carries it in its mouth to the wall or the glass and tapes it up.
  case carryNote

  public var group: CatActivityGroup {
    switch self {
    case .sit, .loaf, .lookAround, .bellyUp: .idle
    case .wander, .sniffObject, .inspectFurniture: .explore
    case .findNapSpot, .knead, .curl, .wake, .yawn: .rest
    case .groomPaw, .groomFlank, .groomTail: .groom
    case .walkToBowl, .eat, .lickLips, .waitByBowl, .pawBowl, .beg, .yowl, .knockOff, .flop: .eat
    case .stalk, .pounce, .chase, .batObject, .zoomies, .scratch: .play
    case .watchWindow, .watchPartnerWindow: .watch
    case .seekYou, .rub, .slowBlink, .bringToy, .waitByDoor, .dropToy, .sulk: .social
    case .pushItem, .sitInCardigan, .sitOnDesk: .mischief
    case .startle, .curiousTilt, .carryNote: .react
    }
  }

  /// Whether the cat travels during this step, so its body goes to the step's target.
  public var travels: Bool {
    switch self {
    case .wander, .findNapSpot, .walkToBowl, .chase, .zoomies, .seekYou, .bringToy,
      .inspectFurniture, .dropToy, .beg, .knockOff, .scratch:
      true
    case .sit, .loaf, .lookAround, .sniffObject, .knead, .curl, .wake, .groomPaw, .groomFlank,
      .groomTail, .eat, .lickLips, .stalk, .pounce, .batObject, .watchWindow,
      .watchPartnerWindow, .rub, .slowBlink, .waitByDoor, .waitByBowl, .pushItem, .sitInCardigan,
      .sitOnDesk, .startle, .curiousTilt, .carryNote, .bellyUp, .yawn, .pawBowl, .yowl, .flop,
      .sulk:
      false
    }
  }
}

/// The interaction region: something a person is doing with the cat right now. While one is
/// active it overrides the activity, which resumes from its history afterwards.
public enum CatInteraction: Hashable, Sendable {
  case petted(PetZone)
  case held
  case toy(CatToy)
  case called
  case fed
  /// A finger hovering near the cat: only its head follows.
  case followFinger
  /// Back after hours away: it runs up to whoever holds the phone and headbutts the glass.
  case greeting
  /// A finger resting near the edge of the screen, batted at by a cat in the mood to play.
  case batting

  public var title: String {
    switch self {
    case .petted(let zone): "Petted(\(zone.rawValue))"
    case .held: "Held"
    case .toy(let toy): "Toy(\(toy.rawValue))"
    case .called: "Called"
    case .fed: "Fed"
    case .followFinger: "FollowFinger"
    case .greeting: "Greeting"
    case .batting: "Batting"
    }
  }

  /// Higher wins when two want the cat at once.
  public var priority: Int {
    switch self {
    case .held: 5
    case .fed: 4
    case .petted: 3
    case .toy, .batting: 2
    case .called, .greeting: 1
    case .followFinger: 0
    }
  }
}

/// Where the body goes for a step, as something in the room. A scene finds the spot itself.
public enum CatTarget: Hashable, Sendable {
  /// Wherever it is now.
  case stay
  /// Its own resting place.
  case home
  case affordance(RoomAffordance.Kind)
  /// Towards whoever holds the phone.
  case camera
  /// A spot on its surface picked by the brain, as a fraction across it from 0 to 1.
  case roam(Double, Double)
}

/// Where the head points for a step.
public enum CatGaze: Hashable, Sendable {
  case ahead
  case camera
  case window
  case affordance(RoomAffordance.Kind)
  /// Turned away from whoever holds the phone, as a sulking cat sits.
  case away
  /// Looking round: a heading offset from ahead, in radians, that changes every few seconds.
  case around(Double)
}

/// The active states of every region, innermost last, for tests and the debug overlay.
public struct CatBrainStack: Hashable, Sendable {
  public var vitality: CatVitality
  public var step: CatActivityStep
  public var interaction: CatInteraction?

  public init(vitality: CatVitality, step: CatActivityStep, interaction: CatInteraction? = nil) {
    self.vitality = vitality
    self.step = step
    self.interaction = interaction
  }

  public var group: CatActivityGroup { step.group }

  /// `Vitality.Awake › Activity.Rest.Curl › Interaction.Petted(head)`.
  public var path: String {
    var parts = [
      "Vitality.\(vitality.rawValue.capitalized)",
      "Activity.\(group.title).\(step.rawValue.prefix(1).uppercased() + step.rawValue.dropFirst())",
    ]
    if let interaction { parts.append("Interaction.\(interaction.title)") }
    return parts.joined(separator: " › ")
  }
}

/// Why a transition happened.
public enum CatTransitionCause: String, Codable, Hashable, Sendable {
  /// The day began: the brain starts again from its canonical state.
  case dayStart
  /// The step's time was up and the script went on.
  case scriptNext
  /// The group's script ended and utility chose the next group.
  case chosen
  /// Another group became much more attractive after the minimum dwell.
  case preempted
  /// The cat got sleepy or woke: the vitality region moved.
  case vitality
  /// A life event, such as a note or a meal, interrupted the activity.
  case event
  /// An interaction began or ended.
  case interaction
  /// After an interaction the activity came back to where it was.
  case history
}

/// One move of the brain, kept for the debug overlay and tests.
public struct CatBrainTransition: Hashable, Sendable {
  public var at: Double
  public var from: CatBrainStack
  public var to: CatBrainStack
  public var cause: CatTransitionCause

  public init(at: Double, from: CatBrainStack, to: CatBrainStack, cause: CatTransitionCause) {
    self.at = at
    self.from = from
    self.to = to
    self.cause = cause
  }
}
