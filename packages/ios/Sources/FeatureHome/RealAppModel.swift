import FeatureOnboarding
import FeaturePairing
import Foundation
import Observation
import Persistence
import Transport

/// Which screen the real client shows, from what the device has saved.
public enum RealStage: Equatable, Sendable {
  case signedOut
  case unpaired
  case paired

  public init(_ saved: (token: String, record: AccountRecord)?) {
    switch saved {
    case nil: self = .signedOut
    case let saved? where saved.record.isPaired: self = .paired
    case _?: self = .unpaired
    }
  }
}

/// The real client's top level: reads the saved account, then moves from sign-in to pairing to the
/// paired screens as each step finishes.
@MainActor
@Observable
public final class RealAppModel {
  public private(set) var stage: RealStage
  public let api: APIClient
  public let accounts: AccountStore
  public let signIn: SignInModel
  public private(set) var pairing: PairingModel

  public init(api: APIClient, accounts: AccountStore) {
    self.api = api
    self.accounts = accounts
    stage = RealStage((try? accounts.load()) ?? nil)
    signIn = SignInModel(api: api, accounts: accounts)
    pairing = PairingModel(api: api)
  }

  public func signedIn() {
    stage = RealStage((try? accounts.load()) ?? nil)
  }

  public func paired() {
    if case .paired(let pairID) = pairing.state {
      try? accounts.setPaired(true, pairID)
    }
    stage = .paired
  }

  /// Forgets the account on this phone and returns to sign-in.
  public func signedOut() {
    try? accounts.clear()
    pairing = PairingModel(api: api)
    stage = .signedOut
  }
}
