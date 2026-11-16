import BilletKit
import Transport
import Wire

/// Why a pairing step did not work, as the screen words it.
public enum PairingFailure: Equatable, Sendable {
  /// The code is unknown, expired, already used or the user's own. The backend does not say which.
  case invalidCode
  /// This account already has a partner and has to unpair first.
  case alreadyPaired
  /// The session is no longer accepted.
  case signedOut
  /// The backend or the network is down. Trying again is safe.
  case unavailable

  public init(_ error: TransportError) {
    switch error {
    case .api(.invalidInvite): self = .invalidCode
    case .api(.alreadyPaired): self = .alreadyPaired
    case .api(.unauthorized): self = .signedOut
    case .api(.invalidRequest): self = .invalidCode
    case .api(.unavailable), .api(.notFound), .api(.appleIdInUse), .api(.invalidPurchase),
      .api(.inkNotOwned), .api(.postageNotOwned), .api(.notEnoughCoins), .api(.alreadyOwned),
      .api(.collectionIncomplete), .api(.giftTaken), .api(.bonusTaken), .api(.catNotAdopted),
      .api(.streakNotRestorable), .api(.priceChanged), .api(.layoutRefused),
      .network,
      .status, .maintenance,
      .encoding,
      .decoding:
      self = .unavailable
    }
  }
}

/// An invite this phone showed, until it is claimed, cancelled or runs out. `expiresAt` is epoch milliseconds.
public struct KeptInvite: Codable, Equatable, Sendable {
  public let code: String
  public let expiresAt: Int

  public init(code: String, expiresAt: Int) {
    self.code = code
    self.expiresAt = expiresAt
  }
}

/// Where the shown invite is kept across launches; `none` keeps nothing.
public struct InviteKeeper: Sendable {
  public var load: @MainActor @Sendable () -> KeptInvite?
  public var keep: @MainActor @Sendable (KeptInvite?) -> Void

  public init(
    load: @escaping @MainActor @Sendable () -> KeptInvite?,
    keep: @escaping @MainActor @Sendable (KeptInvite?) -> Void
  ) {
    self.load = load
    self.keep = keep
  }

  public static let none = InviteKeeper(load: { nil }, keep: { _ in })
}

/// Which side of the invite this phone was on.
public enum PairRole: Equatable, Sendable {
  /// Showed the code; the pair's cat is this phone's to adopt.
  case inviter
  /// Entered the code. `pairID` is nil when the server answered that the account already has a partner, as
  /// for a retry whose first claim went through.
  case joiner(pairID: String?)
}

/// Create an invite and wait for the partner, or enter the partner's code.
///
/// `request` counts the calls made, so a result for an earlier call changes nothing.
public enum PairingMachine: Machine {
  public enum State: Equatable, Sendable {
    case choosing(failure: PairingFailure?, request: Int)
    case creating(request: Int)
    /// The invite exists. A tick asks whether the partner has claimed it; `misses` counts the checks
    /// in a row that got no answer, which space the next ones out (`checkDelay`).
    case waiting(code: String, expiresAt: Int, request: Int, misses: Int)
    case claiming(request: Int)
    case paired(PairRole)

    public static let initial = State.choosing(failure: nil, request: 0)

    var request: Int {
      switch self {
      case .choosing(_, let request), .creating(let request), .waiting(_, _, let request, _),
        .claiming(let request):
        request
      case .paired: 0
      }
    }
  }

  public enum Event: Equatable, Sendable {
    case createRequested
    case codeSubmitted(String)
    case cancelled
    /// Time to ask whether the partner has claimed the invite.
    case ticked
    case created(code: String, expiresAt: Int, request: Int)
    case claimed(pairID: String, request: Int)
    /// `paired` is whether the account has a partner now.
    case checked(paired: Bool, request: Int)
    case failed(PairingFailure, request: Int)

    var answeredRequest: Int? {
      switch self {
      case .createRequested, .codeSubmitted, .cancelled, .ticked: nil
      case .created(_, _, let request), .claimed(_, let request), .checked(_, let request),
        .failed(_, let request):
        request
      }
    }
  }

