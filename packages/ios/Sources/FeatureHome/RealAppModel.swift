import FeatureCanvas
import FeatureInbox
import FeatureOnboarding
import FeaturePairing
import FeatureSettings
import Foundation
import Observation
import Persistence
import Transport
import WidgetBridge
import Wire

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
  private let baseURL: URL
  public let accounts: AccountStore
  public private(set) var signIn: SignInModel
  public private(set) var pairing: PairingModel
  /// The saved Labs choices and the server's test variants for this pair.
  public let labs: WidgetFeaturesModel
  @ObservationIgnored private let flags: FlagsRefresher
  @ObservationIgnored private let reporter: EventReporter
  @ObservationIgnored private let hasWidget: @MainActor () async -> Bool
  @ObservationIgnored private var cachedHistory: HistoryModel?
  @ObservationIgnored private var cachedAccount: AccountModel?
  @ObservationIgnored private var cachedLive: LiveRoom?

  public init(
    api: APIClient, accounts: AccountStore, baseURL: URL,
    labs: WidgetFeaturesModel = WidgetFeaturesModel(store: .appGroup()),
    eventStorage: AppGroupStorage? = try? .appGroup(identifier: AppGroupStorage.billetIdentifier),
    hasWidget: (@MainActor () async -> Bool)? = nil
  ) {
    self.api = api
    self.labs = labs
    flags = FlagsRefresher(api: api, labs: labs)
    reporter = EventReporter(api: api, storage: eventStorage)
    self.hasWidget = hasWidget ?? { await WidgetPresence.isInstalled() }
    self.baseURL = baseURL
    self.accounts = accounts
    stage = RealStage((try? accounts.load()) ?? nil)
    signIn = SignInModel(api: api, accounts: accounts)
    pairing = PairingModel(api: api)
  }

  /// The app came to the front with a paired account: learn which test variants the pair is in
  /// and count what happened. Neither can fail the screen; a failure keeps what was held.
  public func becameActive() async {
    reporter.appOpened()
    await flags.refresh()
    if await hasWidget() { reporter.widgetAdded() }
    await reporter.flush()
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

  /// The history of the signed-in account, kept for as long as the account stays signed in.
  public func history() -> HistoryModel {
    if let cachedHistory { return cachedHistory }
    let me = ((try? accounts.load()) ?? nil)?.record.userID ?? ""
    let model = HistoryModel(api: api, me: me)
    cachedHistory = model
    return model
  }

  /// The room socket of the signed-in account, kept for as long as the account stays signed in.
  /// `lastSeq` is the last note already held, used the first time the room is made.
  public func live(lastSeq: Int?, onNote: @escaping (Int, Note) -> Void) -> LiveRoom {
    if let cachedLive { return cachedLive }
    let accounts = accounts
    let room = LiveRoom.live(
      baseURL: baseURL, token: { (try? accounts.load())?.token }, lastSeq: lastSeq, onNote: onNote)
    cachedLive = room
    return room
  }

  /// The settings of the signed-in account, kept for as long as the account stays signed in.
  public func account() -> AccountModel {
    if let cachedAccount { return cachedAccount }
    let model = AccountModel(api: api, accounts: accounts, health: .system(api: api))
    cachedAccount = model
    return model
  }

  /// Settings finished `action`: unpairing goes back to pairing, signing out back to sign-in.
  public func finished(_ action: AccountAction) {
    cachedLive?.disconnect()
    cachedLive = nil
    cachedHistory = nil
    cachedAccount = nil
    // The variants belong to the pair, and what is waiting to be counted to the account.
    flags.forget()
    if action == .signOut { reporter.discard() }
    pairing = PairingModel(api: api)
    switch action {
    case .unpair:
      stage = .unpaired
    case .signOut:
      signIn = SignInModel(api: api, accounts: accounts)
      stage = .signedOut
    }
  }
}
