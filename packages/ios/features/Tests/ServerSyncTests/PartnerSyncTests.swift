import Synchronization
import Testing

@testable import ServerSync

@Suite nonisolated struct PartnerSyncMachineTests {
  typealias M = PartnerSyncMachine
  typealias State = M.State

  static func following(clock: Int, _ pull: M.Pull, serial: Int) -> State {
    State(mode: .following(M.Following(clock: clock, pull: pull)), serial: serial)
  }

  @Test func comingToTheFrontPairedFollowsPullsAndStartsTheClock() {
    let (state, outputs) = M.transition(State(mode: .away(paired: true), serial: 4), .cameToFront)
    #expect(state == Self.following(clock: 5, .pulling(6), serial: 6))
    #expect(outputs == [.follow, .pull(6), .tick(clock: 5)])
  }

  @Test func comingToTheFrontUnpairedFollowsNothing() {
    let (state, outputs) = M.transition(.initial, .cameToFront)
    #expect(state == State(mode: .unpaired, serial: 0))
    #expect(outputs.isEmpty)
  }

  @Test func aPairMadeInFrontFollowsAtOnce() {
    let (state, outputs) = M.transition(State(mode: .unpaired, serial: 0), .paired)
    #expect(state == Self.following(clock: 1, .pulling(2), serial: 2))
    #expect(outputs == [.follow, .pull(2), .tick(clock: 1)])
  }

  @Test func aPairLearnedAwayIsFollowedOnTheReturn() {
    let (away, none) = M.transition(.initial, .paired)
    #expect(away == State(mode: .away(paired: true), serial: 0))
    #expect(none.isEmpty)
    let (state, outputs) = M.transition(away, .cameToFront)
    #expect(state == Self.following(clock: 1, .pulling(2), serial: 2))
    #expect(outputs == [.follow, .pull(2), .tick(clock: 1)])
  }

  @Test func aPairEndedAwayIsNotFollowedOnTheReturn() {
    let (state, _) = M.transition(State(mode: .away(paired: true), serial: 3), .unpaired)
    #expect(state == State(mode: .away(paired: false), serial: 3))
    #expect(M.transition(state, .cameToFront).1.isEmpty)
  }

  @Test func goingAwayUnfollows() {
    let (state, outputs) = M.transition(Self.following(clock: 1, .resting, serial: 2), .wentAway)
    #expect(state == State(mode: .away(paired: true), serial: 2))
    #expect(outputs == [.unfollow])
  }

  @Test func unpairingInFrontUnfollows() {
    let (state, outputs) = M.transition(Self.following(clock: 1, .resting, serial: 2), .unpaired)
    #expect(state == State(mode: .unpaired, serial: 2))
    #expect(outputs == [.unfollow])
  }

  @Test func goingAwayUnpairedIsQuiet() {
    let (state, outputs) = M.transition(State(mode: .unpaired, serial: 2), .wentAway)
    #expect(state == State(mode: .away(paired: false), serial: 2))
    #expect(outputs.isEmpty)
  }

  @Test func aTickWhileRestingPullsAndFollowsAgain() {
    let (state, outputs) = M.transition(
      Self.following(clock: 1, .resting, serial: 2), .ticked(clock: 1))
    #expect(state == Self.following(clock: 3, .pulling(4), serial: 4))
    #expect(outputs == [.follow, .tick(clock: 3), .pull(4)])
  }

  @Test func aTickDuringAPullQueuesOneMore() {
    let (state, outputs) = M.transition(
      Self.following(clock: 1, .pulling(2), serial: 2), .ticked(clock: 1))
    #expect(state == Self.following(clock: 3, .pullingThenAgain(2), serial: 3))
    #expect(outputs == [.follow, .tick(clock: 3)])
    let (again, more) = M.transition(state, .ticked(clock: 3))
    #expect(again == Self.following(clock: 4, .pullingThenAgain(2), serial: 4))
    #expect(more == [.follow, .tick(clock: 4)])
  }

  @Test func aFinishedPullRests() {
    let (state, outputs) = M.transition(
      Self.following(clock: 1, .pulling(2), serial: 2), .pulled(2))
    #expect(state == Self.following(clock: 1, .resting, serial: 2))
    #expect(outputs.isEmpty)
  }

  @Test func aFinishedPullWithOneQueuedStartsIt() {
    let (state, outputs) = M.transition(
      Self.following(clock: 3, .pullingThenAgain(2), serial: 3), .pulled(2))
    #expect(state == Self.following(clock: 3, .pulling(4), serial: 4))
    #expect(outputs == [.pull(4)])
  }

  @Test func aPullFromBeforeGoingAwayDoesNotEndTheNewOne() {
    var (state, _) = M.transition(Self.following(clock: 1, .pulling(2), serial: 2), .wentAway)
    (state, _) = M.transition(state, .cameToFront)
    #expect(state == Self.following(clock: 3, .pulling(4), serial: 4))
    let (after, outputs) = M.transition(state, .pulled(2))
    #expect(after == state)
    #expect(outputs.isEmpty)
  }

  @Test func aStaleTickChangesNothing() {
    let state = Self.following(clock: 3, .resting, serial: 4)
    let (after, outputs) = M.transition(state, .ticked(clock: 1))
    #expect(after == state)
    #expect(outputs.isEmpty)
  }

  static let rejected: [(State, M.Event)] = [
    (State(mode: .away(paired: true), serial: 1), .wentAway),
    (State(mode: .away(paired: true), serial: 1), .ticked(clock: 1)),
    (State(mode: .away(paired: false), serial: 1), .pulled(1)),
    (State(mode: .unpaired, serial: 1), .cameToFront),
    (State(mode: .unpaired, serial: 1), .unpaired),
    (State(mode: .unpaired, serial: 1), .ticked(clock: 1)),
    (State(mode: .unpaired, serial: 1), .pulled(1)),
    (following(clock: 1, .resting, serial: 2), .cameToFront),
    (following(clock: 1, .resting, serial: 2), .paired),
    (following(clock: 1, .resting, serial: 2), .pulled(2)),
    (following(clock: 1, .pulling(2), serial: 2), .pulled(7)),
    (following(clock: 1, .pullingThenAgain(2), serial: 2), .pulled(7)),
  ]

  @Test(arguments: rejected.indices) func rejectedEventsChangeNothing(_ index: Int) {
    let (state, event) = Self.rejected[index]
    let (after, outputs) = M.transition(state, event)
    #expect(after == state)
    #expect(outputs.isEmpty)
  }
}

