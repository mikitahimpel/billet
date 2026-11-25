import BilletKit
import Foundation
import Observation
import Payments
import Transport
import Wire

/// The Plus routes on the server.
public nonisolated struct PlusClient: Sendable {
  public var read: @Sendable () async throws(TransportError) -> PlusResponse
  public var open: @Sendable (OpenParcelRequest) async throws(TransportError) -> OpenParcelResponse

  public init(
    read: @escaping @Sendable () async throws(TransportError) -> PlusResponse,
    open: @escaping @Sendable (OpenParcelRequest) async throws(TransportError) -> OpenParcelResponse
  ) {
    self.read = read
    self.open = open
  }

  public static func live(_ client: PurchasesClient) -> PlusClient {
    PlusClient(read: client.plus, open: client.openParcel)
  }
}

/// What the Shop and Settings rows show.
public enum PlusEntry: Equatable, Sendable {
  /// Not offered to this account, or not read yet: no row at all.
  case hidden
  case offer
  case parcels(Int)
  case has
}

/// The pair's Ourio Plus: the sheet that sells it and the parcels it brings. Only the server says
/// what the pair has; a parcel's piece reaches the Shop through `applied`.
@MainActor
@Observable
public final class PlusModel {
  @ObservationIgnored private let payments: (any Payments)?
  private let plusStore: Store<PlusMachine>
  private let parcelStore: Store<ParcelMachine>

  public var state: PlusMachine.State { plusStore.state }
  public var parcel: ParcelMachine.State { parcelStore.state }

  /// `applied` takes the server's shop after a parcel opened.
  public init(
    payments: (any Payments)?, client: PlusClient,
    applied: @escaping @MainActor @Sendable (ShopResponse) -> Void
  ) {
    self.payments = payments
    let plus = Store<PlusMachine>(initial: .initial) { output in
      switch output {
      case .load:
        let plus: PlusResponse
        do throws(TransportError) {
          plus = try await client.read()
        } catch {
          return .loadFailed(PlusError(error))
        }
        // A build that can't sell shows the pair's Plus, never an offer it can't keep.
        guard let payments else {
          return switch plus.state {
          case .none, .ended: .loadFailed(.notOffered)
          case .active, .ending, .grace, .shared: .loaded(plus, offers: [])
          }
        }
        let offers = (try? await payments.plusOffers()) ?? []
        return .loaded(plus, offers: offers)
      case .subscribe(let offer):
        guard let payments else { return .buyFailed(.unavailable) }
        do throws(PaymentsError) {
          return switch try await payments.subscribe(offer) {
          case .subscribed: .subscribed
          case .cancelled: .cancelled
          case .pending: .pending
          case .awaitingServer: .awaitingServer
          }
        } catch {
          return .buyFailed(error)
        }
      case .restore:
        guard let payments else { return .restoreFailed(.unavailable) }
        do throws(PaymentsError) {
          try await payments.restorePlus()
          return .restored
        } catch {
          return .restoreFailed(error)
        }
      }
    }
    plusStore = plus
    parcelStore = Store(initial: .closed) { output in
      switch output {
      case .open(let parcel, let offer):
        do throws(TransportError) {
          return .opened(try await client.open(OpenParcelRequest(parcel: parcel, offer: offer)))
        } catch {
          return .openFailed(ParcelError(error))
        }
      case .apply(let answer):
        await applied(answer.shop)
        await plus.send(.updated(answer.plus))
        return nil
      case .reread:
        await plus.send(.changed)
        return nil
      }
    }
  }

  public var entry: PlusEntry {
    switch state {
    case .idle, .loading, .notOffered, .unavailable: .hidden
    case .offered(let shelf), .buying(let shelf), .waiting(let shelf), .delivering(let shelf),
      .restoring(let shelf):
      shelf.plus.parcels.isEmpty ? .offer : .parcels(shelf.plus.parcels.count)
    case .mine(let plus), .partners(let plus):
      plus.parcels.isEmpty ? .has : .parcels(plus.parcels.count)
    }
  }

  public func send(_ event: PlusMachine.Event) { plusStore.send(event) }
  public func send(_ event: ParcelMachine.Event) { parcelStore.send(event) }

  /// Reads the pair's Plus, then follows renewals and refunds for as long as the caller's task runs.
  public func follow() async {
    let updates = payments?.updates()
    if case .idle = state { plusStore.send(.changed) }
    guard let updates else { return await plusStore.settled() }
    for await update in updates {
      switch update {
      case .plusChanged: plusStore.send(.changed)
      case .credited, .ledgerChanged: break
      }
    }
  }

  /// Read again, such as when the pair changed.
  public func reload() { plusStore.send(.changed) }

  public func settled() async {
    await plusStore.settled()
    await parcelStore.settled()
  }
}
