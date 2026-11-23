import Foundation
import SchoolInterface
import Synchronization
import Testing
import Transport
import Wire

@testable import FeatureSchool

@MainActor
@Suite struct SchoolStoreTests {
  final class Room: Sendable {
    let book = Mutex(SchoolBook())
    let fails = Mutex(false)

    var client: SchoolClient {
      SchoolClient(
        fetch: { self.book.withLock { $0 } },
        teach: { trick, star in
          guard !self.fails.withLock({ $0 }) else { return nil }
          return self.book.withLock {
            $0.skills[trick] = TrickSkill(trick: trick, stars: star, teacher: "me")
            return $0
          }
        },
        send: { take in
          guard !self.fails.withLock({ $0 }) else { return nil }
          return self.book.withLock {
            $0.mine = take
            return $0
          }
        })
    }
  }

  final class Counted {
    var events: [ClientEvent] = []
    var moves: [SchoolMove] = []
  }

  private func make(_ room: Room, _ counted: Counted) -> SchoolStore {
    let stage = SchoolStage()
    stage.perform = { counted.moves.append($0) }
    return .school(
      SchoolServices(
        client: room.client, stage: stage, events: EventReporter { counted.events.append($0) },
        beat: .zero))
  }

  private func pass(_ store: SchoolStore) async {
    while case .lesson(let lesson)? = store.state.desk?.screen {
      switch lesson {
      case .cue(let run):
        for window in run.current.windows { store.send(.lesson(.tapped(window.lowerBound))) }
      case .judged: store.send(.lesson(.next))
      case .passed, .missed: return
      }
    }
  }

  @Test func aLessonPassedEarnsAStarInTheRoomAndIsCounted() async {
    let room = Room()
    let counted = Counted()
    let store = make(room, counted)
    store.send(.enabled)
    await store.settled()
    store.send(.opened)
    store.send(.teach(.spin, seed: 1))
    await pass(store)
    await store.settled()

    #expect(store.state.desk?.book.stars(of: .spin) == 1)
    #expect(store.state.desk?.saving == .idle)
    #expect(counted.events == [ClientEvent(.trickTaught, detail: "spin")])
    #expect(counted.moves == [.trick(.spin), .trick(.spin), .trick(.spin)])
  }

  @Test func aStarTheRoomDidNotTakeIsKeptAndSentAgain() async {
    let room = Room()
    let counted = Counted()
    let store = make(room, counted)
    store.send(.enabled)
    await store.settled()
    store.send(.opened)
    room.fails.withLock { $0 = true }
    store.send(.teach(.bow, seed: 1))
    await pass(store)
    await store.settled()
    #expect(store.state.desk?.saving == .failed(.bow, star: 1))
    #expect(counted.events == [])

    room.fails.withLock { $0 = false }
    store.send(.retrySave)
    await store.settled()
    #expect(store.state.desk?.book.stars(of: .bow) == 1)
  }

  @Test func aRoutineIsPlayedSentAndCountedAndATrickAskedForIsCounted() async {
    let room = Room()
    room.book.withLock {
      $0.skills[.jump] = TrickSkill(trick: .jump, stars: 3, teacher: "me")
    }
    let counted = Counted()
    let store = make(room, counted)
    store.send(.enabled)
    await store.settled()
    store.send(.opened)
    store.send(.ask(.jump, roll: 0.5))
    store.send(.buildRoutine)
    for _ in 0..<3 { store.send(.routine(.pick(.jump))) }
    store.send(
      .routine(.tryIt(rolls: [0, 0, 0], stars: [.jump: 3], at: Date(timeIntervalSince1970: 5))))
    await store.settled()
    store.send(.routine(.send))
    await store.settled()

    #expect(counted.moves == Array(repeating: .trick(.jump), count: 4))
    #expect(counted.events == [ClientEvent(.trickDone, detail: "jump"), ClientEvent(.routineSent)])
    #expect(store.state.desk?.book.mine?.steps.count == 3)
    #expect(store.state.desk?.screen == .routine(.sent(room.book.withLock { $0.mine! })))
  }

  @Test func theWireBookLeavesOutWhatThisBuildDoesNotKnow() throws {
    let json = #"""
      {"tricks":[{"trick":"spin","stars":2,"by":"user-a","at":1},{"trick":"moonwalk","stars":1,"by":"user-b","at":2}],
       "partner":{"steps":[{"trick":"spin","landed":true},{"trick":"moonwalk","landed":true},{"trick":"spin","landed":false}],"at":3},
       "mine":{"steps":[{"trick":"spin","landed":true},{"trick":"spin","landed":false},{"trick":"spin","landed":true}],"at":4000}}
      """#
    let book = try JSONDecoder().decode(SchoolResponse.self, from: Data(json.utf8)).book
    #expect(book.skills == [.spin: TrickSkill(trick: .spin, stars: 2, teacher: "user-a")])
    #expect(book.partner == nil)
    #expect(book.mine?.at == Date(timeIntervalSince1970: 4))
    #expect(book.mine?.landed == 2)
  }
}
