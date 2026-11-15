import ShopInterface
import Testing
import Wire

@testable import FeatureShop

nonisolated private let moon = NotePostage(NoteStamp.moon)

@Suite struct PostageUnlockMachineTests {
  typealias Machine = PostageUnlockMachine

  @Test func anOwnedOneIsChosenAtOnce() {
    #expect(
      Machine.transition(.idle, .tapped(moon, owned: true)) == (.idle, [.select(moon)]))
  }

  @Test func aLockedOneAsksFirst() {
    #expect(
      Machine.transition(.idle, .tapped(moon, owned: false)) == (.confirming(moon), []))
  }

  @Test func buyAsksTheShop() {
    #expect(
      Machine.transition(.confirming(moon), .buyTapped) == (
        .buying(moon), [.buy(moon)]
      ))
  }

  @Test func cancelLeavesTheNoteAsItWas() {
    #expect(Machine.transition(.confirming(moon), .cancelled) == (.idle, []))
  }

  @Test func aPlacedBuyChoosesIt() {
    #expect(Machine.transition(.buying(moon), .bought) == (.idle, [.select(moon)]))
  }

  @Test func shortOfCoinsOpensCoins() {
    #expect(Machine.transition(.buying(moon), .coinsShort) == (.idle, [.openCoins]))
  }

  @Test func aRefusedBuyChoosesNothing() {
    #expect(Machine.transition(.buying(moon), .refused) == (.idle, []))
  }

  @Test(arguments: [
    (Machine.State.idle, Machine.Event.buyTapped),
    (.idle, .cancelled),
    (.idle, .bought),
    (.idle, .coinsShort),
    (.idle, .refused),
    (.confirming(moon), .tapped(NotePostage(NoteSeal.rose), owned: true)),
    (.confirming(moon), .bought),
    (.confirming(moon), .coinsShort),
    (.confirming(moon), .refused),
    (.buying(moon), .tapped(moon, owned: false)),
    (.buying(moon), .buyTapped),
    (.buying(moon), .cancelled),
  ])
  func rejectedEventsChangeNothing(state: Machine.State, event: Machine.Event) {
    let (next, outputs) = Machine.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }
}
