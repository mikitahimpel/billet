import Foundation

/// Places in Nooki's room the cat can be sent to. `home` is its bed, `front` the open floor before
/// the camera.
public enum NookiSpot: String, CaseIterable, Codable, Hashable, Sendable {
  case home, tree, sill, ball, basket, bowl, front
  /// Pieces the player stood in the room, each the first of its kind.
  case sofa, windowSeat, post, catBed, crate

  /// Where the brain's piece of furniture is in Nooki's room, if anywhere.
  public init?(_ kind: RoomAffordance.Kind) {
    switch kind {
    case .bed: self = .home
    case .window, .sunbeam: self = .sill
    case .rug, .toy: self = .ball
    case .shelf, .desk, .smallItem: self = .tree
    case .box: self = .basket
    case .soft: self = .home
    case .sofa: self = .sofa
    case .windowSeat: self = .windowSeat
    case .scratchingPost: self = .post
    case .catBed: self = .catBed
    case .crate: self = .crate
    case .bowl: self = .bowl
    case .door: self = .front
    }
  }

  public static func affordances(_ spots: Set<NookiSpot>) -> RoomAffordances {
    RoomAffordances(
      spots.compactMap { spot -> RoomAffordance? in
        switch spot {
        case .home: RoomAffordance(id: "bed", kind: .bed)
        case .tree: RoomAffordance(id: "tree", kind: .shelf)
        case .sill: RoomAffordance(id: "sill", kind: .window)
        case .ball: RoomAffordance(id: "ball", kind: .toy)
        case .basket: RoomAffordance(id: "basket", kind: .box)
        case .bowl: RoomAffordance(id: "bowl", kind: .bowl)
        case .front: nil
        case .sofa: RoomAffordance(id: "sofa", kind: .sofa)
        case .windowSeat: RoomAffordance(id: "windowSeat", kind: .windowSeat)
        case .post: RoomAffordance(id: "post", kind: .scratchingPost)
        case .catBed: RoomAffordance(id: "catBed", kind: .catBed)
        case .crate: RoomAffordance(id: "crate", kind: .crate)
        }
      })
  }
}

/// The three bodies the cat rests in. Each is its own splat, cut to in one frame while it is still.
public enum NookiRestPose: String, CaseIterable, Codable, Hashable, Sendable {
  case sit, loaf, sleep

  /// The least time the cat stays in a rest pose before it changes again, in seconds.
  public var dwell: Double {
    switch self {
    case .sit: 4
    case .loaf: 20
    case .sleep: 40
    }
  }
}

/// A short thing the cat does where it is, one of Nooki's habits.
public enum NookiAct: String, CaseIterable, Codable, Hashable, Sendable {
  case yawn, slowBlink, listen, twitch, flick, curl, pats
  /// Gestures of the head and ears that work in any body.
  case shake, tilt, chatter, track, lookUp
  /// Gets up and crouches low, rump wiggling, before a pounce or a dash.
  case crouch
  /// A quick hop forward on the paws, as onto a mote.
  case pounce
  /// Spins on the spot after her own tail.
  case spin
  /// Washes her chest in short licks, head down; it stands in for eating too.
  case groom
}

extension NookiAct {
  /// Whether the act is done from sitting up: pats and a head bent down, a crouch, a hop, a spin.
  public var needsSitting: Bool {
    switch self {
    case .pats, .groom, .crouch, .pounce, .spin: true
    case .yawn, .slowBlink, .listen, .twitch, .flick, .curl, .shake, .tilt, .chatter, .track,
      .lookUp:
      false
    }
  }
}

/// Where the cat looks between its own glances.
public enum NookiLook: Hashable, Sendable {
  case around, camera, window, away
  case spot(NookiSpot)
}

/// What the scene's cat is doing, as the script needs to know it.
public struct NookiCatBody: Hashable, Sendable {
  public var moving: Bool
  /// Where it is or is headed.
  public var at: NookiSpot
  public var rest: NookiRestPose

  public init(moving: Bool, at: NookiSpot, rest: NookiRestPose) {
    self.moving = moving
    self.at = at
    self.rest = rest
  }
}

/// One thing for the scene to do now.
public enum NookiCatIntent: Hashable, Sendable {
  /// Get up and go to `spot`; `stretch` when it gets up from a loaf or a nap.
  case go(NookiSpot, stretch: Bool)
  case rest(NookiRestPose)
  case act(NookiAct)
  case look(NookiLook)
  /// How sleepy it looks, from 0 awake to 1 asleep.
  case drowse(Double)
}

/// Turns the brain's frames into what Nooki's cat can do: sit, loaf and sleep bodies, walks and
/// jumps between spots, small habits. It adds the body's dwell to the brain's: no resend soon after
/// arriving, no pose cut before its dwell, and body changes only while the cat stands still.
public struct NookiCatScript: Sendable {
  /// Seconds the cat stays at a spot after arriving before it is sent elsewhere.
  public static let spotDwell = 8.0

  public let spots: Set<NookiSpot>
  /// Where she may rest: her bed and the window seat. The yarn basket and the toys are for play.
  public static let beds: Set<NookiSpot> = [.home, .sill, .sofa, .windowSeat, .catBed, .crate]
  private var step: (step: CatActivityStep, start: Double)?
  private var look: NookiLook?
  private var drowse: Double?
  private var lastBody: NookiCatBody?
  private var restSince = -Double.infinity
  private var arrived = -Double.infinity

