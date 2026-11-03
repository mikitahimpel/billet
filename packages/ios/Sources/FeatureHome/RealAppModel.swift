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
  /// The anonymous account's key in the iCloud Keychain.
  public let keys: AccountKeyStore
  @ObservationIgnored private let reauthorize: AppleReauthorizer
  public private(set) var signIn: SignInModel
  /// Opens or restores the account from the iCloud key, with no question asked.
  public private(set) var anonymous: AnonymousSignInModel
  /// Whether the account can also be recovered with Sign in with Apple; `nil` until the server
  /// has said.
  public private(set) var linked: Bool?
  /// The partner left and the user hasn't been told yet. The pair has already ended.
  public private(set) var partnerLeft: PartnerLeft?
  public private(set) var pairing: PairingModel
  /// The saved Labs choices and the server's test variants for this pair.
  public let labs: WidgetFeaturesModel
  /// Maintenance, the oldest build that may run, and the service's notice.
  public let serviceStatus: ServiceStatusModel
  @ObservationIgnored private let flags: FlagsRefresher
  @ObservationIgnored private let reporter: EventReporter
  @ObservationIgnored private let hasWidget: @MainActor () async -> Bool
  @ObservationIgnored private var cachedHistory: HistoryModel?
  @ObservationIgnored private var cachedAccount: AccountModel?
  @ObservationIgnored private var cachedLive: LiveRoom?
  @ObservationIgnored private let noticeStorage: AppGroupStorage?
  private static let seenNoticeFile = "partner-left-seen.json"

  public init(
    api: APIClient, accounts: AccountStore, keys: AccountKeyStore, baseURL: URL,
    reauthorize: @escaping AppleReauthorizer = { await AppleReauthorization.system() },
    labs: WidgetFeaturesModel = WidgetFeaturesModel(store: .appGroup()),
    eventStorage: AppGroupStorage? = try? .appGroup(identifier: AppGroupStorage.billetIdentifier),
    hasWidget: (@MainActor () async -> Bool)? = nil,
    serviceStatus: ServiceStatusModel? = nil
  ) {
    self.api = api
    self.labs = labs
    self.serviceStatus =
      serviceStatus
      ?? ServiceStatusModel(
        appVersion: nil,
        fetch: { () async throws(TransportError) -> AppStatus in try await api.status().status })
    flags = FlagsRefresher(api: api, labs: labs)
    reporter = EventReporter(api: api, storage: eventStorage)
    self.hasWidget = hasWidget ?? { await WidgetPresence.isInstalled() }
    self.baseURL = baseURL
    self.accounts = accounts
    self.keys = keys
    self.reauthorize = reauthorize
    stage = RealStage((try? accounts.load()) ?? nil)
    signIn = SignInModel(api: api, accounts: accounts)
    anonymous = AnonymousSignInModel(api: api, keys: keys, accounts: accounts)
    pairing = PairingModel(api: api)
    noticeStorage = eventStorage
  }

  /// The app came to the front with a paired account: learn which test variants the pair is in
  /// and count what happened. Neither can fail the screen; a failure keeps what was held.
  public func becameActive() async {
    await refreshAccount()
    reporter.appOpened()
    if let status = await flags.refresh() { serviceStatus.received(status) }
    if await hasWidget() { reporter.widgetAdded() }
    await reporter.flush()
  }

  /// Maintenance is over: the room reconnects now instead of waiting out its back-off, and the
  /// events that could not be counted during it are sent.
  public func maintenanceEnded() async {
    if let cachedLive, !cachedLive.isOnline {
      cachedLive.disconnect()
      cachedLive.connect()
    }
    cachedHistory?.refresh()
    await reporter.flush()
  }

  /// Asks the server about the account: whether it is linked, and whether the partner left. A
  /// partner who left ends the pair here too, and the notice waits for ``partnerLeftSeen()``.
  public func refreshAccount() async {
    guard stage != .signedOut, let account = try? await api.account() else { return }
    linked = account.linked
    guard let left = account.partnerLeft else { return }
    if stage == .paired {
      try? accounts.setPaired(false, nil)
      finished(.unpair)
    }
    let seen = try? noticeStorage?.readJSON(Int.self, named: Self.seenNoticeFile)
    if seen != left.at { partnerLeft = left }
  }

  /// The user has read that their partner left; it isn't shown again.
  public func partnerLeftSeen() {
    if let partnerLeft { try? noticeStorage?.writeJSON(partnerLeft.at, named: Self.seenNoticeFile) }
    partnerLeft = nil
  }

  /// The account is now linked to an Apple ID.
  public func linkedApple() {
    linked = true
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
    let model = AccountModel(
      api: api, accounts: accounts, keys: keys, health: .system(api: api),
      reauthorize: reauthorize)
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
    if action != .unpair { reporter.discard() }
    pairing = PairingModel(api: api)
    switch action {
    case .unpair:
      stage = .unpaired
    case .signOut, .deleteAccount:
      signIn = SignInModel(api: api, accounts: accounts)
      anonymous = AnonymousSignInModel(api: api, keys: keys, accounts: accounts)
      linked = nil
      stage = .signedOut
    }
  }
}
