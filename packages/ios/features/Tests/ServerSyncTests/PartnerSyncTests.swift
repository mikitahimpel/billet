import Synchronization
import Testing

@testable import ServerSync

@Suite nonisolated struct PartnerSyncMachineTests {
  typealias M = PartnerSyncMachine
  typealias State = M.State

  static func following(clock: Int, _ pull: M.Pull, _ socket: M.Socket, serial: Int) -> State {
    State(mode: .following(M.Following(clock: clock, pull: pull, socket: socket)), serial: serial)
  }

  @Test func comingToTheFrontPairedFollowsAndGivesTheSocketItsGrace() {
    let (state, outputs) = M.transition(State(mode: .away(paired: true), serial: 4), .cameToFront)
    #expect(state == Self.following(clock: 5, .resting, .opening, serial: 5))
    #expect(outputs == [.follow, .tick(clock: 5, after: M.openingGrace)])
  }

  @Test func comingToTheFrontUnpairedFollowsNothing() {
    let (state, outputs) = M.transition(.initial, .cameToFront)
    #expect(state == State(mode: .unpaired, serial: 0))
    #expect(outputs.isEmpty)
  }

  @Test func aPairMadeInFrontFollowsAtOnce() {
    let (state, outputs) = M.transition(State(mode: .unpaired, serial: 0), .paired)
    #expect(state == Self.following(clock: 1, .resting, .opening, serial: 1))
    #expect(outputs == [.follow, .tick(clock: 1, after: M.openingGrace)])
  }

  @Test func aPairLearnedAwayIsFollowedOnTheReturn() {
    let (away, none) = M.transition(.initial, .paired)
    #expect(away == State(mode: .away(paired: true), serial: 0))
    #expect(none.isEmpty)
    let (_, outputs) = M.transition(away, .cameToFront)
    #expect(outputs.first == .follow)
  }

  @Test func aPairEndedAwayIsNotFollowedOnTheReturn() {
    let (state, _) = M.transition(State(mode: .away(paired: true), serial: 3), .unpaired)
    #expect(state == State(mode: .away(paired: false), serial: 3))
    #expect(M.transition(state, .cameToFront).1.isEmpty)
  }

  @Test func theSocketOpeningPullsEverythingAndWaitsAMinute() {
    let (state, outputs) = M.transition(
      Self.following(clock: 1, .resting, .opening, serial: 1), .socketOpened)
    #expect(state == Self.following(clock: 2, .pulling(3), .healthy, serial: 3))
    #expect(outputs == [.tick(clock: 2, after: M.healthyEvery), .pull(3, .everything)])
  }

  @Test func aReconnectDuringAPullPullsEverythingAfterIt() {
    let (state, outputs) = M.transition(
      Self.following(clock: 4, .pulling(3), .silent(failures: 2), serial: 4), .socketOpened)
    #expect(state == Self.following(clock: 5, .pullingThen(3, .everything), .healthy, serial: 5))
    #expect(outputs == [.tick(clock: 5, after: M.healthyEvery)])
  }

  @Test func aTickChecksTheSocket() {
    let state = Self.following(clock: 2, .resting, .healthy, serial: 3)
    let (after, outputs) = M.transition(state, .ticked(clock: 2))
    #expect(after == state)
    #expect(outputs == [.follow, .check(clock: 2)])
  }

  @Test func aHealthySocketPullsOnlyTheSummaryEveryMinute() {
    let (state, outputs) = M.transition(
      Self.following(clock: 2, .resting, .healthy, serial: 3), .checked(clock: 2, healthy: true))
    #expect(state == Self.following(clock: 4, .pulling(5), .healthy, serial: 5))
    #expect(outputs == [.tick(clock: 4, after: .seconds(60)), .pull(5, .summary)])
  }

  @Test func aSilentSocketPullsEverythingBackingOffToAMinute() {
    var state = Self.following(clock: 1, .resting, .opening, serial: 1)
    var delays: [Duration] = []
    for _ in 0..<4 {
      guard case .following(let before) = state.mode else {
        Issue.record("not following")
        return
      }
      let (next, outputs) = M.transition(state, .checked(clock: before.clock, healthy: false))
      guard case .following(let after) = next.mode, case .pulling(let id) = after.pull else {
        Issue.record("no pull")
        return
      }
      #expect(outputs.contains(.pull(id, .everything)))
      for case .tick(_, let delay) in outputs { delays.append(delay) }
      state = M.transition(next, .pulled(id)).0
    }
    #expect(delays == [15, 30, 60, 60].map { .seconds($0) })
  }

  @Test func aHealthyAnswerEndsTheBackOff() {
    let (state, outputs) = M.transition(
      Self.following(clock: 2, .resting, .silent(failures: 3), serial: 2),
      .checked(clock: 2, healthy: true))
    #expect(state == Self.following(clock: 3, .pulling(4), .healthy, serial: 4))
    #expect(outputs == [.tick(clock: 3, after: M.healthyEvery), .pull(4, .summary)])
  }

  @Test func aSummaryAskedDuringAFullPullKeepsTheFullOneQueued() {
    let (state, _) = M.transition(
      Self.following(clock: 2, .pullingThen(1, .everything), .healthy, serial: 2),
      .checked(clock: 2, healthy: true))
    #expect(state == Self.following(clock: 3, .pullingThen(1, .everything), .healthy, serial: 3))
  }

  @Test func aFinishedPullWithOneQueuedStartsIt() {
    let (state, outputs) = M.transition(
      Self.following(clock: 3, .pullingThen(2, .summary), .healthy, serial: 3), .pulled(2))
    #expect(state == Self.following(clock: 3, .pulling(4), .healthy, serial: 4))
    #expect(outputs == [.pull(4, .summary)])
  }

  @Test func aFinishedPullRests() {
    let (state, outputs) = M.transition(
      Self.following(clock: 1, .pulling(2), .healthy, serial: 2), .pulled(2))
    #expect(state == Self.following(clock: 1, .resting, .healthy, serial: 2))
    #expect(outputs.isEmpty)
  }

  @Test func goingAwayUnfollowsAndStopsTheClock() {
    let (state, outputs) = M.transition(
      Self.following(clock: 1, .pulling(2), .healthy, serial: 2), .wentAway)
    #expect(state == State(mode: .away(paired: true), serial: 2))
    #expect(outputs == [.unfollow])
    #expect(M.transition(state, .ticked(clock: 1)).1.isEmpty)
  }

  @Test func unpairingInFrontUnfollows() {
    let (state, outputs) = M.transition(
      Self.following(clock: 1, .resting, .healthy, serial: 2), .unpaired)
    #expect(state == State(mode: .unpaired, serial: 2))
    #expect(outputs == [.unfollow])
  }

  @Test func goingAwayUnpairedIsQuiet() {
    let (state, outputs) = M.transition(State(mode: .unpaired, serial: 2), .wentAway)
    #expect(state == State(mode: .away(paired: false), serial: 2))
    #expect(outputs.isEmpty)
  }

  @Test func aPullFromBeforeGoingAwayDoesNotEndTheNewOne() {
    var (state, _) = M.transition(
      Self.following(clock: 1, .pulling(2), .healthy, serial: 2), .wentAway)
    (state, _) = M.transition(state, .cameToFront)
    (state, _) = M.transition(state, .socketOpened)
    #expect(state == Self.following(clock: 4, .pulling(5), .healthy, serial: 5))
    let (after, outputs) = M.transition(state, .pulled(2))
    #expect(after == state)
    #expect(outputs.isEmpty)
  }

  static let rejected: [(State, M.Event)] = [
    (State(mode: .away(paired: true), serial: 1), .wentAway),
    (State(mode: .away(paired: true), serial: 1), .socketOpened),
    (State(mode: .away(paired: true), serial: 1), .ticked(clock: 1)),
    (State(mode: .away(paired: true), serial: 1), .checked(clock: 1, healthy: true)),
    (State(mode: .away(paired: false), serial: 1), .pulled(1)),
    (State(mode: .unpaired, serial: 1), .cameToFront),
    (State(mode: .unpaired, serial: 1), .unpaired),
    (State(mode: .unpaired, serial: 1), .socketOpened),
    (State(mode: .unpaired, serial: 1), .ticked(clock: 1)),
    (State(mode: .unpaired, serial: 1), .checked(clock: 1, healthy: false)),
    (State(mode: .unpaired, serial: 1), .pulled(1)),
    (following(clock: 1, .resting, .healthy, serial: 2), .cameToFront),
    (following(clock: 1, .resting, .healthy, serial: 2), .paired),
    (following(clock: 3, .resting, .healthy, serial: 3), .ticked(clock: 1)),
    (following(clock: 3, .resting, .healthy, serial: 3), .checked(clock: 1, healthy: false)),
    (following(clock: 1, .resting, .healthy, serial: 2), .pulled(2)),
    (following(clock: 1, .pulling(2), .healthy, serial: 2), .pulled(7)),
    (following(clock: 1, .pullingThen(2, .summary), .healthy, serial: 2), .pulled(7)),
  ]

  @Test(arguments: rejected.indices) func rejectedEventsChangeNothing(_ index: Int) {
    let (state, event) = Self.rejected[index]
    let (after, outputs) = M.transition(state, event)
    #expect(after == state)
    #expect(outputs.isEmpty)
  }
}