  public init(spots: Set<NookiSpot>) {
    self.spots = spots
  }

  /// The rest pose `mind` rests in, from `now`: a pet leaves her in the body she is in.
  public static func rest(_ mind: CatMind, now: NookiRestPose) -> NookiRestPose {
    switch mind {
    case .loaf: .loaf
    case .napping, .deepSleep: .sleep
    case .beingPetted: now
    case .idle, .exploring, .playing, .grooming, .eating, .seekingAttention, .greetingPartner,
      .sulking:
      .sit
    }
  }

  public static func drowse(_ mind: CatMind) -> Double {
    switch mind {
    case .napping, .deepSleep: 1
    case .loaf: 0.35
    case .idle, .exploring, .playing, .grooming, .eating, .seekingAttention, .beingPetted,
      .greetingPartner, .sulking:
      0
    }
  }

  /// The act a step plays as it starts, if any.
  public static func act(_ step: CatActivityStep) -> NookiAct? {
    switch step {
    case .yawn: .yawn
    case .slowBlink, .rub, .lickLips: .slowBlink
    case .startle, .watchPartnerWindow, .heardNoise, .perkUp: .listen
    case .curiousTilt, .skid: .tilt
    case .trackMover: .track
    case .chatter: .chatter
    case .spotMote: .lookUp
    case .windUp: .crouch
    case .shakeOff: .shake
    case .chaseTail: .spin
    case .glanceBack: .slowBlink
    case .stalk, .sniffObject: .twitch
    case .dropToy, .sulk: .flick
    case .bellyUp: .curl
    case .pounce: .pounce
    case .knead, .batObject, .pawBowl, .scratch, .knockOff, .pushItem: .pats
    case .groomPaw, .groomFlank, .groomTail, .eat: .groom
    case .sit, .loaf, .lookAround, .wander, .inspectFurniture, .findNapSpot, .curl, .wake,
      .walkToBowl, .waitByBowl, .beg, .yowl, .flop, .chase, .zoomies, .watchWindow, .seekYou,
      .bringToy, .waitByDoor, .sitInCardigan, .sitOnDesk, .carryNote, .bask, .dashToDoor:
      nil
    }
  }

  /// Where the cat should be for `target` as `mind`, given that it is at `here`: resting, only in a bed.
  public func spot(for target: CatTarget, mind: CatMind, here: NookiSpot) -> NookiSpot {
    let spot = spot(for: target, here: here)
    guard mind.region == .resting, !Self.beds.contains(spot) else { return spot }
    return spots.contains(.sill) && spot == .sill ? .sill : .home
  }

  /// Where the cat should be for `target`, given that it is at `here`.
  public func spot(for target: CatTarget, here: NookiSpot) -> NookiSpot {
    let wanted: NookiSpot? =
      switch target {
      case .stay, .roam: here
      case .home: .home
      case .camera: .front
      case .affordance(let kind): NookiSpot(kind)
      }
    guard let wanted, wanted == .home || spots.contains(wanted) else { return here }
    return wanted
  }

  public func look(for gaze: CatGaze) -> NookiLook {
    switch gaze {
    case .ahead, .around: .around
    case .camera: .camera
    case .window: spots.contains(.sill) ? .window : .around
    case .away: .away
    case .affordance(let kind):
      NookiSpot(kind).flatMap { spots.contains($0) ? .spot($0) : nil } ?? .around
    }
  }

  /// What to do now for `frame`, read as `mind`, with the cat as `body` at `now`.
  public mutating func next(
    _ frame: CatBrainFrame, mind: CatMind, body: NookiCatBody, now: Double
  ) -> [NookiCatIntent] {
    if let last = lastBody {
      if last.rest != body.rest { restSince = now }
      if last.moving && !body.moving { arrived = now }
    }
    lastBody = body
    var intents: [NookiCatIntent] = []

    let look = look(for: frame.gaze)
    if look != self.look {
      self.look = look
      intents.append(.look(look))
    }
    let drowse = Self.drowse(mind)
    if drowse != self.drowse {
      self.drowse = drowse
      intents.append(.drowse(drowse))
    }

    guard !body.moving else { return intents }
    // A step that starts while she walks plays its act once she is still.
    let newStep = step.map { $0.step != frame.stack.step || $0.start != frame.stepStart } ?? true
    step = (frame.stack.step, frame.stepStart)

    let wanted = spot(for: frame.target, mind: mind, here: body.at)
    if wanted != body.at {
      guard now - arrived >= Self.spotDwell, now - restSince >= body.rest.dwell else {
        return intents
      }
      intents.append(.go(wanted, stretch: body.rest != .sit))
      return intents
    }

    var resting = body.rest
    let rest = Self.rest(mind, now: body.rest)
    if rest != body.rest, now - restSince >= body.rest.dwell {
      intents.append(.rest(rest))
      resting = rest
    }
    // Pats and a head bent down need her sitting; her face and tail do the rest in any body.
    if newStep, frame.stack.interaction == nil, let act = Self.act(frame.stack.step),
      resting == .sit || !act.needsSitting
    {
      intents.append(.act(act))
    }
    return intents
  }
}
