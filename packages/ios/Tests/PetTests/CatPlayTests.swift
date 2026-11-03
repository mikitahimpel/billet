import Foundation
import Testing

@testable import Pet

@Suite("CatBodyOnScreen")
struct CatBodyOnScreenTests {
  /// A cat lying across the screen, head on the left.
  private let body = CatBodyOnScreen(head: [100, 300], tail: [300, 300], girth: 50)

  @Test func findsTheZoneUnderTheFinger() {
    #expect(body.zone(at: [110, 290]) == .head)
    #expect(body.zone(at: [120, 330]) == .chin)
    #expect(body.zone(at: [220, 290]) == .back)
    var rolled = body
    rolled.isOnBack = true
    #expect(rolled.zone(at: [200, 300]) == .belly)
    #expect(rolled.zone(at: [290, 300]) == .back)
  }

  @Test func tellsWhichWayAStrokeRuns() {
    #expect(body.direction(of: [30, 2]) == .withFur)
    #expect(body.direction(of: [-30, -4]) == .againstFur)
    #expect(body.direction(of: [2, 30]) == .across)
    #expect(body.direction(of: [1, 0]) == .across)
  }

  @Test func onlyTouchesNearTheBodyCount() {
    #expect(body.contains([200, 320]))
    #expect(body.contains([70, 300]))
    #expect(!body.contains([200, 400]))
    #expect(!body.contains([400, 300]))
  }
}

@Suite("CatTouchRouter")
struct CatTouchRouterTests {
  @Test func touchesOnTheCatAreTheCats() {
    #expect(CatTouchRouter.route(.tap, on: .cat) == .pat)
    #expect(CatTouchRouter.route(.drag, on: .cat) == .stroke)
    #expect(CatTouchRouter.route(.doubleTap, on: .cat) == .trick)
    #expect(CatTouchRouter.route(.longPress, on: .cat) == .lift)
  }

  @Test func emptySpaceKeepsTheCamera() {
    #expect(CatTouchRouter.route(.drag, on: .nothing) == .camera)
    #expect(CatTouchRouter.route(.drag, on: .floor) == .camera)
    #expect(CatTouchRouter.route(.drag, on: .scenery) == .camera)
    #expect(CatTouchRouter.route(.doubleTap, on: .nothing) == .camera)
    #expect(CatTouchRouter.route(.doubleTap, on: .scenery) == .camera)
  }

  @Test func theFloorCallsTheCatOnlyOnADoubleTap() {
    #expect(CatTouchRouter.route(.doubleTap, on: .floor) == .call)
    #expect(CatTouchRouter.route(.tap, on: .floor) == .ignore)
  }

  @Test func toysAreCarriedOrFlung() {
    #expect(CatTouchRouter.route(.drag, on: .toy(.wand)) == .carry(.wand))
    #expect(CatTouchRouter.route(.drag, on: .toy(.laser)) == .carry(.laser))
    #expect(CatTouchRouter.route(.drag, on: .toy(.ball)) == .fling(.ball))
    #expect(CatTouchRouter.route(.drag, on: .toy(.yarn)) == .fling(.yarn))
    #expect(CatTouchRouter.route(.tap, on: .toy(.ball)) == .fling(.ball))
    #expect(CatTouchRouter.route(.tap, on: .toy(.wand)) == .ignore)
  }

  @Test func foodAndTreats() {
    #expect(CatTouchRouter.route(.tap, on: .bowl) == .fillBowl)
    #expect(CatTouchRouter.route(.drag, on: .treats) == .offerTreat)
    #expect(CatTouchRouter.route(.drag, on: .bowl) == .camera)
  }

  private func quick(_ x: Double, _ y: Double, axis: SIMD2<Double>? = nil) -> CatDragStart {
    CatDragStart(rested: 0.05, movement: [x, y], axis: axis)
  }

  @Test func aQuickSidewaysSwipeTurnsTheRoomWhateverItStartsOn() {
    let targets: [CatTouchTarget] = [
      .cat, .toy(.ball), .toy(.yarn), .toy(.wand), .toy(.laser), .treats, .bowl, .floor, .nothing,
    ]
    for target in targets {
      #expect(CatTouchRouter.routeDrag(on: target, start: quick(40, 8)) == .camera)
      #expect(CatTouchRouter.routeDrag(on: target, start: quick(-30, -10)) == .camera)
    }
    // Even along a cat lying across the screen: a quick stroke needs to rest first.
    #expect(CatTouchRouter.routeDrag(on: .cat, start: quick(40, 0, axis: [1, 0])) == .camera)
  }

