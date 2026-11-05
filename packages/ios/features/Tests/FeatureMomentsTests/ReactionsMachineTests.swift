import Foundation
import Testing
import Transport
import Wire

@testable import FeatureMoments

@Suite struct ReactionsMachineTests {
  typealias M = ReactionsMachine

  static let me = UserId("user-me")
  static let partner = UserId("user-partner")
  static let photo = NoteId("note-1")

  static func change(_ rev: Int, by: UserId = partner, _ reaction: PhotoReaction?) -> NoteReaction {
    NoteReaction(rev: rev, note: photo, by: by, at: rev * 1000, reaction: reaction)
  }

  static let start = M.State(viewer: me, saved: .init())

  @Test func aTapShowsAtOnceAndGoesToTheServer() {
    let (state, outputs) = M.transition(Self.start, .tapped(note: Self.photo, .heart))
    #expect(state.mine("note-1") == .heart)
    #expect(outputs == [.send(ReactRequest(note: Self.photo, reaction: .heart))])
  }

  @Test func tappingTheReactionShownTakesItBack() {
    var state = Self.start
    state.saved.mine["note-1"] = .fire
    let (next, outputs) = M.transition(state, .tapped(note: Self.photo, .fire))
    #expect(next.mine("note-1") == nil)
    #expect(outputs == [.send(ReactRequest(note: Self.photo, reaction: nil))])
  }

  @Test func aTapWhileOneIsOutWaitsAndTheAnswerSendsTheLatestWish() {
    var (state, _) = M.transition(Self.start, .tapped(note: Self.photo, .heart))
    var outputs: [M.Output]
    (state, outputs) = M.transition(state, .tapped(note: Self.photo, .laugh))
    #expect(outputs.isEmpty)
    #expect(state.mine("note-1") == .laugh)
    (state, outputs) = M.transition(state, .confirmed(note: Self.photo, .heart))
    #expect(outputs.contains(.send(ReactRequest(note: Self.photo, reaction: .laugh))))
    (state, outputs) = M.transition(state, .confirmed(note: Self.photo, .laugh))
    #expect(state.wanted.isEmpty && state.sending.isEmpty)
    #expect(state.saved.mine == ["note-1": .laugh])
  }

  @Test func aFailurePutsBackWhatTheServerHas() {
    var state = Self.start
    state.saved.mine["note-1"] = .wow
    (state, _) = M.transition(state, .tapped(note: Self.photo, .sad))
    (state, _) = M.transition(state, .failed(note: Self.photo))
    #expect(state.mine("note-1") == .wow)
    #expect(state.sending.isEmpty)
  }

  @Test func changesApplyOnceInRevOrderToTheRightSide() {
    var (state, outputs) = M.transition(Self.start, .received(Self.change(1, .heart)))
    #expect(state.saved.theirs == ["note-1": .heart])
    #expect(outputs == [.save(state.saved)])
    (state, outputs) = M.transition(state, .received(Self.change(1, .fire)))
    #expect(outputs.isEmpty)
    (state, _) = M.transition(state, .received(Self.change(2, by: Self.me, .wow)))
    (state, _) = M.transition(state, .received(Self.change(3, nil)))
    #expect(state.saved == .init(lastRev: 3, mine: ["note-1": .wow], theirs: [:]))
  }

  @Test func aRefreshPagesUntilAShortPage() {
    var (state, outputs) = M.transition(Self.start, .refreshed)
    #expect(outputs == [.load(after: 0)])
    let full = (1...M.pageSize).map { Self.change($0, .heart) }
    (state, outputs) = M.transition(state, .pageLoaded(full))
    #expect(outputs.last == .load(after: M.pageSize))
    (state, outputs) = M.transition(state, .pageLoaded([]))
    #expect(outputs.isEmpty)
    #expect(!state.loading)
  }

  @Test func takingBackNothingCountsAsDone() async {
    var api = APIClient.offline
    api.react = { (_) async throws(TransportError) in throw .api(.notFound) }
    let event = await M.run(
      .send(ReactRequest(note: Self.photo, reaction: nil)), api: api, save: { _ in })
    #expect(event == .confirmed(note: Self.photo, nil))
  }
}
