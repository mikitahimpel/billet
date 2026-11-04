import Foundation

/// Places in Nooki's room the cat can be sent to. `home` is its bed, `front` the open floor before
/// the camera.
public enum NookiSpot: String, CaseIterable, Codable, Hashable, Sendable {
  case home, tree, sill, ball, basket, bowl, front

  /// Where the brain's piece of furniture is in Nooki's room, if anywhere.
  public init?(_ kind: RoomAffordance.Kind) {
    switch kind {
    case .bed: self = .home
    case .window, .sunbeam: self = .sill
    case .rug, .toy: self = .ball
    case .shelf, .box, .desk, .smallItem: self = .tree
    case .soft: self = .basket
    case .bowl: self = .bowl
    case .door: self = .front
    }
  }

  /// What a room that has these spots offers the brain.
  public static func affordances(_ spots: Set<NookiSpot>) -> RoomAffordances {
    RoomAffordances(
      spots.compactMap { spot -> RoomAffordance? in
        switch spot {
        case .home: RoomAffordance(id: "bed", kind: .bed)
        case .tree: RoomAffordance(id: "tree", kind: .shelf)
        case .sill: RoomAffordance(id: "sill", kind: .window)
        case .ball: RoomAffordance(id: "ball", kind: .toy)
        case .basket: RoomAffordance(id: "basket", kind: .soft)
        case .bowl: RoomAffordance(id: "bowl", kind: .bowl)
        case .front: nil
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
  /// Washes her chest in short licks, head down; it stands in for eating too.
  case groom
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

/// Turns the brain's frames into what Nooki's cat can do: the rig's sit, loaf and sleep bodies,
/// its walks and jumps between the room's spots, and its small habits. The brain already keeps
/// its own dwell times; the script adds the body's, so a cat is never sent off again within a
/// few seconds of arriving or cut from one rest pose to another sooner than the pose's dwell,
/// and only changes its body while it stands still.
public struct NookiCatScript: Sendable {
  /// Seconds the cat stays at a spot after arriving before it is sent elsewhere.
  public static let spotDwell = 8.0

  public let spots: Set<NookiSpot>
  private var step: (step: CatActivityStep, start: Double)?
  private var look: NookiLook?
  private var drowse: Double?
  private var lastBody: NookiCatBody?
  private var restSince = -Double.infinity
  private var arrived = -Double.infinity

  public init(spots: Set<NookiSpot>) {
    self.spots = spots
  }

  /// The rest pose `mind` rests in.
  public static func rest(_ mind: CatMind) -> NookiRestPose {
    switch mind {
    case .loaf: .loaf
    case .napping, .deepSleep: .sleep
    case .idle, .exploring, .playing, .grooming, .eating, .seekingAttention, .beingPetted,
      .greetingPartner, .sulking:
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
    case .startle, .curiousTilt, .watchPartnerWindow: .listen
    case .stalk, .sniffObject: .twitch
    case .dropToy, .sulk: .flick
    case .bellyUp: .curl
    case .knead, .batObject, .pounce, .pawBowl, .scratch, .knockOff, .pushItem: .pats
    case .groomPaw, .groomFlank, .groomTail, .eat: .groom
    case .sit, .loaf, .lookAround, .wander, .inspectFurniture, .findNapSpot, .curl, .wake,
      .walkToBowl, .waitByBowl, .beg, .yowl, .flop, .chase, .zoomies, .watchWindow, .seekYou,
      .bringToy, .waitByDoor, .sitInCardigan, .sitOnDesk, .carryNote:
      nil
    }
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
    case .affordance(let kind): NookiSpot(kind).flatMap { spots.contains($0) ? .spot($0) : nil } ?? .around
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

    let newStep = step.map { $0.step != frame.stack.step || $0.start != frame.stepStart } ?? true
    step = (frame.stack.step, frame.stepStart)
    guard !body.moving else { return intents }

    let wanted = spot(for: frame.target, here: body.at)
    if wanted != body.at {
      guard now - arrived >= Self.spotDwell, now - restSince >= body.rest.dwell else {
        return intents
      }
      intents.append(.go(wanted, stretch: body.rest != .sit))
      return intents
    }

    var resting = body.rest
    let rest = Self.rest(mind)
    if rest != body.rest, now - restSince >= body.rest.dwell {
      intents.append(.rest(rest))
      resting = rest
    }
    // Pats and a head bent down need her sitting; her face and tail do the rest in any body.
    if newStep, frame.stack.interaction == nil, let act = Self.act(frame.stack.step),
      resting == .sit || (act != .pats && act != .groom)
    {
      intents.append(.act(act))
    }
    return intents
  }
}