/// A fake socket and server: counts follows and pulls, and holds each tick until the test lets it go.
@MainActor
final class FakeLink {
  var follows = 0
  var unfollows = 0
  var pulls = 0
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
        pull: { [self] in pulls += 1 }, sleep: { _ in await ticks.sleep() }))
  }
}

@MainActor
@Suite struct PartnerSyncTests {
  @Test func followsAndPullsOnTheFrontThenOnEachTick() async {
    let link = FakeLink()
    let sync = link.sync()
    sync.send(.paired)
    sync.send(.cameToFront)
    while link.ticks.count == 0 { await Task.yield() }
    #expect(link.follows == 1)
    #expect(link.pulls == 1)

    link.ticks.release()
    while link.ticks.count == 0 { await Task.yield() }
    while link.pulls < 2 { await Task.yield() }
    #expect(link.follows == 2)

    sync.send(.wentAway)
    link.ticks.release()
    await sync.settled()
    #expect(link.unfollows == 1)
    #expect(link.pulls == 2)
    #expect(link.ticks.count == 0)
  }

  @Test func unpairedFollowsNothing() async {
    let link = FakeLink()
    let sync = link.sync()
    sync.send(.cameToFront)
    await sync.settled()
    #expect(link.follows == 0)
    #expect(link.pulls == 0)
    #expect(sync.state.mode == .unpaired)
  }
}
