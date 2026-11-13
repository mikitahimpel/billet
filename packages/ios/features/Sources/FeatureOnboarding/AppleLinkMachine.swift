import BilletKit
import Observation
import Transport
import Wire

/// The Settings' Account card: whether this account is linked to an Apple ID, and linking it.
/// `request` counts the backend calls so a late answer changes nothing.
public nonisolated enum AppleLinkMachine: Machine {
  public enum State: Equatable, Sendable {
    case idle
    case checking(request: Int)
    /// The server could not say whether the account is linked.
    case checkFailed(request: Int)
    /// Not linked; fetching the nonce Apple's request must carry.
    case preparing(request: Int)
    /// Not linked; Apple's button is shown.
    case ready(nonce: String, request: Int)
    case linking(request: Int)
    case linked
    /// Not linked. `appleIdInUse` means another account has this Apple ID: trying again asks Apple
    /// again, and the user can choose another Apple ID in its sheet.
    case failed(SignInFailure, request: Int)

    var request: Int {
      switch self {
      case .idle, .linked: 0
      case .checking(let request), .checkFailed(let request), .preparing(let request),
        .ready(_, let request), .linking(let request), .failed(_, let request):
        request
      }
    }
  }

  public enum Event: Equatable, Sendable {
    case appeared
    case retried
    case statusRead(linked: Bool, request: Int)
    case nonceFetched(String, request: Int)
    /// Apple's sheet gave back an identity token.
    case appleCompleted(identityToken: String)
    /// The user closed Apple's sheet.
    case appleCancelled
    case appleFailed
    case linkSaved(request: Int)
    case failed(SignInFailure, request: Int)

    var answeredRequest: Int? {
      switch self {
      case .appeared, .retried, .appleCompleted, .appleCancelled, .appleFailed: nil
      case .statusRead(_, let request), .nonceFetched(_, let request), .linkSaved(let request),
        .failed(_, let request):
        request
      }
    }
  }

  public enum Output: Equatable, Sendable {
    case readStatus(request: Int)
    case fetchNonce(request: Int)
    case link(identityToken: String, request: Int)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    if let answered = event.answeredRequest, answered != state.request {
      return (state, [])
    }
    let next = state.request + 1
    switch state {
    case .idle:
      switch event {
      case .appeared: return (.checking(request: next), [.readStatus(request: next)])
      case .retried, .statusRead, .nonceFetched, .appleCompleted, .appleCancelled, .appleFailed,
        .linkSaved, .failed:
        return (state, [])
      }

    case .checking:
      switch event {
      case .statusRead(let linked, _):
        return linked
          ? (.linked, []) : (.preparing(request: next), [.fetchNonce(request: next)])
      case .failed: return (.checkFailed(request: state.request), [])
      case .appeared, .retried, .nonceFetched, .appleCompleted, .appleCancelled, .appleFailed,
        .linkSaved:
        return (state, [])
      }

    case .checkFailed:
      switch event {
      case .retried: return (.checking(request: next), [.readStatus(request: next)])
      case .appeared, .statusRead, .nonceFetched, .appleCompleted, .appleCancelled, .appleFailed,
        .linkSaved, .failed:
        return (state, [])
      }

    case .preparing:
      switch event {
      case .nonceFetched(let nonce, _): return (.ready(nonce: nonce, request: state.request), [])
      case .failed(let failure, _): return (.failed(failure, request: state.request), [])
      case .appeared, .retried, .statusRead, .appleCompleted, .appleCancelled, .appleFailed,
        .linkSaved:
        return (state, [])
      }

    case .ready:
      switch event {
      case .appleCompleted(let token):
        return (.linking(request: next), [.link(identityToken: token, request: next)])
      case .appleFailed: return (.failed(.appleRefused, request: state.request), [])
      case .appeared, .retried, .statusRead, .nonceFetched, .appleCancelled, .linkSaved, .failed:
        return (state, [])
      }

    case .linking:
      switch event {
      case .linkSaved: return (.linked, [])
      case .failed(let failure, _): return (.failed(failure, request: state.request), [])
      case .appeared, .retried, .statusRead, .nonceFetched, .appleCompleted, .appleCancelled,
        .appleFailed:
        return (state, [])
      }

    case .linked:
      switch event {
      case .appeared, .retried, .statusRead, .nonceFetched, .appleCompleted, .appleCancelled,
        .appleFailed, .linkSaved, .failed:
        return (state, [])
      }

    case .failed:
      switch event {
      case .retried: return (.preparing(request: next), [.fetchNonce(request: next)])
      case .appeared, .statusRead, .nonceFetched, .appleCompleted, .appleCancelled, .appleFailed,
        .linkSaved, .failed:
        return (state, [])
      }
    }
  }
}

nonisolated extension AppleLinkMachine {
  public static func run(_ output: Output, api: APIClient) async -> Event? {
    switch output {
    case .readStatus(let request):
      do {
        let account = try await api.account()
        return .statusRead(linked: account.linked, request: request)
      } catch {
        return .failed(SignInFailure(error), request: request)
      }
    case .fetchNonce(let request):
      do {
        let challenge = try await api.authChallenge()
        return .nonceFetched(challenge.nonce.rawValue, request: request)
      } catch {
        return .failed(SignInFailure(error), request: request)
      }
    case .link(let identityToken, let request):
      do {
        _ = try await api.linkApple(SignInWithAppleRequest(identityToken: identityToken))
        return .linkSaved(request: request)
      } catch {
        return .failed(SignInFailure(error), request: request)
      }
    }
  }
}

/// Runs ``AppleLinkMachine`` against the backend.
@MainActor
@Observable
public final class AppleLinkModel {
  private let store: Store<AppleLinkMachine>

  public var state: AppleLinkMachine.State { store.state }

  public init(api: APIClient) {
    store = Store<AppleLinkMachine>(initial: .idle) { output in
      await AppleLinkMachine.run(output, api: api)
    }
  }

  public func appeared() { store.send(.appeared) }
  public func retry() { store.send(.retried) }
  public func appleCompleted(identityToken: String) {
    store.send(.appleCompleted(identityToken: identityToken))
  }
  public func appleCancelled() { store.send(.appleCancelled) }
  public func appleFailed() { store.send(.appleFailed) }
  public func settled() async { await store.settled() }

}

nonisolated extension SignInFailure {
  /// What the Account card tells the user.
  public var linkMessage: String {
    switch self {
    case .appleRefused: "Apple couldn't sign you in. Try again."
    case .rejected:
      "Ourio didn't accept that sign-in, which can happen after a long wait. Try again."
    case .unavailable:
      "Ourio can't be reached right now. Nothing was linked. Try again in a moment."
    case .storage: "Ourio couldn't save that on this phone. Try again."
    case .appleIdInUse:
      "This Apple ID is already linked to another Ourio account, maybe from an earlier install. "
        + "Try again and choose a different Apple ID."
    }
  }
}
