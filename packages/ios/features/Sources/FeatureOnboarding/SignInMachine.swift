import BilletKit
import Persistence
import Transport
import Wire

/// Why signing in did not finish, as the screen words it.
public nonisolated enum SignInFailure: Equatable, Sendable {
  /// Apple refused or could not answer. A cancelled sheet is not a failure.
  case appleRefused
  /// The backend did not accept the identity token.
  case rejected
  /// The backend or the network is down. Trying again is safe.
  case unavailable
  /// The session could not be saved on this device.
  case storage
  /// Linking only: this Apple ID already has its own account.
  case appleIdInUse

  public init(_ error: TransportError) {
    switch error {
    case .api(.unauthorized), .api(.invalidRequest): self = .rejected
    case .api(.appleIdInUse): self = .appleIdInUse
    case .api(.unavailable), .api(.notFound), .api(.invalidInvite), .api(.alreadyPaired),
      .api(.invalidPurchase), .api(.inkNotOwned), .api(.notEnoughCoins), .api(.alreadyOwned),
      .api(.collectionIncomplete), .api(.giftTaken), .api(.bonusTaken), .api(.catNotAdopted),
      .api(.streakNotRestorable), .api(.priceChanged), .api(.layoutRefused),
      .network, .status, .maintenance, .encoding, .decoding:
      self = .unavailable
    }
  }
}

/// From launch to a saved session: fetch a nonce, let Apple sign it into an identity token, and
/// trade the token for a session. `request` counts the backend calls so a late answer changes
/// nothing.
public nonisolated enum SignInMachine: Machine {
  public enum State: Equatable, Sendable {
    case idle
    case fetchingNonce(request: Int)
    /// The nonce is what Apple's request must carry.
    case ready(nonce: String, request: Int)
    case exchanging(request: Int)
    case signedIn
    case failed(SignInFailure, request: Int)

    var request: Int {
      switch self {
      case .idle, .signedIn: 0
      case .fetchingNonce(let request), .ready(_, let request), .exchanging(let request),
        .failed(_, let request):
        request
      }
    }
  }

  public enum Event: Equatable, Sendable {
    case appeared
    case retried
    case nonceFetched(String, request: Int)
    /// Apple's sheet gave back an identity token.
    case appleCompleted(identityToken: String)
    /// The user closed Apple's sheet.
    case appleCancelled
    case appleFailed
    case sessionSaved(request: Int)
    case failed(SignInFailure, request: Int)

    var answeredRequest: Int? {
      switch self {
      case .appeared, .retried, .appleCompleted, .appleCancelled, .appleFailed: nil
      case .nonceFetched(_, let request), .sessionSaved(let request), .failed(_, let request):
        request
      }
    }
  }

  public enum Output: Equatable, Sendable {
    case fetchNonce(request: Int)
    case exchange(identityToken: String, request: Int)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    if let answered = event.answeredRequest, answered != state.request {
      return (state, [])
    }
    let request = state.request + 1
    switch (state, event) {
    case (.idle, .appeared), (.failed, .retried):
      return (.fetchingNonce(request: request), [.fetchNonce(request: request)])

    case (.fetchingNonce, .nonceFetched(let nonce, _)):
      return (.ready(nonce: nonce, request: state.request), [])

    case (.ready, .appleCompleted(let token)):
      return (.exchanging(request: request), [.exchange(identityToken: token, request: request)])

    case (.ready, .appleCancelled):
      return (state, [])

    case (.ready, .appleFailed):
      return (.failed(.appleRefused, request: state.request), [])

    case (.exchanging, .sessionSaved):
      return (.signedIn, [])

    case (.fetchingNonce, .failed(let failure, _)), (.exchanging, .failed(let failure, _)):
      return (.failed(failure, request: state.request), [])

    case (.idle, _), (.signedIn, _),
      (.fetchingNonce, .appeared), (.fetchingNonce, .retried), (.fetchingNonce, .appleCompleted),
      (.fetchingNonce, .appleCancelled), (.fetchingNonce, .appleFailed),
      (.fetchingNonce, .sessionSaved),
      (.ready, .appeared), (.ready, .retried), (.ready, .nonceFetched), (.ready, .sessionSaved),
      (.ready, .failed),
      (.exchanging, .appeared), (.exchanging, .retried), (.exchanging, .nonceFetched),
      (.exchanging, .appleCompleted), (.exchanging, .appleCancelled), (.exchanging, .appleFailed),
      (.failed, .appeared), (.failed, .nonceFetched), (.failed, .appleCompleted),
      (.failed, .appleCancelled), (.failed, .appleFailed), (.failed, .sessionSaved),
      (.failed, .failed):
      return (state, [])
    }
  }
}

/// What the Apple identity token is for.
public nonisolated enum SignInPurpose: Equatable, Sendable {
  /// Sign in to the account linked to this Apple ID, or open one, and save its session.
  case signIn
  /// Link the account already signed in on this phone. Its session stays as it is.
  case link
}

nonisolated extension SignInMachine {
  public static func run(
    _ output: Output, api: APIClient, accounts: AccountStore, purpose: SignInPurpose = .signIn
  ) async -> Event? {
    switch output {
    case .fetchNonce(let request):
      do {
        let challenge = try await api.authChallenge()
        return .nonceFetched(challenge.nonce.rawValue, request: request)
      } catch {
        return .failed(SignInFailure(error), request: request)
      }
    case .exchange(let identityToken, let request) where purpose == .link:
      do {
        _ = try await api.linkApple(SignInWithAppleRequest(identityToken: identityToken))
        return .sessionSaved(request: request)
      } catch {
        return .failed(SignInFailure(error), request: request)
      }
    case .exchange(let identityToken, let request):
      let session: SessionResponse
      do {
        session = try await api.signInWithApple(
          SignInWithAppleRequest(identityToken: identityToken))
      } catch {
        return .failed(SignInFailure(error), request: request)
      }
      do {
        try accounts.save(
          session.sessionToken.rawValue,
          AccountRecord(
            userID: session.userId.rawValue, deviceID: session.deviceId.rawValue,
            expiresAt: session.expiresAt))
        return .sessionSaved(request: request)
      } catch {
        return .failed(.storage, request: request)
      }
    }
  }
}