  @Test func restingFirstGivesTheDragToWhatIsUnderTheFinger() {
    let rested = CatDragStart(rested: 0.2, movement: [40, 0], axis: [0, 1])
    #expect(CatTouchRouter.routeDrag(on: .cat, start: rested) == .stroke)
    #expect(CatTouchRouter.routeDrag(on: .toy(.ball), start: rested) == .fling(.ball))
    #expect(CatTouchRouter.routeDrag(on: .toy(.wand), start: rested) == .carry(.wand))
    #expect(CatTouchRouter.routeDrag(on: .treats, start: rested) == .offerTreat)
    // Resting decides at once, before the finger has gone far.
    let barely = CatDragStart(rested: 0.2, movement: [3, 0])
    #expect(CatTouchRouter.routeDrag(on: .toy(.laser), start: barely) == .carry(.laser))
  }

  @Test func aQuickDragAlongWhatAThingDoesIsThatThings() {
    #expect(CatTouchRouter.routeDrag(on: .toy(.ball), start: quick(4, -40)) == .fling(.ball))
    #expect(CatTouchRouter.routeDrag(on: .toy(.yarn), start: quick(-10, 30)) == .fling(.yarn))
    #expect(CatTouchRouter.routeDrag(on: .toy(.wand), start: quick(20, 30)) == .carry(.wand))
    #expect(CatTouchRouter.routeDrag(on: .treats, start: quick(0, 25)) == .offerTreat)
    // A cat lying down the screen is stroked down it, and turned across it.
    let down: SIMD2<Double> = [0.2, 1]
    #expect(CatTouchRouter.routeDrag(on: .cat, start: quick(5, 30, axis: down)) == .stroke)
    #expect(CatTouchRouter.routeDrag(on: .cat, start: quick(-3, -25, axis: down)) == .stroke)
    // A cat lying diagonally, stroked across its body.
    #expect(
      CatTouchRouter.routeDrag(on: .cat, start: quick(-20, 25, axis: [1, 1])) == .camera)
  }

  @Test func aQuickDragIsReadOnlyOnceItHasGoneFarEnough() {
    #expect(CatTouchRouter.routeDrag(on: .toy(.ball), start: quick(2, -6)) == nil)
    #expect(CatTouchRouter.routeDrag(on: .cat, start: quick(8, 0)) == nil)
    // Away from the cat and its things the room turns from the start.
    #expect(CatTouchRouter.routeDrag(on: .nothing, start: quick(2, 0)) == .camera)
    #expect(CatTouchRouter.routeDrag(on: .floor, start: quick(0, 3)) == .camera)
  }

  @Test func holdingTheCatTakesEveryDrag() {
    let rested = CatDragStart(rested: 1, movement: [0, 30])
    #expect(CatTouchRouter.routeDrag(on: .cat, start: rested, isHoldingCat: true) == .ignore)
    #expect(
      CatTouchRouter.routeDrag(on: .nothing, start: quick(40, 0), isHoldingCat: true) == .ignore)
  }

  @Test func holdingTheCatTakesEveryOtherTouch() {
    let gestures: [CatTouchGesture] = [.tap, .doubleTap, .drag, .longPress]
    let targets: [CatTouchTarget] = [
      .cat, .toy(.ball), .bowl, .treats, .floor, .scenery, .nothing,
    ]
    for gesture in gestures {
      for target in targets {
        #expect(CatTouchRouter.route(gesture, on: target, isHoldingCat: true) == .ignore)
      }
    }
  }
}

@Suite("CatPlay")
struct CatPlayTests {
  @Test func headAndChinCloseTheEyes() throws {
    var play = CatPlay()
    let headResponse = play.handle(.stroke(.head, .withFur), at: 0)
    let head = try #require(headResponse)
    #expect(head.reaction == .lean(eyesClosed: true))
    // The stroke's start reports the pet; the machine counts no more for it.
    #expect(head.need == nil)
    let chinResponse = play.handle(.stroke(.chin, .across), at: 1)
    let chin = try #require(chinResponse)
    #expect(chin.reaction == .lean(eyesClosed: true))
    #expect(chin.haptic == .purr(strength: 0.75))
    let backResponse = play.handle(.stroke(.back, .withFur), at: 2)
    let back = try #require(backResponse)
    #expect(back.reaction == .lean(eyesClosed: false))
  }

  @Test func againstTheFurFlicksTheTail() throws {
    var play = CatPlay()
    let responseResponse = play.handle(.stroke(.back, .againstFur), at: 0)
    let response = try #require(responseResponse)
    #expect(response.reaction == .flick)
    #expect(response.haptic == .nudge)
  }

  @Test func bellyRubsSometimesEndInAGrabButNotOverAndOver() {
    var play = CatPlay(seed: 7)
    var grabs: [Double] = []
    for second in stride(from: 0.0, to: 60, by: 0.5) {
      if play.handle(.stroke(.belly, .withFur), at: second)?.reaction == .grab {
        grabs.append(second)
      }
    }
    #expect(!grabs.isEmpty)
    for (a, b) in zip(grabs, grabs.dropFirst()) {
      #expect(b - a >= CatPlay.tiring(.belly).cooldown)
    }
  }