/// A fake socket and server: counts follows and pulls, answers checks as told, and holds each tick
/// until the test lets it go.
@MainActor
final class FakeLink {
  var follows = 0
  var unfollows = 0
  var pulls: [PartnerSyncMachine.Kind] = []
  var healthy = true
  let ticks = Ticks()

  final class Ticks: Sendable {
    private let waiting = Mutex<[CheckedContinuation<Void, Never>]>([])

    func sleep() async {
      await withCheckedContinuation { continuation in waiting.withLock { $0.append(continuation) } }
    }

    var count: Int { waiting.withLock { $0.count } }

    func release() {
      let all = waiting.withLock { held in
        defer { held = [] }
        return held
      }
      for continuation in all { continuation.resume() }
    }
  }

  func sync() -> PartnerSync {
    let ticks = ticks
    return PartnerSync(
      .init(
        follow: { [self] in follows += 1 }, unfollow: { [self] in unfollows += 1 },
        isHealthy: { [self] _ in healthy }, pull: { [self] in pulls.append($0) },
        sleep: { _ in await ticks.sleep() }))
  }

  func nextTick() async {
    while ticks.count == 0 { await Task.yield() }
  }
}

@MainActor
@Suite struct PartnerSyncTests {
  @Test func pullsEverythingOnOpeningThenTheSummaryWhileHealthy() async {
    let link = FakeLink()
    let sync = link.sync()
    sync.send(.paired)
    sync.send(.cameToFront)
    sync.send(.socketOpened)
    while link.pulls.isEmpty || link.ticks.count < 2 { await Task.yield() }
    #expect(link.follows == 1)
    #expect(link.pulls == [.everything])

    // The opening's grace tick is stale by now; the minute's tick checks.
    link.ticks.release()
    while link.pulls.count < 2 { await Task.yield() }
    #expect(link.pulls == [.everything, .summary])

    link.healthy = false
    await link.nextTick()
    link.ticks.release()
    while link.pulls.count < 3 { await Task.yield() }
    #expect(link.pulls == [.everything, .summary, .everything])

    sync.send(.wentAway)
    link.ticks.release()
    await sync.settled()
    #expect(link.unfollows == 1)
    #expect(link.pulls.count == 3)
    #expect(link.ticks.count == 0)
  }

  @Test func unpairedFollowsNothing() async {
    let link = FakeLink()
    let sync = link.sync()
    sync.send(.cameToFront)
    await sync.settled()
    #expect(link.follows == 0)
    #expect(link.pulls.isEmpty)
    #expect(sync.state.mode == .unpaired)
  }
}
