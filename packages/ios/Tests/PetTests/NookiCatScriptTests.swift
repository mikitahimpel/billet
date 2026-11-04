import Foundation
import Testing

@testable import Pet

@Suite("CatMind")
struct CatMindTests {
  @Test("each region reads from the brain's stack")
  func regions() {
    func mind(
      _ vitality: CatVitality, _ step: CatActivityStep, _ touch: CatInteraction? = nil,
      hour: Double = 12
    ) -> CatMind {
      CatMind(CatBrainStack(vitality: vitality, step: step, interaction: touch), hour: hour)
    }
    #expect(mind(.awake, .sit) == .idle)
    #expect(mind(.awake, .wander) == .exploring)
    #expect(mind(.awake, .pounce) == .playing)
    #expect(mind(.awake, .groomPaw) == .grooming)
    #expect(mind(.awake, .eat) == .eating)
    #expect(mind(.awake, .seekYou) == .seekingAttention)
    #expect(mind(.awake, .loaf) == .loaf)
    #expect(mind(.drowsy, .sit) == .loaf)
    #expect(mind(.drowsy, .curl) == .napping)
    #expect(mind(.asleep, .curl, hour: 14) == .napping)
    #expect(mind(.asleep, .curl, hour: 23) == .deepSleep)
    #expect(mind(.asleep, .curl, hour: 3) == .deepSleep)
    #expect(mind(.awake, .sit, .petted(.head)) == .beingPetted)
    #expect(mind(.asleep, .curl, .petted(.head)) == .beingPetted)
    #expect(mind(.awake, .sit, .greeting) == .greetingPartner)
    #expect(mind(.awake, .sulk) == .sulking)
    #expect(mind(.awake, .sulk).region == .social)
    #expect(mind(.asleep, .curl).region == .resting)
  }

  @Test("every state the owner's chart names is reachable from some stack")
  func everyState() {
    var seen = Set<CatMind>()
    let touches: [CatInteraction?] = [nil, .petted(.head), .greeting, .fed, .batting]
    for vitality in CatVitality.allCases {
      for step in CatActivityStep.allCases {
        for touch in touches {
          for hour in [3.0, 14] {
            seen.insert(
              CatMind(CatBrainStack(vitality: vitality, step: step, interaction: touch), hour: hour)
            )
          }
        }
      }
    }
    #expect(seen == Set(CatMind.allCases))
  }
}

@Suite("NookiCatScript")
struct NookiCatScriptTests {
  typealias Day = CatBrainTests

  static let spots: Set<NookiSpot> = [.home, .tree, .sill, .ball, .basket]

  static func frame(
    _ step: CatActivityStep, start: Double = 0, target: CatTarget = .stay,
    gaze: CatGaze = .ahead, vitality: CatVitality = .awake, touch: CatInteraction? = nil
  ) -> CatBrainFrame {
    CatBrainFrame(
      stack: CatBrainStack(vitality: vitality, step: step, interaction: touch),
      action: CatStatechart.clip(step), target: target, gaze: gaze, pace: 0, stepStart: start,
      stepEnd: start + 10, eager: false, tempo: 1, amplitude: 1, personalSpace: 0.3, tricks: [],
      feeling: .content, voice: nil, voiceEvery: nil, purring: false)
  }

  static func mind(_ frame: CatBrainFrame) -> CatMind { CatMind(frame.stack, hour: 12) }

  static let still = NookiCatBody(moving: false, at: .home, rest: .sit)

  @Test("a target in the room sends the cat there; one the room lacks keeps it where it is")
  func targets() {
    var script = NookiCatScript(spots: Self.spots)
    let window = Self.frame(.watchWindow, target: .affordance(.window), gaze: .window)
    let intents = script.next(window, mind: Self.mind(window), body: Self.still, now: 100)
    #expect(intents.contains(.go(.sill, stretch: false)))
    #expect(intents.contains(.look(.window)))
    #expect(script.spot(for: .affordance(.bowl), here: .tree) == .tree)
    #expect(script.spot(for: .camera, here: .tree) == .tree)
    #expect(NookiCatScript(spots: [.bowl]).spot(for: .affordance(.bowl), here: .home) == .bowl)
  }

