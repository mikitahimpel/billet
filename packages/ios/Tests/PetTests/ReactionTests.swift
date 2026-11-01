import DesignSystem
import Foundation
import Pet
import Testing

@Suite("Reactions")
struct ReactionTests {
  private let note = UUID()
  private let other = UUID()

  @Test func nameTheRoomsKinds() {
    #expect(Reaction.allCases.map(\.rawValue) == ["heart", "stamp"])
    #expect(Reaction(rawValue: "coin") == nil)
  }

  @Test func aReceivedTableReportsOnlyWhatIsNewOrChanged() {
    var play = PairPlay(device: "me")
    #expect(play.reactionsReceived([note: .heart]) == [note: .heart])
    #expect(play.reactionsReceived([note: .heart]).isEmpty)
    #expect(play.reactionsReceived([note: .stamp, other: .heart]) == [note: .stamp, other: .heart])
    #expect(play.reactions == [note: .stamp, other: .heart])
  }

  @Test func aReactionGivenHereIsNotReportedWhenTheRoomEchoesIt() {
    var play = PairPlay(device: "me")
    play.reactionGiven(to: note, .stamp)
    #expect(play.reactions[note] == .stamp)
    #expect(play.reactionsReceived([note: .stamp]).isEmpty)
  }
}
