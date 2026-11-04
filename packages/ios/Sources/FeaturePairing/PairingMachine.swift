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
    case .api(.unavailable), .api(.notFound), .api(.appleIdInUse), .api(.invalidPurchase), .network,
      .status, .maintenance,
      .encoding,
      .decoding:
      self = .unavailable
    }
  }
}

/// Create an invite and wait for the partner, or enter the partner's code.
///
/// `request` counts the calls made, so a result for an earlier call changes nothing.
public enum PairingMachine: Machine {
  public enum State: Equatable, Sendable {
    case choosing(failure: PairingFailure?, request: Int)
    case creating(request: Int)
    /// The invite exists. A tick asks whether the partner has claimed it.
    case waiting(code: String, expiresAt: Int, request: Int)
    case claiming(request: Int)
    /// `pairID` is known only to the partner who entered the code.
    case paired(pairID: String?)

    public static let initial = State.choosing(failure: nil, request: 0)

    var request: Int {
      switch self {
      case .choosing(_, let request), .creating(let request), .waiting(_, _, let request),
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
      return (.waiting(code: code, expiresAt: expiresAt, request: state.request), [])

    case (.waiting(let code, let expiresAt, _), .ticked):
      // A tick that finds the previous check still out starts another; the old answer is stale.
      return (
        .waiting(code: code, expiresAt: expiresAt, request: request),
        [.checkPaired(request: request)]
      )

    case (.waiting, .checked(let paired, _)):
      if paired { return (.paired(pairID: nil), []) }
      return (state, [])

    case (.claiming, .claimed(let pairID, _)):
      return (.paired(pairID: pairID), [])

    case (.creating, .failed(let failure, _)), (.claiming, .failed(let failure, _)):
      return (.choosing(failure: failure, request: state.request), [])

    case (.waiting, .failed(let failure, _)):
      // A check that cannot be answered leaves the invite showing; only a lost session ends it.
      if failure == .signedOut { return (.choosing(failure: failure, request: state.request), []) }
      return (state, [])

    case (.waiting, .cancelled), (.claiming, .cancelled), (.creating, .cancelled):
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
  /// The calls the outputs make, on `api`. A partner's claim shows as the notes route answering,
  /// because there is no route that reports the pair directly.
  public static func run(_ output: Output, api: APIClient) async -> Event? {
    switch output {
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
        _ = try await api.listNotes(nil)
        return .checked(paired: true, request: request)
      } catch {
        if error == .api(.notFound) { return .checked(paired: false, request: request) }
        return .failed(PairingFailure(error), request: request)
      }
    }
  }
}
