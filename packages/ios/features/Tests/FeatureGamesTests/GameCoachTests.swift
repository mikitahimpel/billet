import GamesInterface
import Testing

@testable import FeatureGames

@Suite struct GameCoachTests {
  typealias M = GameCoach

  static let acceptedPairs: [(M.State, M.Event, M.State)] = [
    (.idle, .step(0), .showing(step: 0)),
    (.idle, .step(nil), .idle),
    (.showing(step: 0), .step(0), .showing(step: 0)),
    (.showing(step: 0), .step(1), .showing(step: 1)),
    (.showing(step: 0), .step(nil), .idle),
    (.showing(step: 0), .touched, .quiet(step: 0, idle: 0)),
    (.quiet(step: 0, idle: 2), .touched, .quiet(step: 0, idle: 0)),
    (.quiet(step: 0, idle: 1), .tick(1), .quiet(step: 0, idle: 2)),
    (.quiet(step: 0, idle: 4.5), .tick(0.5), .showing(step: 0)),
    (.quiet(step: 0, idle: 3), .step(0), .quiet(step: 0, idle: 3)),
    (.quiet(step: 0, idle: 3), .step(2), .showing(step: 2)),
    (.quiet(step: 0, idle: 3), .step(nil), .idle),
  ]

  @Test(arguments: acceptedPairs)
  func accepted(_ state: M.State, _ event: M.Event, _ expected: M.State) {
    let (next, outputs) = M.transition(state, event)
    #expect(next == expected)
    #expect(outputs.isEmpty)
  }

  static let rejectedPairs: [(M.State, M.Event)] = [
    (.idle, .touched),
    (.idle, .tick(1)),
    (.showing(step: 0), .tick(30)),
  ]

  @Test(arguments: rejectedPairs)
  func rejected(_ state: M.State, _ event: M.Event) {
    let (next, outputs) = M.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }

  @Test func theHandGoesAtTheFirstTouchAndComesBackWhenLeftAlone() {
    var state = M.transition(.idle, .step(0)).0
    #expect(state.shown == 0)
    state = M.transition(state, .touched).0
    #expect(state.shown == nil)
    for _ in 0..<49 { state = M.transition(state, .tick(0.1)).0 }
    #expect(state.shown == nil)
    state = M.transition(state, .tick(0.2)).0
    #expect(state.shown == 0)
  }

  @Test func aNewStepShowsAtOnceEvenRightAfterATouch() {
    var state = M.transition(.showing(step: 0), .touched).0
    state = M.transition(state, .step(1)).0
    #expect(state.shown == 1)
  }

  @Test func aBackwardTickChangesNothing() {
    let (state, _) = M.transition(.quiet(step: 0, idle: 1), .tick(-3))
    #expect(state == .quiet(step: 0, idle: 1))
  }
}

@Suite struct GameSceneryTests {
  @Test func feedAndWaterAreOnlyPlayedInTheKitchen() {
    for game in [MiniGame.feed, .water] {
      #expect(GameScenery.options(for: game) == [.kitchen])
    }
  }

  @Test func theBrushOffersTwoCornersAndTheLaserIsOnlyPlayedInTheRoom() {
    let brush = GameScenery.options(for: .brush)
    #expect(brush.count == 2)
    #expect(Set(brush).count == 2)
    #expect(brush.allSatisfy { $0.isCorner })
    #expect(GameScenery.options(for: .laser) == [.room])
    #expect(!GameScenery.options(for: .laser).contains(.kitchen))
  }

  @Test func eachGameIsPlayedInItsOwnScene() {
    #expect(GameScenery.start(.feed) == .kitchen)
    #expect(GameScenery.start(.water) == .kitchen)
    #expect(GameScenery.start(.brush) == .rug)
    #expect(GameScenery.start(.laser) == .room)
  }
}

@Suite struct GameGazeTests {
  @Test func aFingerTakesHerEyesAtOnce() {
    var gaze = GameGaze()
    #expect(gaze.update(dt: 0.016, touching: true) == .finger)
  }

  @Test func leftAloneSheMostlyLooksAtThePlayerAndGlancesAwayNowAndThen() {
    var gaze = GameGaze()
    #expect(gaze.update(dt: 0.1, touching: false) == .player)
    #expect(gaze.update(dt: 3.5, touching: false) == .free)
    #expect(gaze.update(dt: 1.4, touching: false) == .player)
  }

  @Test func afterTheFingerLiftsSheLooksAtThePlayerFirst() {
    var gaze = GameGaze()
    _ = gaze.update(dt: 3.6, touching: false)
    _ = gaze.update(dt: 0.1, touching: true)
    #expect(gaze.update(dt: 0.1, touching: false) == .player)
  }

  @Test func aSuccessTurnsHerBackToThePlayer() {
    var gaze = GameGaze()
    #expect(gaze.update(dt: 3.7, touching: false) == .free)
    gaze.pleased()
    #expect(gaze.update(dt: 0.1, touching: false) == .player)
  }
}
