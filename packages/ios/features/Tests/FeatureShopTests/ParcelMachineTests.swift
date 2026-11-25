import Testing
import Transport
import Wire

@testable import FeatureShop

nonisolated private let parcel = Parcel(id: "parcel:t1", arrived: "2026-11-20T12:00:00.000Z")
nonisolated private let other = Parcel(id: "parcel:t2", arrived: "2026-12-20T12:00:00.000Z")
nonisolated private let armchair = ParcelOffer.item(RoomItemId("armchair"))
nonisolated private let plum = ParcelOffer.ink(InkId("ink-plum"))
nonisolated private let answer = OpenParcelResponse(
  plus: PlusResponse(state: .shared, parcels: [], opened: 1, bothPay: false, choicesLeft: 39),
  shop: ShopResponse(
    balance: 10, inks: [], items: [RoomItemId("armchair")], postage: [], wishlist: [],
    giftDay: nil, bonuses: []))

@Suite struct ParcelMachineTests {
  typealias Machine = ParcelMachine

  nonisolated static let all: [Machine.State] = [
    .closed, .choosing(parcel), .picked(parcel, armchair), .opening(parcel, armchair),
    .opened(armchair), .failed(parcel, armchair, .owned), .failed(parcel, armchair, .unavailable),
    .failed(parcel, armchair, .refused),
  ]
  nonisolated static let events: [Machine.Event] = [
    .parcelTapped(other), .offerPicked(plum), .confirmTapped, .closeTapped, .opened(answer),
    .openFailed(.owned), .openFailed(.gone), .openFailed(.unavailable),
  ]

  nonisolated static let accepted:
    [(Machine.State, Machine.Event, Machine.State, [Machine.Output])] = [
      (.closed, .parcelTapped(other), .choosing(other), []),
      (.opened(armchair), .parcelTapped(other), .choosing(other), []),
      (.choosing(parcel), .offerPicked(plum), .picked(parcel, plum), []),
      (.picked(parcel, armchair), .offerPicked(plum), .picked(parcel, plum), []),
      (.failed(parcel, armchair, .owned), .offerPicked(plum), .picked(parcel, plum), []),
      (.failed(parcel, armchair, .unavailable), .offerPicked(plum), .picked(parcel, plum), []),
      (.failed(parcel, armchair, .refused), .offerPicked(plum), .picked(parcel, plum), []),
      (
        .picked(parcel, armchair), .confirmTapped, .opening(parcel, armchair),
        [.open(parcel: parcel.id, offer: armchair)]
      ),
      (
        .failed(parcel, armchair, .unavailable), .confirmTapped, .opening(parcel, armchair),
        [.open(parcel: parcel.id, offer: armchair)]
      ),
      (.opening(parcel, armchair), .opened(answer), .opened(armchair), [.apply(answer)]),
      (.opening(parcel, armchair), .openFailed(.owned), .failed(parcel, armchair, .owned), []),
      (
        .opening(parcel, armchair), .openFailed(.unavailable),
        .failed(parcel, armchair, .unavailable), []
      ),
      (.opening(parcel, armchair), .openFailed(.gone), .closed, [.reread]),
      (.choosing(parcel), .closeTapped, .closed, []),
      (.picked(parcel, armchair), .closeTapped, .closed, []),
      (.opened(armchair), .closeTapped, .closed, []),
      (.failed(parcel, armchair, .owned), .closeTapped, .closed, []),
      (.failed(parcel, armchair, .unavailable), .closeTapped, .closed, []),
      (.failed(parcel, armchair, .refused), .closeTapped, .closed, []),
    ]

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

  @Test(arguments: [
    (TransportError.api(.alreadyOwned(itemId: "armchair")), ParcelError.owned),
    (.api(.parcelOpened), .gone), (.api(.notFound), .gone), (.api(.invalidRequest), .refused),
    (.network("offline"), .unavailable),
  ])
  func errorsMapOnce(_ error: TransportError, _ expected: ParcelError) {
    #expect(ParcelError(error) == expected)
  }
}
