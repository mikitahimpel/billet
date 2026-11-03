import BilletKit
import Persistence
import Transport
import Wire

/// Why signing in did not finish, as the screen words it.
public enum SignInFailure: Equatable, Sendable {
  /// Apple refused or could not answer. A cancelled sheet is not a failure.
  case appleRefused
  /// The backend did not accept the identity token.
  case rejected
  /// The backend or the network is down. Trying again is safe.
  case unavailable
  /// The session could not be saved on this device.
  case storage

  public init(_ error: TransportError) {
    switch error {
    case .api(.unauthorized), .api(.invalidRequest): self = .rejected
    case .api(.unavailable), .api(.notFound), .api(.invalidInvite), .api(.alreadyPaired),
      .api(.appleIdInUse), .network, .status, .encoding, .decoding:
      self = .unavailable
    }
  }
}

/// From launch to a saved session: fetch a nonce, let Apple sign it into an identity token, and
/// trade the token for a session.
///
/// Each state holds only what it needs, so there is no "signed in without a session" or "asking
/// Apple without a nonce". `request` counts the backend calls so a late answer changes nothing.
public enum SignInMachine: Machine {
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

extension SignInMachine {
  public static func run(
    _ output: Output, api: APIClient, accounts: AccountStore
  ) async -> Event? {
    switch output {
    case .fetchNonce(let request):
      do {
        let challenge = try await api.authChallenge()
        return .nonceFetched(challenge.nonce.rawValue, request: request)
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