  @Test("each resting state rests in its own pose, once the cat is still")
  func restPoses() {
    #expect(NookiCatScript.rest(.loaf, now: .sit) == .loaf)
    #expect(NookiCatScript.rest(.napping, now: .sit) == .sleep)
    #expect(NookiCatScript.rest(.deepSleep, now: .loaf) == .sleep)
    #expect(NookiCatScript.rest(.idle, now: .sleep) == .sit)
    #expect(NookiCatScript.rest(.beingPetted, now: .sleep) == .sleep)

    var script = NookiCatScript(spots: Self.spots)
    let nap = Self.frame(.curl, vitality: .asleep)
    let moving = NookiCatBody(moving: true, at: .home, rest: .sit)
    #expect(!script.next(nap, mind: .napping, body: moving, now: 100).contains(.rest(.sleep)))
    #expect(script.next(nap, mind: .napping, body: Self.still, now: 110).contains(.rest(.sleep)))
  }

  @Test("she rests only in her bed or on the window seat; the basket is for play")
  func beds() {
    let script = NookiCatScript(spots: Self.spots)
    #expect(script.spot(for: .affordance(.box), mind: .playing, here: .home) == .basket)
    #expect(script.spot(for: .affordance(.box), mind: .napping, here: .basket) == .home)
    #expect(script.spot(for: .affordance(.soft), mind: .loaf, here: .tree) == .home)
    #expect(script.spot(for: .affordance(.window), mind: .deepSleep, here: .home) == .sill)
    #expect(script.spot(for: .stay, mind: .napping, here: .ball) == .home)
    #expect(
      NookiCatScript(spots: [.home]).spot(for: .affordance(.window), mind: .napping, here: .home)
        == .home)
  }

  @Test("a step that starts mid-walk plays its act on arrival")
  func actAfterWalk() {
    var script = NookiCatScript(spots: Self.spots)
    let groom = Self.frame(.groomPaw, start: 3)
    let walking = NookiCatBody(moving: true, at: .home, rest: .sit)
    #expect(!script.next(groom, mind: .grooming, body: walking, now: 3).contains(.act(.groom)))
    #expect(script.next(groom, mind: .grooming, body: Self.still, now: 5).contains(.act(.groom)))
  }

  @Test("a new rest pose waits out the last one's dwell")
  func restDwell() {
    var script = NookiCatScript(spots: Self.spots)
    let loaf = NookiCatBody(moving: false, at: .home, rest: .loaf)
    let sit = Self.frame(.sit)
    _ = script.next(sit, mind: .idle, body: Self.still, now: 0)
    // It became a loaf at 1 s; asked to sit again it holds the loaf for the loaf's dwell.
    #expect(script.next(sit, mind: .idle, body: loaf, now: 1).isEmpty)
    #expect(!script.next(sit, mind: .idle, body: loaf, now: 15).contains(.rest(.sit)))
    #expect(script.next(sit, mind: .idle, body: loaf, now: 21.5).contains(.rest(.sit)))
  }

  @Test("an arrival is not followed by another trip within the spot's dwell")
  func spotDwell() {
    var script = NookiCatScript(spots: Self.spots)
    let tree = Self.frame(.inspectFurniture, target: .affordance(.shelf))
    _ = script.next(
      tree, mind: .exploring, body: NookiCatBody(moving: true, at: .tree, rest: .sit), now: 0)
    let there = NookiCatBody(moving: false, at: .tree, rest: .sit)
    let ball = Self.frame(.chase, start: 3, target: .affordance(.toy))
    #expect(
      !script.next(ball, mind: .playing, body: there, now: 3).contains {
        if case .go = $0 { true } else { false }
      })
    #expect(
      script.next(ball, mind: .playing, body: there, now: 12).contains(.go(.ball, stretch: false)))
  }

  @Test("getting up from a loaf or a nap stretches first")
  func stretch() {
    var script = NookiCatScript(spots: Self.spots)
    let napping = NookiCatBody(moving: false, at: .home, rest: .sleep)
    let window = Self.frame(.watchWindow, target: .affordance(.window))
    _ = script.next(Self.frame(.curl, vitality: .asleep), mind: .napping, body: napping, now: 0)
    #expect(
      script.next(window, mind: .idle, body: napping, now: 60).contains(.go(.sill, stretch: true)))
  }

  @Test("a step's act plays once, when the step starts, and not under a touch")
  func acts() {
    var script = NookiCatScript(spots: Self.spots)
    let yawn = Self.frame(.yawn, start: 5)
    #expect(script.next(yawn, mind: .loaf, body: Self.still, now: 5).contains(.act(.yawn)))
    #expect(!script.next(yawn, mind: .loaf, body: Self.still, now: 5.1).contains(.act(.yawn)))
    let groom = Self.frame(.groomPaw, start: 9, touch: .petted(.head))
    #expect(
      !script.next(groom, mind: .beingPetted, body: Self.still, now: 9).contains(.act(.groom)))
  }

  /// A scene's cat for the day test: a trip takes a few seconds, a rest pose changes at once.
  struct Scene {
    var body = NookiCatBody(moving: false, at: .home, rest: .sit)
    var arrives = 0.0
    var restChanges: [(at: Double, from: NookiRestPose)] = []
    var trips: [(at: Double, to: NookiSpot)] = []
    var arrivals: [Double] = []

    let lyingMinds: Set<CatMind> = [.loaf, .napping, .deepSleep]

    mutating func apply(_ intents: [NookiCatIntent], mind: CatMind, at t: Double) {
      for intent in intents {
        switch intent {
        case .go(let spot, _):
          #expect(!body.moving, "sent off while already walking at \(t)")
          #expect(
            spot != .basket || !lyingMinds.contains(mind), "sent to rest in the basket at \(t)")
          trips.append((t, spot))
          body = NookiCatBody(moving: true, at: spot, rest: .sit)
          arrives = t + 6
        case .rest(let rest):
          #expect(!body.moving, "rest pose changed mid-walk at \(t)")
          restChanges.append((t, body.rest))
          body.rest = rest
        case .act, .look, .drowse: break
        }
      }
    }

    mutating func tick(_ t: Double) {
      if body.moving && t >= arrives {
        body.moving = false
        arrivals.append(t)
      }
    }
  }

  @Test("a simulated day through the script never flaps the cat's body")
  func simulatedDay() {
    let events = Day.bothActive
    let from = Day.at(0)
    let until = Day.at(24)
    var runner = CatBrainRunner(
      events: events, now: from, context: Day.context, seed: 11,
      room: NookiSpot.affordances(Self.spots))
    var script = NookiCatScript(spots: Self.spots)
    var scene = Scene()
    var minds = Set<CatMind>()
    var t = from
    while t < until {
      runner.advance(to: t)
      scene.tick(t)
      let frame = runner.frame
      let mind = CatMind(frame.stack, hour: runner.brain.hour(at: t))
      minds.insert(mind)
      scene.apply(script.next(frame, mind: mind, body: scene.body, now: t), mind: mind, at: t)
      if [.loaf, .napping, .deepSleep].contains(mind), !scene.body.moving, scene.body.rest != .sit {
        #expect(NookiCatScript.beds.contains(scene.body.at), "lying at \(scene.body.at) at \(t)")
      }
      t += 0.5
    }

    var restSince = -Double.infinity
    for change in scene.restChanges {
      #expect(
        change.at - restSince >= change.from.dwell - 1e-9, "rest pose flapped at \(change.at)")
      restSince = change.at
    }
    for trip in scene.trips {
      let last = scene.arrivals.last { $0 <= trip.at }
      if let last {
        #expect(
          trip.at - last >= NookiCatScript.spotDwell - 1e-9, "sent off too soon at \(trip.at)")
      }
    }
    #expect(scene.trips.count > 10, "the cat should get about in a day")
    #expect(scene.trips.count < 24 * 60, "the cat should not be on the move all day")
    #expect(scene.restChanges.contains { $0.from == .sleep }, "the cat should sleep and wake")
    #expect(minds.contains(.deepSleep))
    #expect(minds.contains(.exploring) || minds.contains(.playing))
  }
}