  public enum Output: Equatable, Sendable {
    case createInvite(request: Int)
    case claimInvite(code: String, request: Int)
    case checkPaired(request: Int)
    /// The shown invite outlives a relaunch, since creating another deletes it on the server.
    case keepInvite(KeptInvite)
    case forgetInvite
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    if let answered = event.answeredRequest, answered != state.request {
      return (state, [])
    }
    let request = state.request + 1
    switch (state, event) {
    case (.choosing, .createRequested):
      return (.creating(request: request), [.createInvite(request: request)])

    case (.choosing, .codeSubmitted(let code)):
      let code = code.filter { !$0.isWhitespace }.uppercased()
      guard !code.isEmpty else {
        return (.choosing(failure: .invalidCode, request: state.request), [])
      }
      return (.claiming(request: request), [.claimInvite(code: code, request: request)])

    case (.creating, .created(let code, let expiresAt, _)):
      return (
        .waiting(code: code, expiresAt: expiresAt, request: state.request, misses: 0),
        [.keepInvite(KeptInvite(code: code, expiresAt: expiresAt))]
      )

    case (.waiting(let code, let expiresAt, _, let misses), .ticked):
      // A tick that finds the previous check still out starts another; the old answer is stale.
      return (
        .waiting(code: code, expiresAt: expiresAt, request: request, misses: misses),
        [.checkPaired(request: request)]
      )

    case (.waiting(let code, let expiresAt, let request, _), .checked(let paired, _)):
      if paired { return (.paired(.inviter), [.forgetInvite]) }
      return (.waiting(code: code, expiresAt: expiresAt, request: request, misses: 0), [])

    case (.claiming, .claimed(let pairID, _)):
      return (.paired(.joiner(pairID: pairID)), [])

    case (.claiming, .failed(.alreadyPaired, _)):
      return (.paired(.joiner(pairID: nil)), [])

    case (.creating, .failed(let failure, _)), (.claiming, .failed(let failure, _)):
      return (.choosing(failure: failure, request: state.request), [])

    case (.waiting(let code, let expiresAt, let request, let misses), .failed(let failure, _)):
      // A check that cannot be answered leaves the invite showing; only a lost session ends it.
      if failure == .signedOut {
        return (.choosing(failure: failure, request: state.request), [.forgetInvite])
      }
      return (
        .waiting(code: code, expiresAt: expiresAt, request: request, misses: misses + 1), []
      )

    case (.waiting, .cancelled):
      return (.choosing(failure: nil, request: request), [.forgetInvite])

    case (.claiming, .cancelled), (.creating, .cancelled):
      return (.choosing(failure: nil, request: request), [])

    case (.choosing, .cancelled):
      return (.choosing(failure: nil, request: state.request), [])

    case (.paired, _),
      (.choosing, .ticked), (.choosing, .created), (.choosing, .claimed), (.choosing, .checked),
      (.choosing, .failed),
      (.creating, .createRequested), (.creating, .codeSubmitted), (.creating, .ticked),
      (.creating, .claimed), (.creating, .checked),
      (.waiting, .createRequested), (.waiting, .codeSubmitted), (.waiting, .created),
      (.waiting, .claimed),
      (.claiming, .createRequested), (.claiming, .codeSubmitted), (.claiming, .ticked),
      (.claiming, .created), (.claiming, .checked):
      return (state, [])
    }
  }
}

extension PairingMachine {
  /// How long a shown invite waits before its next check: 6 s, doubled for each check in a row that got
  /// no answer (a refusal for too many requests among them), up to the rate limiter's one-minute window.
  public static func checkDelay(misses: Int) -> Duration {
    .seconds(min(6 << min(misses, 4), 60))
  }

  /// When a shown invite is checked next; nil when no invite is out or it has run out. `now` in epoch
  /// milliseconds.
  public static func nextCheck(_ state: State, now: Int) -> Duration? {
    switch state {
    case .waiting(_, let expiresAt, _, let misses):
      expiresAt > now ? checkDelay(misses: misses) : nil
    case .choosing, .creating, .claiming, .paired: nil
    }
  }

  /// The calls the outputs make, on `api`. A partner's claim shows as `GET /v1/pair` answering.
  public static func run(_ output: Output, api: APIClient, invites: InviteKeeper) async -> Event? {
    switch output {
    case .keepInvite(let invite):
      await invites.keep(invite)
      return nil
    case .forgetInvite:
      await invites.keep(nil)
      return nil
    case .createInvite(let request):
      do {
        let invite = try await api.createInvite()
        return .created(
          code: invite.code.rawValue, expiresAt: invite.expiresAt, request: request)
      } catch {
        return .failed(PairingFailure(error), request: request)
      }
    case .claimInvite(let code, let request):
      do {
        let claim = try await api.claimInvite(ClaimInviteRequest(code: InviteCode(code)))
        return .claimed(pairID: claim.pairId.rawValue, request: request)
      } catch {
        return .failed(PairingFailure(error), request: request)
      }
    case .checkPaired(let request):
      do {
        _ = try await api.pair()
        return .checked(paired: true, request: request)
      } catch {
        if error == .api(.notFound) { return .checked(paired: false, request: request) }
        return .failed(PairingFailure(error), request: request)
      }
    }
  }
}
