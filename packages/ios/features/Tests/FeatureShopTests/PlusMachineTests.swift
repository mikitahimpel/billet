import Payments
import Testing
import Transport
import Wire

@testable import FeatureShop

nonisolated private let monthly = PlusOffer(
  id: "com.ourio.app.plus.monthly", plan: .monthly, displayName: "Ourio Plus",
  displayPrice: "$3.99")
nonisolated private let yearly = PlusOffer(
  id: "com.ourio.app.plus.yearly", plan: .yearly, displayName: "Ourio Plus, yearly",
  displayPrice: "$29.99")
nonisolated private let parcel = Parcel(id: "parcel:t1", arrived: "2026-11-20T12:00:00.000Z")

nonisolated private func plus(_ state: PlusState, parcels: [Parcel] = []) -> PlusResponse {
  PlusResponse(state: state, parcels: parcels, opened: 0, bothPay: false, choicesLeft: 40)
}

nonisolated private let none = plus(.none)
nonisolated private let mine = plus(.active(plan: .monthly, renewsOn: "2026-12-20T12:00:00.000Z"))
nonisolated private let shared = plus(.shared, parcels: [parcel])
nonisolated private let shelf = PlusMachine.Shelf(plus: none, offers: [monthly, yearly])

@Suite struct PlusMachineTests {
  typealias Machine = PlusMachine

  nonisolated static let all: [Machine.State] = [
    .idle, .loading(again: false), .loading(again: true), .notOffered, .unavailable,
    .offered(shelf), .buying(shelf), .waiting(shelf), .delivering(shelf), .restoring(shelf),
    .mine(mine), .partners(shared),
  ]
  nonisolated static let events: [Machine.Event] = [
    .loaded(none, offers: [monthly]), .loadFailed(.notOffered), .loadFailed(.unavailable),
    .retryTapped, .planPicked(.yearly), .buyTapped, .subscribed, .cancelled, .pending,
    .awaitingServer, .buyFailed(.notAllowed), .restoreTapped, .restored,
    .restoreFailed(.subscriptionTaken), .changed, .updated(mine),
  ]

  /// Every pairing the table takes; everything else must leave the state as it is.
  nonisolated static let accepted:
    [(Machine.State, Machine.Event, Machine.State, [Machine.Output])] = {
      let reading = Machine.State.loading(again: false)
      var picked = shelf
      picked.plan = .yearly
      var failed = shelf
      failed.failure = .notAllowed
      var taken = shelf
      taken.failure = .subscriptionTaken
      return [
        (.idle, .changed, reading, [.load]),
        (
          reading, .loaded(none, offers: [monthly]), .offered(.init(plus: none, offers: [monthly])),
          []
        ),
        (reading, .loaded(mine, offers: []), .mine(mine), []),
        (reading, .loaded(shared, offers: []), .partners(shared), []),
        (reading, .loadFailed(.notOffered), .notOffered, []),
        (reading, .loadFailed(.unavailable), .unavailable, []),
        (reading, .changed, .loading(again: true), []),
        (.loading(again: true), .loaded(none, offers: [monthly]), reading, [.load]),
        (.loading(again: true), .loadFailed(.notOffered), reading, [.load]),
        (.loading(again: true), .loadFailed(.unavailable), reading, [.load]),
        (.loading(again: true), .changed, .loading(again: true), []),
        (.notOffered, .changed, reading, [.load]),
        (.unavailable, .retryTapped, reading, [.load]),
        (.unavailable, .changed, reading, [.load]),
        (.offered(shelf), .planPicked(.yearly), .offered(picked), []),
        (.offered(shelf), .buyTapped, .buying(shelf), [.subscribe(monthly)]),
        (.offered(picked), .buyTapped, .buying(picked), [.subscribe(yearly)]),
        (.offered(shelf), .restoreTapped, .restoring(shelf), [.restore]),
        (.offered(shelf), .changed, reading, [.load]),
        (.offered(shelf), .updated(mine), .mine(mine), []),
        (.buying(shelf), .subscribed, reading, [.load]),
        (.buying(shelf), .cancelled, .offered(shelf), []),
        (.buying(shelf), .pending, .waiting(shelf), []),
        (.buying(shelf), .awaitingServer, .delivering(shelf), []),
        (.buying(shelf), .buyFailed(.notAllowed), .offered(failed), []),
        (.restoring(shelf), .restored, reading, [.load]),
        (.restoring(shelf), .restoreFailed(.subscriptionTaken), .offered(taken), []),
        (.waiting(shelf), .changed, reading, [.load]),
        (.delivering(shelf), .changed, reading, [.load]),
        (.mine(mine), .changed, reading, [.load]),
        (.mine(mine), .updated(mine), .mine(mine), []),
        (.partners(shared), .changed, reading, [.load]),
        (.partners(shared), .updated(mine), .mine(mine), []),
      ]
    }()

  @Test(arguments: accepted.indices)
  func theTableTakes(_ index: Int) {
    let (state, event, next, outputs) = Self.accepted[index]
    #expect(Machine.transition(state, event) == (next, outputs))
  }

  @Test(arguments: all)
  func everyOtherPairingIsRefused(_ state: Machine.State) {
    for event in Self.events
    where !Self.accepted.contains(where: { $0.0 == state && $0.1 == event }) {
      #expect(Machine.transition(state, event) == (state, []), "\(state) \(event)")
    }
  }

  @Test func aPickedFailureClearsOnTheNextTap() {
    var failed = shelf
    failed.failure = .unavailable
    let (next, _) = Machine.transition(.offered(failed), .planPicked(.monthly))
    #expect(next == .offered(shelf))
  }

  @Test func withoutAnOfferTheButtonDoesNothing() {
    let empty = Machine.Shelf(plus: none, offers: [])
    #expect(Machine.transition(.offered(empty), .buyTapped) == (.offered(empty), []))
  }

  @Test func anEndedPlusIsOfferedAgainWithItsParcels() {
    let ended = plus(.ended, parcels: [parcel])
    let (next, _) = Machine.transition(.loading(again: false), .loaded(ended, offers: [monthly]))
    #expect(next == .offered(.init(plus: ended, offers: [monthly])))
  }

  @Test(arguments: [
    (TransportError.api(.notFound), PlusError.notOffered),
    (.api(.unavailable), .unavailable), (.network("offline"), .unavailable),
    (.status(500), .unavailable),
  ])
  func errorsMapOnce(_ error: TransportError, _ expected: PlusError) {
    #expect(PlusError(error) == expected)
  }
}
