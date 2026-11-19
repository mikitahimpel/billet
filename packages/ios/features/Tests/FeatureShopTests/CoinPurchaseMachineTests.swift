import Payments
import Testing

@testable import FeatureShop

nonisolated private let pack = StampPack(
  id: "com.ourio.app.coins.550", stamps: 550, displayName: "550 coins", description: "",
  displayPrice: "$4.99")

@Suite struct CoinPurchaseMachineTests {
  typealias Machine = CoinPurchaseMachine

  @Test(arguments: [
    Machine.State.idle, .waiting, .delivering, .bought(coins: 100), .failed(.unavailable),
  ])
  func aTapBuysThePack(from state: Machine.State) {
    #expect(Machine.transition(state, .buyTapped(pack)) == (.buying(pack.id), [.purchase(pack)]))
  }

  @Test func aPurchaseTheServerCreditedReadsTheWallet() {
    #expect(
      Machine.transition(.buying(pack.id), .purchased(coins: 550)) == (
        .bought(coins: 550), [.readWallet]
      ))
  }

  @Test func whatTheStoreAnsweredIsWhatTheSheetSays() {
    #expect(Machine.transition(.buying(pack.id), .cancelled) == (.idle, []))
    #expect(Machine.transition(.buying(pack.id), .pending) == (.waiting, []))
    #expect(Machine.transition(.buying(pack.id), .awaitingCredit) == (.delivering, []))
    #expect(
      Machine.transition(.buying(pack.id), .failed(.notAllowed)) == (.failed(.notAllowed), []))
  }

  @Test(arguments: [Machine.State.waiting, .delivering])
  func aLaterCreditFinishesTheWait(from state: Machine.State) {
    #expect(
      Machine.transition(state, .credited(coins: 550)) == (.bought(coins: 550), [.readWallet]))
  }

  @Test(arguments: [
    (Machine.State.idle, Machine.Event.credited(coins: 100)),
    (.buying(pack.id), .credited(coins: 100)),
    (.bought(coins: 550), .credited(coins: 100)),
    (.failed(.unavailable), .credited(coins: 100)),
    (.idle, .ledgerChanged),
    (.buying(pack.id), .ledgerChanged),
    (.waiting, .ledgerChanged),
    (.delivering, .ledgerChanged),
    (.bought(coins: 550), .ledgerChanged),
    (.failed(.unavailable), .ledgerChanged),
  ])
  func coinsFromElsewhereReadTheWalletOnly(state: Machine.State, event: Machine.Event) {
    #expect(Machine.transition(state, event) == (state, [.readWallet]))
  }

  @Test(
    arguments: [Machine.State.idle, .waiting, .delivering, .bought(coins: 100), .failed(.rejected)]
      .flatMap { state in
        [
          Machine.Event.purchased(coins: 100), .cancelled, .pending, .awaitingCredit,
          .failed(.unavailable),
        ].map { (state, $0) }
      } + [(.buying(pack.id), .buyTapped(pack))])
  func rejectedEventsChangeNothing(state: Machine.State, event: Machine.Event) {
    let (next, outputs) = Machine.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }
}

@Suite struct CoinShelfMachineTests {
  typealias Machine = CoinShelfMachine

  @Test(arguments: [Machine.State.loading, .unavailable])
  func openingLoadsTheProducts(from state: Machine.State) {
    #expect(Machine.transition(state, .opened) == (.loading, [.loadProducts]))
  }

  @Test func theStoreAnswersTheShelf() {
    #expect(Machine.transition(.loading, .loaded([pack])) == (.ready([pack]), []))
    #expect(Machine.transition(.loading, .loaded([])) == (.unavailable, []))
    #expect(Machine.transition(.loading, .loadFailed) == (.unavailable, []))
  }

  @Test(arguments: [
    (Machine.State.ready([pack]), Machine.Event.opened),
    (.ready([pack]), .loaded([])),
    (.ready([pack]), .loadFailed),
    (.unavailable, .loaded([pack])),
    (.unavailable, .loadFailed),
  ])
  func rejectedEventsChangeNothing(state: Machine.State, event: Machine.Event) {
    let (next, outputs) = Machine.transition(state, event)
    #expect(next == state)
    #expect(outputs.isEmpty)
  }
}
