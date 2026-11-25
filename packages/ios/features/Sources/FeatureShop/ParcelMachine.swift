import BilletKit
import Transport
import Wire

public enum ParcelError: Error, Equatable, Sendable {
  /// The pair has the piece already.
  case owned
  /// The partner opened it first, as something else, or it went with a refund.
  case gone
  /// Not a piece a parcel may hold.
  case refused
  /// The network or the server; nothing was opened, trying again is safe.
  case unavailable

  public init(_ error: TransportError) {
    switch error {
    case .api(.alreadyOwned): self = .owned
    case .api(.parcelOpened), .api(.notFound): self = .gone
    case .api(.invalidRequest): self = .refused
    case .api(.unauthorized), .api(.unavailable), .api(.invalidInvite), .api(.alreadyPaired),
      .api(.appleIdInUse), .api(.invalidPurchase), .api(.inkNotOwned), .api(.postageNotOwned),
      .api(.notEnoughCoins), .api(.subscriptionTaken), .api(.collectionIncomplete),
      .api(.giftTaken), .api(.bonusTaken), .api(.catNotAdopted), .api(.streakNotRestorable),
      .api(.priceChanged), .api(.layoutRefused), .network, .status, .maintenance, .encoding,
      .decoding:
      self = .unavailable
    }
  }
}

/// Choosing what one parcel becomes. Closing it before the choice is sent leaves the parcel
/// waiting; once sent, it stays open until the server answers.
public nonisolated enum ParcelMachine: Machine {
  public enum State: Equatable, Sendable {
    case closed
    case choosing(Parcel)
    case picked(Parcel, ParcelOffer)
    case opening(Parcel, ParcelOffer)
    case opened(ParcelOffer)
    case failed(Parcel, ParcelOffer, ParcelError)
  }

  public enum Event: Equatable, Sendable {
    case parcelTapped(Parcel)
    case offerPicked(ParcelOffer)
    case confirmTapped
    case closeTapped
    case opened(OpenParcelResponse)
    case openFailed(ParcelError)
  }

  public enum Output: Equatable, Sendable {
    case open(parcel: String, offer: ParcelOffer)
    /// The server's shop and Plus after the parcel opened.
    case apply(OpenParcelResponse)
    /// The parcel is no longer there: read the pair's Plus again.
    case reread
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.closed, .parcelTapped(let parcel)), (.opened, .parcelTapped(let parcel)):
      return (.choosing(parcel), [])
    case (.choosing(let parcel), .offerPicked(let offer)),
      (.picked(let parcel, _), .offerPicked(let offer)),
      (.failed(let parcel, _, _), .offerPicked(let offer)):
      return (.picked(parcel, offer), [])
    case (.picked(let parcel, let offer), .confirmTapped),
      (.failed(let parcel, let offer, .unavailable), .confirmTapped):
      return (.opening(parcel, offer), [.open(parcel: parcel.id, offer: offer)])
    case (.opening(_, let offer), .opened(let answer)):
      return (.opened(offer), [.apply(answer)])
    case (.opening(let parcel, let offer), .openFailed(let error)):
      switch error {
      case .gone: return (.closed, [.reread])
      case .owned, .refused, .unavailable: return (.failed(parcel, offer, error), [])
      }
    case (.choosing, .closeTapped), (.picked, .closeTapped), (.opened, .closeTapped),
      (.failed, .closeTapped):
      return (.closed, [])

    // Rejected: one parcel at a time, nothing to confirm, or no request out.
    case (.closed, .offerPicked), (.closed, .confirmTapped), (.closed, .closeTapped),
      (.closed, .opened), (.closed, .openFailed),
      (.choosing, .parcelTapped), (.choosing, .confirmTapped), (.choosing, .opened),
      (.choosing, .openFailed),
      (.picked, .parcelTapped), (.picked, .opened), (.picked, .openFailed),
      (.opening, .parcelTapped), (.opening, .offerPicked), (.opening, .confirmTapped),
      (.opening, .closeTapped),
      (.opened, .offerPicked), (.opened, .confirmTapped), (.opened, .opened),
      (.opened, .openFailed),
      (.failed, .parcelTapped), (.failed(_, _, .owned), .confirmTapped),
      (.failed(_, _, .refused), .confirmTapped), (.failed(_, _, .gone), .confirmTapped),
      (.failed, .opened), (.failed, .openFailed):
      return (state, [])
    }
  }
}