@Suite("CatMindTour")
struct CatMindTourTests {
  @Test("the tour shows the owner's states in order, through the script")
  func tour() {
    let tour = CatMindTour.standard
    #expect(tour.seconds >= 85 && tour.seconds <= 95)
    let minds = tour.stops.map { CatMind($0.stack, hour: 12) }
    #expect(
      minds == [
        .idle, .exploring, .playing, .grooming, .loaf, .napping, .beingPetted, .napping,
      ])
    #expect(tour.stop(at: 0)?.start == 0)
    #expect(tour.stop(at: tour.seconds) == nil)

    var script = NookiCatScript(spots: [.home, .tree, .sill, .ball, .basket])
    var scene = NookiCatScriptTests.Scene()
    var rests: [NookiRestPose] = []
    var t = 0.0
    while let (stop, start) = tour.stop(at: t) {
      scene.tick(t)
      let mind = CatMind(stop.stack, hour: 12)
      let frame = CatMindTour.frame(stop, start: start)
      scene.apply(script.next(frame, mind: mind, body: scene.body, now: t), mind: mind, at: t)
      if rests.last != scene.body.rest { rests.append(scene.body.rest) }
      t += 0.25
    }
    #expect(scene.trips.map(\.to) == [.tree, .ball, .home])
    #expect(rests == [.sit, .loaf, .sleep], "the pet leaves her asleep")
  }
}
