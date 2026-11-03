import Foundation
import Observation
import Transport
import Wire

/// Runs ``ServiceStatusMachine`` for the open app: asks `/v1/status` when the app comes to the
/// front and every ``checkEvery`` while it stays there, and takes the status the flags answer and
/// any maintenance 503 carry.
///
/// A failed check changes nothing: the app keeps the last status it heard, and normal before any.
@MainActor
@Observable
public final class ServiceStatusModel {
  public static let checkEvery = Duration.seconds(60)

  public private(set) var state: ServiceStatusMachine.State
  /// Counts the times maintenance ended. Whatever holds sends back during maintenance retries
  /// them when this changes.
  public private(set) var maintenanceEnds = 0

  public var screen: ServiceScreen { state.screen }

  /// Asks the service for its status. `nil` when this build has nowhere to ask, as a demo build
  /// without a host.
  public typealias Fetch = @Sendable () async throws(TransportError) -> AppStatus

  @ObservationIgnored private let fetch: Fetch?
  @ObservationIgnored private let memory: NoticeMemory
  @ObservationIgnored private let strings: (String) -> String?
  @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void

  /// - Parameters:
  ///   - appVersion: This build as ``ClientInfo`` names it, `<marketing>+<build>`.
  ///   - strings: The app's own text for a message key, or `nil` when it has none.
  public init(
    appVersion: String?,
    fetch: Fetch?,
    memory: NoticeMemory = .none,
    strings: @escaping (String) -> String? = { _ in nil },
    sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
  ) {
    state = ServiceStatusMachine.State(
      appVersion: appVersion.flatMap(AppVersion.init), dismissedNotice: memory.load())
    self.fetch = fetch
    self.memory = memory
    self.strings = strings
    self.sleep = sleep
  }

  /// Asks the service once.
  public func check() async {
    guard let fetch else { return }
    do throws(TransportError) {
      received(try await fetch())
    } catch {
      switch error {
      case .maintenance(let status): received(status)
      case .network, .api, .status, .encoding, .decoding: break
      }
    }
  }

  /// Checks now and then every ``checkEvery`` until the task is cancelled, as when the app leaves
  /// the front.
  public func run() async {
    while !Task.isCancelled {
      await check()
      await sleep(Self.checkEvery)
    }
  }

  /// A status the service sent some other way: with the flags, or in a maintenance 503.
  public func received(_ status: AppStatus) {
    apply(.received(status))
  }

  public func dismissNotice() {
    apply(.noticeDismissed)
  }

  /// The notice's words, or `nil` when none is shown.
  public var noticeText: String? {
    guard case .normal(let notice?) = screen else { return nil }
    return ServiceStatusCopy.text(notice, strings: strings)
  }

  /// The maintenance screen's message.
  func maintenanceMessage(_ maintenance: MaintenanceStatus) -> String {
    ServiceStatusCopy.maintenanceMessage(maintenance, strings: strings)
  }

  private func apply(_ event: ServiceStatusMachine.Event) {
    let (next, outputs) = ServiceStatusMachine.transition(state, event)
    state = next
    for output in outputs {
      switch output {
      case .maintenanceEnded: maintenanceEnds += 1
      case .rememberDismissed(let notice): memory.save(notice)
      }
    }
  }
}

extension ServiceStatusModel {
  /// The status route at `baseURL`, sent with `headers` like every other request.
  public static func fetch(baseURL: URL, headers: [String: String]) -> Fetch {
    let api = APIClient.live(
      http: .urlSession(baseURL: baseURL, session: .shared, headers: headers), token: { nil })
    return { () async throws(TransportError) -> AppStatus in try await api.status().status }
  }

  /// The demo Worker's status route: `https://<host>/v1/status`, or plain `http` for a local
  /// server. `nil` when the build has no demo host.
  public static func demoBaseURL(host: String) -> URL? {
    guard !host.isEmpty else { return nil }
    let scheme = host.hasPrefix("127.0.0.1") || host.hasPrefix("localhost") ? "http" : "https"
    return URL(string: "\(scheme)://\(host)")
  }

  /// Looks a message key up in `table` of `bundle`. A key the table does not have is `nil`.
  public static func strings(
    in bundle: Bundle, table: String = "ServiceStatus"
  ) -> (String) -> String? {
    { key in
      let missing = "\u{1}"
      let value = bundle.localizedString(forKey: key, value: missing, table: table)
      return value == missing ? nil : value
    }
  }
}

/// Where the dismissed notice is kept between launches.
public struct NoticeMemory {
  public var load: () -> StatusMessage?
  public var save: (StatusMessage) -> Void

  public init(load: @escaping () -> StatusMessage?, save: @escaping (StatusMessage) -> Void) {
    self.load = load
    self.save = save
  }

  /// Kept for this launch only.
  public static var none: NoticeMemory { NoticeMemory(load: { nil }, save: { _ in }) }

  /// Kept in `defaults` under `key`.
  public static func defaults(
    _ defaults: UserDefaults, key: String = "status.dismissedNotice"
  ) -> NoticeMemory {
    NoticeMemory(
      load: {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StatusMessage.self, from: data)
      },
      save: { notice in
        defaults.set(try? JSONEncoder().encode(notice), forKey: key)
      })
  }
}
