import Foundation

/// The shape of the cat's brain: its regions, the scripts inside each activity group, how long
/// each step lasts, what it plays, and which moves are legal. The brain runs on it, the tests
/// check every move against it, and `docs/cat-brain.md` is drawn from it.
///
/// Four regions run side by side. Vitality is slow: awake, drowsy, asleep, one neighbour at a
/// time. Activity is the big one: groups of steps, each group played as a short script, with
/// utility choosing the next group when a script ends. Interaction overrides activity while a
/// person is busy with the cat, and activity comes back from its history afterwards. Reflexes
/// (blinks, ears, tail, breath, the head following things) never stop.
public enum CatStatechart {
  /// The scripts a group can play, each a list of steps run in order. Entering a group picks one.
  public static func scripts(_ group: CatActivityGroup) -> [[CatActivityStep]] {
    switch group {
    case .idle: [[.sit], [.loaf], [.sit, .lookAround], [.lookAround, .sit]]
    case .explore: [[.wander, .sniffObject], [.wander], [.inspectFurniture, .sniffObject]]
    case .rest: [[.findNapSpot, .knead, .curl, .wake], [.findNapSpot, .curl, .wake]]
    case .groom:
      [
        [.groomPaw], [.groomPaw, .groomFlank], [.groomFlank, .groomTail],
        [.groomPaw, .groomFlank, .groomTail],
      ]
    case .eat: [[.walkToBowl, .eat, .lickLips]]
    case .play:
      [
        [.stalk, .pounce], [.stalk, .pounce, .chase], [.batObject], [.zoomies], [.chase, .pounce],
      ]
    case .watch: [[.watchWindow], [.watchPartnerWindow]]
    case .social:
      [[.seekYou, .rub], [.slowBlink], [.bringToy], [.waitByDoor], [.seekYou, .slowBlink]]
    case .mischief: [[.pushItem], [.sitInCardigan], [.sitOnDesk]]
    case .react: [[.startle], [.curiousTilt], [.carryNote]]
    }
  }

  /// Scripts only an event starts. A curled cat wakes first, then turns to what woke it.
  public static let eventScripts: [[CatActivityStep]] = [
    [.wake, .curiousTilt], [.wake, .carryNote], [.wake, .stalk, .pounce],
  ]

  /// The steps a group can be entered at.
  public static func entries(_ group: CatActivityGroup) -> Set<CatActivityStep> {
    Set(scripts(group).compactMap(\.first))
  }

  /// The steps a script can end on, after which utility chooses again.
  public static func exits(_ group: CatActivityGroup) -> Set<CatActivityStep> {
    Set(scripts(group).compactMap(\.last))
  }

  /// The steps that can follow `step` in a script. Only a reaction's script crosses groups: a
  /// curled cat wakes before it tilts its head.
  public static func successors(_ step: CatActivityStep) -> Set<CatActivityStep> {
    var next = Set<CatActivityStep>()
    for script in CatActivityGroup.allCases.flatMap(scripts) + eventScripts {
      for (a, b) in zip(script, script.dropFirst()) where a == step { next.insert(b) }
    }
    return next
  }

  /// Whether the activity may go from `from` to `to` for `cause`. History may come back to any
  /// step it left; an event may break into any step for a reaction or a meal.
  public static func isLegal(
    from: CatActivityStep, to: CatActivityStep, cause: CatTransitionCause
  ) -> Bool {
    switch cause {
    case .dayStart, .history, .interaction: return true
    case .scriptNext: return successors(from).contains(to)
    case .chosen:
      return exits(from.group).contains(from) && entries(to.group).contains(to)
        && to.group != .react
    case .preempted:
      return from.group != to.group && entries(to.group).contains(to) && to.group != .react
    case .vitality:
      // Sleepiness takes the cat to its nap spot; waking stands it up from the curl.
      return (to.group == .rest && (entries(.rest).contains(to) || to == .curl))
        || (from == .curl && to == .wake)
    case .event:
      return to.group == .react || entries(to.group).contains(to)
        || eventScripts.contains { $0.first == to } && from == .curl
    }
  }

  /// Vitality moves one neighbour at a time: the cat is drowsy on the way to sleep and back.
  public static func isLegal(from: CatVitality, to: CatVitality) -> Bool {
    switch (from, to) {
    case (.awake, .drowsy), (.drowsy, .awake), (.drowsy, .asleep), (.asleep, .drowsy): true
    case (.awake, .awake), (.drowsy, .drowsy), (.asleep, .asleep): true
    case (.awake, .asleep), (.asleep, .awake): false
    }
  }

