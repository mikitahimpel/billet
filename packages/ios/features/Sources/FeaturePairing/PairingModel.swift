import BilletKit
import Foundation
import Observation
import Transport

/// Runs ``PairingMachine`` against the backend.
@MainActor
@Observable
public final class PairingModel {
  private let store: Store<PairingMachine>

  public var state: PairingMachine.State { store.state }

  /// Starts on the invite `invites` kept while it has not run out, so a relaunch shows the same code.
  public init(api: APIClient, invites: InviteKeeper = .none, now: Date = .now) {
    let kept = invites.load().flatMap {
      $0.expiresAt > Int(now.timeIntervalSince1970 * 1000) ? $0 : nil
    }
    let initial =
      kept.map {
        PairingMachine.State.waiting(code: $0.code, expiresAt: $0.expiresAt, request: 0, misses: 0)
      }
      ?? .initial
    store = Store<PairingMachine>(initial: initial) { output in
      await PairingMachine.run(output, api: api, invites: invites)
    }
  }

  public func createInvite() { store.send(.createRequested) }
  public func submit(code: String) { store.send(.codeSubmitted(code)) }
  public func cancel() { store.send(.cancelled) }
  /// Asks whether the partner has claimed the shown invite.
  public func tick() { store.send(.ticked) }
  /// When the shown invite is checked next; nil while none is out or it has run out.
  public func nextCheck(now: Date = .now) -> Duration? {
    PairingMachine.nextCheck(state, now: Int(now.timeIntervalSince1970 * 1000))
  }
  /// While an invite is shown.
  public var isWaiting: Bool {
    if case .waiting = state { true } else { false }
  }
  public func settled() async { await store.settled() }
}

extension PairingFailure {
  /// What the screen tells the user.
  public var message: String {
    switch self {
    case .invalidCode:
      "That code isn't working. It may be mistyped, expired, already used or your own."
    case .alreadyPaired:
      "You already have a partner. Unpair in Settings before pairing again."
    case .signedOut:
      "You've been signed out. Open the app again to sign in."
    case .unavailable:
      "Ourio can't be reached right now. Try again in a moment."
    }
  }
}