  @Test func aToyTiresTheCatUntilItOnlyWatches() {
    var play = CatPlay()
    var reactions: [CatPlayReaction] = []
    for go in 0..<8 {
      if let response = play.handle(.toyMoved(.wand), at: Double(go) * 2) {
        reactions.append(response.reaction)
      }
    }
    #expect(reactions.first == .stalk(.wand))
    #expect(reactions.last == .watch(.wand))
    // A rest brings the keenness back.
    #expect(play.handle(.toyMoved(.wand), at: 400)?.reaction == .stalk(.wand))
  }

  @Test func aToyMovedAgainAtOnceIsLetPass() {
    var play = CatPlay()
    #expect(play.handle(.toyMoved(.laser), at: 0) != nil)
    #expect(play.handle(.toyMoved(.laser), at: 0.5) == nil)
  }

  @Test func onlyTheBallIsBroughtBack() {
    var fetched = false
    for seed in UInt64(1)...40 {
      var play = CatPlay(seed: seed)
      if case .chase(_, true) = play.handle(.toyMoved(.ball), at: 0)?.reaction { fetched = true }
      if case .chase(_, let fetch) = play.handle(.toyMoved(.yarn), at: 0)?.reaction {
        #expect(!fetch)
      }
    }
    #expect(fetched)
  }

  @Test func aCaughtToyCountsAsPlay() {
    var play = CatPlay()
    let caught = play.handle(.toyCaught(.ball), at: 0)
    #expect(caught?.reaction == .caught(.ball))
    #expect(caught?.haptic == .pounce)
    #expect(caught?.need == .play)
    #expect(play.handle(.toyCaught(.ball), at: 5)?.need == nil)
    #expect(play.handle(.toyCaught(.wand), at: 59)?.need == nil)
    #expect(play.handle(.toyCaught(.wand), at: 61)?.need == .play)
  }

  @Test func aFullCatRefusesTheBowl() {
    var play = CatPlay()
    let first = play.handle(.bowlFilled, at: 0)
    #expect(first?.reaction == .eat)
    #expect(first?.need == .feed)
    #expect(play.handle(.bowlFilled, at: 5)?.reaction == .refuse)
    #expect(play.handle(.bowlFilled, at: 30)?.reaction == .refuse)
    #expect(play.handle(.bowlFilled, at: 3000)?.reaction == .eat)
  }

  @Test func treatsAreTakenUntilTheCatIsFull() {
    var play = CatPlay()
    var reactions: [CatPlayReaction] = []
    for go in 0..<6 {
      if let response = play.handle(.treatHeldOut, at: Double(go) * 5) {
        reactions.append(response.reaction)
      }
    }
    #expect(reactions.prefix(3).allSatisfy { $0 == .takeTreat })
    #expect(reactions.last == .refuse)
  }

  @Test func tricksTakeTurnsAndTire() {
    var play = CatPlay()
    let tricks = (0..<3).compactMap { play.handle(.trickAsked, at: Double($0) * 3)?.reaction }
    #expect(tricks == [.trick(.sit), .trick(.wave), .trick(.spin)])
    #expect(play.handle(.trickAsked, at: 7) == nil)
    var last: CatPlayReaction?
    for go in 4..<10 { last = play.handle(.trickAsked, at: Double(go) * 3)?.reaction ?? last }
    #expect(last == .ignore)
  }

  @Test func callingWorksUntilTheCatIsTiredOfIt() {
    var play = CatPlay()
    #expect(play.handle(.called, at: 0)?.reaction == .come)
    #expect(play.handle(.called, at: 1) == nil)
    var last: CatPlayReaction?
    for go in 1..<10 { last = play.handle(.called, at: Double(go) * 4)?.reaction ?? last }
    #expect(last == .ignore)
  }

  @Test func liftingAlwaysDanglesAndPlacingSettles() {
    var play = CatPlay()
    for go in 0..<5 {
      #expect(play.handle(.lifted, at: Double(go))?.reaction == .dangle)
    }
    #expect(play.handle(.placed, at: 6)?.reaction == .settle)
  }

  @Test func thePartnersCareShowsButIsNotCountedHere() {
    var play = CatPlay()
    let love = play.handle(.partnerPetted, at: 0)
    #expect(love?.reaction == .partnerLove)
    #expect(love?.need == nil)
    #expect(play.handle(.partnerTreated, at: 1) == nil)
    #expect(play.handle(.partnerTreated, at: 3)?.reaction == .partnerLove)
  }
}