  /// The least time vitality stays put before it moves again, in seconds.
  public static let vitalityDwell = 12.0

  /// How long a step lasts, in seconds; the brain draws a length in this range on entry.
  public static func duration(_ step: CatActivityStep) -> ClosedRange<Double> {
    switch step {
    case .sit: 8...20
    case .loaf: 20...45
    case .lookAround: 6...12
    case .wander: 3...6
    case .sniffObject: 2...4
    case .inspectFurniture: 4...7
    case .findNapSpot: 2...4
    case .knead: 3...6
    case .curl: 40...120
    case .wake: 2...3
    case .groomPaw, .groomFlank: 4...8
    case .groomTail: 4...7
    case .walkToBowl: 2...4
    case .eat: 4...7
    case .lickLips: 1.5...2.5
    case .stalk: 3...6
    case .pounce: 1...1.5
    case .chase: 3...5
    case .batObject: 2...3
    case .zoomies: 4...7
    case .watchWindow: 15...45
    case .watchPartnerWindow: 15...35
    case .seekYou: 2...4
    case .rub: 2...3
    case .slowBlink: 2...3
    case .bringToy: 3...5
    case .waitByDoor: 15...30
    case .pushItem: 3...5
    case .sitInCardigan: 15...40
    case .sitOnDesk: 10...25
    case .startle: 1...1.5
    case .curiousTilt: 1.5...2.5
    case .carryNote: 5...7
    }
  }

  /// The least time a group plays before something better may cut it short, in seconds.
  public static func minimumDwell(_ group: CatActivityGroup) -> Double {
    switch group {
    case .rest: 30
    case .watch: 8
    case .idle, .groom, .social, .mischief, .explore: 4
    case .eat, .play, .react: 3
    }
  }

  // MARK: - Animation

  /// The clip a step plays once the cat is where the step wants it. A step with no clip of its
  /// own composes one: looking round is sitting with the head turning.
  public static func clip(_ step: CatActivityStep) -> CatAction {
    switch step {
    case .loaf: .loaf
    case .sit, .lookAround, .findNapSpot, .watchWindow, .waitByDoor, .sitInCardigan,
      .sitOnDesk:
      .sit
    case .wander, .walkToBowl, .bringToy, .inspectFurniture, .sniffObject: .sniff
    case .chase, .seekYou: .perk
    case .zoomies: .happy
    case .knead: .knead
    case .curl: .sleep
    case .wake: .stretch
    case .groomPaw, .groomFlank, .groomTail: .groom
    case .eat: .eat
    case .lickLips: .happy
    case .stalk: .crouchWiggle
    case .pounce: .pounce
    case .batObject, .pushItem: .bat
    case .watchPartnerWindow: .slowBlink
    case .rub: .headbutt
    case .slowBlink: .slowBlink
    case .startle, .curiousTilt: .perk
    case .carryNote: .reachUp
    }
  }

  /// How fast a travelling step moves, as a share of a run: 0 walks, 1 runs flat out.
  public static func pace(_ step: CatActivityStep) -> Double {
    switch step {
    case .chase, .zoomies: 1
    case .seekYou: 0.5
    default: 0
    }
  }

  /// Where the body goes during `step` in `room`. `napSpot` is where the brain chose to rest and
  /// `inspecting` the piece it went to look at; `roll` places a roam.
  public static func target(
    _ step: CatActivityStep, room: RoomAffordances, napSpot: RoomAffordance.Kind?,
    inspecting: RoomAffordance.Kind?, roll: Double
  ) -> CatTarget {
    func spot(_ kind: RoomAffordance.Kind) -> CatTarget {
      room.reachable(kind) ? .affordance(kind) : .stay
    }
    let roam = CatTarget.roam(roll, (roll * 7.31).truncatingRemainder(dividingBy: 1))
    switch step {
    case .wander, .chase, .zoomies: return roam
    case .sniffObject: return room.reachable(.smallItem) ? .affordance(.smallItem) : roam
    case .inspectFurniture: return inspecting.map(CatTarget.affordance) ?? roam
    case .findNapSpot, .knead, .curl, .wake: return napSpot.map(CatTarget.affordance) ?? .home
    case .walkToBowl, .eat, .lickLips: return spot(.bowl)
    case .watchWindow, .watchPartnerWindow: return spot(.window)
    case .seekYou, .rub, .slowBlink: return .camera
    case .bringToy: return spot(.toy)
    case .waitByDoor: return room.reachable(.door) ? .affordance(.door) : spot(.window)
    case .pushItem: return spot(.smallItem)
    case .sitInCardigan: return spot(.soft)
    case .sitOnDesk: return spot(.desk)
    case .sit, .loaf, .lookAround, .groomPaw, .groomFlank, .groomTail, .stalk, .pounce,
      .batObject, .startle, .curiousTilt, .carryNote:
      return .stay
    }
  }

