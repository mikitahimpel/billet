import BilletKit
import Payments
import Transport
import Wire

/// Why the pair's Plus couldn't be read.
public enum PlusError: Error, Equatable, Sendable {
  /// The server doesn't offer Plus to this account: the flag is off, or a declared 13-17.
  case notOffered
  /// The network or the server; trying again is safe.
  case unavailable

  public init(_ error: TransportError) {
    switch error {
    case .api(.notFound): self = .notOffered
    case .api(.unauthorized), .api(.invalidRequest), .api(.unavailable), .api(.invalidInvite),
      .api(.alreadyPaired), .api(.appleIdInUse), .api(.invalidPurchase), .api(.inkNotOwned),
      .api(.postageNotOwned), .api(.notEnoughCoins), .api(.alreadyOwned),
      .api(.subscriptionTaken), .api(.parcelOpened), .api(.collectionIncomplete),
      .api(.giftTaken), .api(.bonusTaken), .api(.catNotAdopted), .api(.streakNotRestorable),
      .api(.priceChanged), .api(.layoutRefused), .network, .status, .maintenance, .encoding,
      .decoding:
      self = .unavailable
    }
  }
}

/// The pair's Ourio Plus and the one sheet that sells it. Nothing here opens the sheet: only a tap
/// on the Shop or Settings row does, and while a buy is on its way every other tap is refused.
public nonisolated enum PlusMachine: Machine {
  /// A pair without Plus, as the sheet offers it.
  public struct Shelf: Equatable, Sendable {
    public var plus: PlusResponse
    /// Monthly first; empty when the store didn't open.
    public var offers: [PlusOffer]
    public var plan: PlusCatalog.Plan = .monthly
    /// What the last buy or restore ran into, shown under the button until the next tap.
    public var failure: PaymentsError?

    public var selected: PlusOffer? { offers.first { $0.plan == plan } }
  }

  public enum State: Equatable, Sendable {
    /// Not read yet.
    case idle
    /// `again`: something changed while the read was out, so it is read once more.
    case loading(again: Bool)
    /// Every entry is hidden.
    case notOffered
    case unavailable
    case offered(Shelf)
    case buying(Shelf)
    /// Ask to Buy: a parent decides; it arrives as `changed`.
    case waiting(Shelf)
    /// Paid, and the server hasn't heard yet; the store sends it again.
    case delivering(Shelf)
    case restoring(Shelf)
    /// The caller pays.
    case mine(PlusResponse)
    /// The partner pays.
    case partners(PlusResponse)

    public static let initial = State.idle
  }

  public enum Event: Equatable, Sendable {
    case loaded(PlusResponse, offers: [PlusOffer])
    case loadFailed(PlusError)
    case retryTapped
    case planPicked(PlusCatalog.Plan)
    case buyTapped
    case subscribed
    case cancelled
    case pending
    case awaitingServer
    case buyFailed(PaymentsError)
    case restoreTapped
    case restored
    case restoreFailed(PaymentsError)
    /// A renewal, an approved Ask to Buy, a refund, a partner's subscription: read it again.
    case changed
    /// A parcel was opened; the server's answer, read in the same request.
    case updated(PlusResponse)
  }

  public enum Output: Equatable, Sendable {
    case load
    case subscribe(PlusOffer)
    case restore
  }

  /// What the server's answer shows: an offer, or the pair's Plus by who pays.
  static func settled(_ plus: PlusResponse, offers: [PlusOffer], keeping plan: PlusCatalog.Plan)
    -> State
  {
    switch plus.state {
    case .none, .ended: .offered(Shelf(plus: plus, offers: offers, plan: plan))
    case .active, .ending, .grace: .mine(plus)
    case .shared: .partners(plus)
    }
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    let unchanged: (State, [Output]) = (state, [])
    let reload: (State, [Output]) = (.loading(again: false), [.load])
    switch state {
    case .idle:
      switch event {
      case .changed: return reload
      // Rejected: nothing is out and nothing is shown.
      case .loaded, .loadFailed, .retryTapped, .planPicked, .buyTapped, .subscribed, .cancelled,
        .pending, .awaitingServer, .buyFailed, .restoreTapped, .restored, .restoreFailed, .updated:
        return unchanged
      }

    case .loading(let again):
      switch event {
      case .loaded(let plus, let offers):
        return again ? reload : (settled(plus, offers: offers, keeping: .monthly), [])
      case .loadFailed(let error):
        if again { return reload }
        switch error {
        case .notOffered: return (.notOffered, [])
        case .unavailable: return (.unavailable, [])
        }
      case .changed: return (.loading(again: true), [])
      // Rejected: no control is shown while reading.
      case .retryTapped, .planPicked, .buyTapped, .subscribed, .cancelled, .pending,
        .awaitingServer, .buyFailed, .restoreTapped, .restored, .restoreFailed, .updated:
        return unchanged
      }

    case .notOffered:
      switch event {
      case .changed: return reload
      case .loaded, .loadFailed, .retryTapped, .planPicked, .buyTapped, .subscribed, .cancelled,
        .pending, .awaitingServer, .buyFailed, .restoreTapped, .restored, .restoreFailed, .updated:
        return unchanged
      }

    case .unavailable:
      switch event {
      case .retryTapped, .changed: return reload
      case .loaded, .loadFailed, .planPicked, .buyTapped, .subscribed, .cancelled, .pending,
        .awaitingServer, .buyFailed, .restoreTapped, .restored, .restoreFailed, .updated:
        return unchanged
      }

    case .offered(var shelf):
      switch event {
      case .planPicked(let plan):
        shelf.plan = plan
        shelf.failure = nil
        return (.offered(shelf), [])
      case .buyTapped:
        guard let offer = shelf.selected else { return unchanged }
        shelf.failure = nil
        return (.buying(shelf), [.subscribe(offer)])
      case .restoreTapped:
        shelf.failure = nil
        return (.restoring(shelf), [.restore])
      case .changed: return reload
      case .updated(let plus):
        return (settled(plus, offers: shelf.offers, keeping: shelf.plan), [])
      // Rejected: no request is out.
      case .loaded, .loadFailed, .retryTapped, .subscribed, .cancelled, .pending, .awaitingServer,
        .buyFailed, .restored, .restoreFailed:
        return unchanged
      }

    case .buying(var shelf):
      switch event {
      case .subscribed: return reload
      case .cancelled: return (.offered(shelf), [])
      case .pending: return (.waiting(shelf), [])
      case .awaitingServer: return (.delivering(shelf), [])
      case .buyFailed(let error):
        shelf.failure = error
        return (.offered(shelf), [])
      // Rejected: one buy at a time; what changed is read once it answers.
      case .loaded, .loadFailed, .retryTapped, .planPicked, .buyTapped, .restoreTapped, .restored,
        .restoreFailed, .changed, .updated:
        return unchanged
      }

    case .restoring(var shelf):
      switch event {
      case .restored: return reload
      case .restoreFailed(let error):
        shelf.failure = error
        return (.offered(shelf), [])
      case .loaded, .loadFailed, .retryTapped, .planPicked, .buyTapped, .subscribed, .cancelled,
        .pending, .awaitingServer, .buyFailed, .restoreTapped, .changed, .updated:
        return unchanged
      }

    case .waiting, .delivering:
      switch event {
      case .changed: return reload
      // Rejected: the store answers later, through `changed`.
      case .loaded, .loadFailed, .retryTapped, .planPicked, .buyTapped, .subscribed, .cancelled,
        .pending, .awaitingServer, .buyFailed, .restoreTapped, .restored, .restoreFailed, .updated:
        return unchanged
      }

    case .mine, .partners:
      switch event {
      case .changed: return reload
      case .updated(let plus): return (settled(plus, offers: [], keeping: .monthly), [])
      // Rejected: a pair with Plus is offered nothing.
      case .loaded, .loadFailed, .retryTapped, .planPicked, .buyTapped, .subscribed, .cancelled,
        .pending, .awaitingServer, .buyFailed, .restoreTapped, .restored, .restoreFailed:
        return unchanged
      }
    }
  }
}
