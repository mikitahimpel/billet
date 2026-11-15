import Foundation

/// Why the pairing did not work, as far as the onboarding pages tell: a wrong code is the code step's alone.
public nonisolated struct OnboardingPairingFailure: Equatable, Sendable {
  public let isInvalidCode: Bool
  /// The line the invite step shows for it.
  public let message: String

  public init(isInvalidCode: Bool, message: String) {
    self.isInvalidCode = isInvalidCode
    self.message = message
  }
}

/// `PairingMachine.State` as the onboarding pages read it.
public nonisolated enum OnboardingPairingState: Equatable, Sendable {
  case choosing(failure: OnboardingPairingFailure?, request: Int)
  case creating(request: Int)
  case waiting(code: String, expiresAt: Int, request: Int)
  case claiming(request: Int)
  case paired
}

/// The pairing the invite and code steps drive. `PairingModel` conforms, in the app, which keeps the
/// pairing feature out of this one.
public protocol OnboardingPairing: AnyObject {
  /// How often the invite page asks whether its code was claimed.
  static var checkEvery: Duration { get }
  var onboardingState: OnboardingPairingState { get }
  func createInvite()
  func submit(code: String)
  func cancel()
  /// Asks whether the partner has claimed the shown invite.
  func tick()
  func spaced(_ code: String) -> String
  func expiry(expiresAt: Int, now: Date) -> String
}