  /// Where the head points during `step`.
  public static func gaze(_ step: CatActivityStep, roll: Double) -> CatGaze {
    switch step {
    case .lookAround: .around((roll - 0.5) * 2.2)
    case .watchWindow, .watchPartnerWindow: .window
    case .waitByDoor: .window
    case .seekYou, .rub, .slowBlink, .bringToy, .curiousTilt, .sit: .camera
    case .sniffObject, .pushItem: .affordance(.smallItem)
    case .stalk, .pounce, .batObject: .affordance(.toy)
    case .loaf, .wander, .inspectFurniture, .findNapSpot, .knead, .curl, .wake, .groomPaw,
      .groomFlank, .groomTail, .walkToBowl, .eat, .lickLips, .chase, .zoomies, .sitInCardigan,
      .sitOnDesk, .startle, .carryNote:
      .ahead
    }
  }

  // MARK: - Export

  /// The chart as a mermaid state diagram, for `docs/cat-brain.md`.
  public static func mermaid() -> String {
    var lines = ["stateDiagram-v2"]
    func name(_ step: CatActivityStep) -> String {
      step.rawValue.prefix(1).uppercased() + step.rawValue.dropFirst()
    }
    lines.append("  state Vitality {")
    lines.append("    [*] --> Awake")
    lines.append("    Awake --> Drowsy : sleep pressure")
    lines.append("    Drowsy --> Awake : rested")
    lines.append("    Drowsy --> Asleep : night or nap")
    lines.append("    Asleep --> Drowsy : wakes")
    lines.append("  }")
    lines.append("  --")
    lines.append("  state Activity {")
    lines.append("    state Choose <<choice>>")
    lines.append("    [*] --> Idle")
    for group in CatActivityGroup.allCases {
      lines.append("    state \(group.title) {")
      for entry in CatActivityStep.allCases where entries(group).contains(entry) {
        lines.append("      [*] --> \(name(entry))")
      }
      var edges = Set<String>()
      for script in scripts(group) {
        for (a, b) in zip(script, script.dropFirst()) {
          edges.insert("      \(name(a)) --> \(name(b))")
        }
      }
      lines += edges.sorted()
      for exit in CatActivityStep.allCases where exits(group).contains(exit) {
        lines.append("      \(name(exit)) --> [*]")
      }
      lines.append("    }")
    }
    for group in CatActivityGroup.allCases {
      lines.append("    \(group.title) --> Choose : script ends")
    }
    for group in CatActivityGroup.chosen {
      lines.append("    Choose --> \(group.title) : utility")
    }
    lines.append("    note right of React : any step jumps here on a note or a startle")
    lines.append("  }")
    lines.append("  --")
    lines.append("  state Interaction {")
    lines.append("    [*] --> None")
    for interaction in [
      "Petted", "Held", "Toy", "Called", "Fed", "FollowFinger", "Greeting", "Batting",
    ] {
      lines.append("    None --> \(interaction)")
      lines.append("    \(interaction) --> None : ends, activity resumes from history")
    }
    lines.append("  }")
    lines.append("  --")
    lines.append("  state Reflex {")
    lines.append("    Blink")
    lines.append("    EarTwitch")
    lines.append("    TailFlick")
    lines.append("    Breathing")
    lines.append("    HeadTracking")
    lines.append("  }")
    // Parallel regions are only drawn inside a composite state, so the whole brain is one.
    let body = lines.dropFirst().map { "  " + $0 }
    return (["stateDiagram-v2", "  state CatBrain {"] + body + ["  }"]).joined(separator: "\n")
  }
}
