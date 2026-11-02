import BilletKit
import Persistence
import Transport

/// What the user can end from Settings.
public enum AccountAction: Equatable, Sendable {
  /// Leaves the partner; the account stays and can pair again.
  case unpair
  /// Forgets the account on this phone.
  case signOut
}

public enum AccountFailure: Equatable, Sendable {
  case unavailable
  case storage
}

/// Unpair and sign out, each behind a confirmation.
///
/// Illegal states are unrepresentable: an action is only `working` after it was confirmed, and
/// `done` carries what finished so the app can move to the matching screen.
public enum AccountMachine: Machine {
  /// `request` counts the actions started, and every state keeps it, so a number is never reused
  /// and an answer to an earlier action is told apart from the current one.
  public enum State: Equatable, Sendable {
    case idle(request: Int)
    case confirming(AccountAction, request: Int)
    case working(AccountAction, request: Int)
    case done(AccountAction)
    case failed(AccountAction, AccountFailure, request: Int)

    public static let initial = State.idle(request: 0)

    var request: Int {
      switch self {
      case .idle(let request), .confirming(_, let request), .working(_, let request),
        .failed(_, _, let request):
        request
      case .done: 0
      }
    }
  }

  public enum Event: Equatable, Sendable {
    case requested(AccountAction)
    case confirmed
    case cancelled
    case succeeded(request: Int)
    case failed(AccountFailure, request: Int)

    var answeredRequest: Int? {
      switch self {
      case .requested, .confirmed, .cancelled: nil
      case .succeeded(let request), .failed(_, let request): request
      }
    }
  }

  public enum Output: Equatable, Sendable {
    case perform(AccountAction, request: Int)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    if let answered = event.answeredRequest, answered != state.request {
      return (state, [])
    }
    switch (state, event) {
    case (.idle(let request), .requested(let action)),
      (.failed(_, _, let request), .requested(let action)):
      return (.confirming(action, request: request), [])

    case (.confirming(let action, let request), .confirmed),
      (.failed(let action, _, let request), .confirmed):
      return (
        .working(action, request: request + 1), [.perform(action, request: request + 1)]
      )

    case (.confirming(_, let request), .cancelled), (.failed(_, _, let request), .cancelled):
      return (.idle(request: request), [])

    case (.working(let action, _), .succeeded):
      return (.done(action), [])

    case (.working(let action, let request), .failed(let failure, _)):
      return (.failed(action, failure, request: request), [])

    case (.idle, .confirmed), (.idle, .cancelled), (.idle, .succeeded), (.idle, .failed),
      (.confirming, .requested), (.confirming, .succeeded), (.confirming, .failed),
      (.working, .requested), (.working, .confirmed), (.working, .cancelled),
      (.done, _),
      (.failed, .succeeded), (.failed, .failed):
      return (state, [])
    }
  }
}

extension AccountMachine {
  public static func run(
    _ output: Output, api: APIClient, accounts: AccountStore
  ) async -> Event? {
    switch output {
    case .perform(.unpair, let request):
      do {
        try await api.unpair()
      } catch {
        return .failed(.unavailable, request: request)
      }
      do {
        try accounts.setPaired(false, nil)
        return .succeeded(request: request)
      } catch {
        return .failed(.storage, request: request)
      }

    case .perform(.signOut, let request):
      // The server forgets the session when it can be reached. Either way the phone forgets it, so
      // a phone that is offline can still be signed out.
      try? await api.signOut()
      do {
        try accounts.clear()
        return .succeeded(request: request)
      } catch {
        return .failed(.storage, request: request)
      }
    }
  }
}
