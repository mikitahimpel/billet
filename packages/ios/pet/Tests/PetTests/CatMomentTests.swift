import Foundation
import Testing

@testable import Pet
#if canImport(simd)
  import simd
#endif

@Suite("CatTrip")
struct CatTripTests {
  @Test func walksOutHoldsAndComesBack() {
    let home = SIMD2<Float>(0, 0)
    let away = SIMD2<Float>(0, -0.5)
    let trip = CatTrip(
      from: home, heading: .pi,
      legs: [
        .walk(to: away, speed: 0.25), .hold(.reachUp, seconds: 2),
        .walk(to: home, speed: 0.25),
      ], at: 10)
    // 0.3 s turn + 2 s walk, then 2 s held, then 0.3 s turn + 2 s back.
    #expect(abs(trip.endsAt - (10 + 2.3 + 2 + 2.3)) < 0.001)
    let turning = trip.pose(at: 10.1)
    #expect(turning.action == .idle)
    #expect(turning.spot == home)
    let walking = trip.pose(at: 11.3)
    #expect(walking.action == .walk)
    #expect(abs(walking.spot.y - -0.25) < 0.001)
    #expect(abs(walking.heading) < 0.001)
    let reaching = trip.pose(at: 13)
    #expect(reaching.action == .reachUp)
    #expect(reaching.spot == away)
    let done = trip.pose(at: 20)
    #expect(done.isDone)
    #expect(simd_distance(done.spot, home) < 0.001)
  }

  @Test func headingsFaceTheWayTheCatsAreMade() {
    #expect(abs(CatTrip.heading(from: .zero, to: [0, -1])) < 0.001)
    #expect(abs(CatTrip.heading(from: .zero, to: [-1, 0]) - .pi / 2) < 0.001)
  }

  @Test func turnsTheShortWay() {
    let turned = CatTrip.blend(3, -3, 0.5)
    #expect(abs(remainder(turned - .pi, 2 * .pi)) < 0.01)
  }

  @Test func stopsShortOfWhatItWalksTo() {
    let spot = CatTrip.towards([1, 0], from: .zero, upTo: 5, keep: 0.2)
    #expect(abs(spot.x - 0.8) < 0.001)
    #expect(CatTrip.towards([1, 0], from: .zero, upTo: 0.3).x == 0.3)
  }
}

@Suite("CatPetting")
struct CatPettingTests {
  /// Strokes every 0.1 s from `start` for `seconds`, collecting the events.
  private func stroke(_ petting: inout CatPetting, from start: Double, for seconds: Double)
    -> [CatPetting.Event]
  {
    var events: [CatPetting.Event] = []
    var t = start
    while t < start + seconds {
      events += petting.touch(at: t)
      t += 0.1
    }
    return events
  }

  @Test func aShortPetPurrsWithHeartsAndNoRoll() {
    var petting = CatPetting()
    let events = stroke(&petting, from: 0, for: 1.5)
    #expect(events.first == .purrStarted)
    #expect(events.filter { $0 == .heart }.count >= 2)
    #expect(!events.contains(.rolled))
    #expect(petting.tick(at: 2.1) == [.purrEnded])
    #expect(!petting.isPurring)
  }

  @Test func theRollComesWithATouchEvenWhenFramesTickInBetween() {
    var petting = CatPetting()
    var rolledOnTouch = false
    var t = 0.0
    while t < 4 {
      #expect(!petting.tick(at: t).contains(.rolled))
      if Int((t * 60).rounded()) % 12 == 0, petting.touch(at: t).contains(.rolled) {
        rolledOnTouch = true
      }
      t += 1.0 / 60
    }
    #expect(rolledOnTouch)
  }

  @Test func aLongPetRollsOnceThenWaits() {
    var petting = CatPetting()
    let first = stroke(&petting, from: 0, for: 4)
    #expect(first.filter { $0 == .rolled }.count == 1)
    _ = petting.tick(at: 5)
    let soon = stroke(&petting, from: 6, for: 4)
    #expect(!soon.contains(.rolled))
    _ = petting.tick(at: 11)
    let later = stroke(&petting, from: 20, for: 4)
    #expect(later.contains(.rolled))
  }
}

@Suite("CatMoments")
struct CatMomentRuleTests {
  @Test func greetsOnlyAfterHoursAway() {
    let now = Date(timeIntervalSince1970: 100_000)
    #expect(!CatGreeting.isDue(lastSeen: nil, now: now))
    #expect(!CatGreeting.isDue(lastSeen: now.addingTimeInterval(-60), now: now))
    #expect(CatGreeting.isDue(lastSeen: now.addingTimeInterval(-4 * 3600), now: now))
  }

  @Test func edgesAreTheSides() {
    #expect(CatEdge.isNearEdge(x: 20, width: 393))
    #expect(CatEdge.isNearEdge(x: 380, width: 393))
    #expect(!CatEdge.isNearEdge(x: 200, width: 393))
    #expect(!CatEdge.isNearEdge(x: 20, width: 100))
  }

  @Test func onlyAFingerHeldStillCountsAsResting() {
    var rest = CatFingerRest()
    // A quick swipe: the finger never stays put long enough.
    for step in 0..<20 {
      rest.moved(toX: 20 + Double(step) * 12, y: 300, at: Double(step) * 0.02)
      #expect(rest.resting(at: Double(step) * 0.02) == nil)
    }
    // Held still, small jitter allowed, it rests after the dwell.
    rest.moved(toX: 30, y: 300, at: 1)
    rest.moved(toX: 33, y: 302, at: 1.2)
    #expect(rest.resting(at: 1.2) == nil)
    #expect(rest.resting(at: 1 + CatFingerRest.dwell)?.x == 30)
    // After a bat it waits again; lifted, it is gone.
    rest.restart(at: 2)
    #expect(rest.resting(at: 2.1) == nil)
    #expect(rest.resting(at: 2 + CatFingerRest.dwell) != nil)
    // A touch whose end never came lapses.
    #expect(rest.resting(at: 1 + CatFingerRest.hold + 0.1) == nil)
    rest.lifted()
    #expect(rest.resting(at: 5) == nil)
  }

  @Test func reactionsPlayStandInsOnCatsWithoutTheClip() {
    let basic: [CatAction: CatClipInfo] = [
      .sit: CatClipInfo(duration: 4, loops: true, base: .sit),
      .idle: CatClipInfo(duration: 4, loops: true, base: .stand),
      .happy: CatClipInfo(duration: 3, loops: true, base: .sit),
      .look: CatClipInfo(duration: 4, loops: true, base: .sit),
    ]
    var cat = CatBehaviour(clips: basic, seed: 1)
    cat.react(.roll, at: 0)
    #expect(cat.beat(at: 0, mode: .awake).action == .happy)
    cat.react(.bat, at: 5)
    #expect(cat.beat(at: 5, mode: .awake).action == .look)
    #expect(cat.playable(.reachUp) == .idle)
    #expect(cat.playable(.headbutt) == .happy)
  }
}
