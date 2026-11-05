import BilletKit
import Wire

/// What the service's status lets the app show, most pressing first.
public enum ServiceScreen: Hashable, Sendable {
  /// This build is older than the service accepts. Nothing else is shown.
  case updateRequired
  /// The calm maintenance screen over the app, which stays as it was underneath.
  case maintenance(MaintenanceStatus)
  /// The app as usual, with the service's notice above it unless the user dismissed it.
  case normal(notice: StatusMessage?)
}

/// The service's status as the app sees it, from the `/v1/status` poll, the flags answer and the
/// 503 any write meets during maintenance. The latest answer wins, whichever source it came from.
///
/// An update required comes before maintenance, and maintenance before a notice. A build that
/// does not know its own version is never told to update. A dismissed notice stays dismissed until
/// the service sends one with another key or text.
public enum ServiceStatusMachine: Machine {
  public struct State: Hashable, Sendable {
    /// This build, or `nil` when its bundle names no version.
    public var appVersion: AppVersion?
    /// The latest status heard. Normal until the service says otherwise.
    public var status: AppStatus
    public var dismissedNotice: StatusMessage?

    public init(
      appVersion: AppVersion?, status: AppStatus = .normal, dismissedNotice: StatusMessage? = nil
    ) {
      self.appVersion = appVersion
      self.status = status
      self.dismissedNotice = dismissedNotice
    }

    public var screen: ServiceScreen {
      if let minimum = status.minVersion, let appVersion, appVersion.isOlder(than: minimum) {
        return .updateRequired
      }
      if status.maintenance.active {
        return .maintenance(status.maintenance)
      }
      guard let notice = status.notice, notice != dismissedNotice else {
        return .normal(notice: nil)
      }
      return .normal(notice: notice)
    }
  }

  public enum Event: Hashable, Sendable {
    /// The service's status, from any of its sources.
    case received(AppStatus)
    /// The user closed the notice on screen.
    case noticeDismissed
  }

  public enum Output: Hashable, Sendable {
    /// Maintenance is over, so what waited for it can be sent now.
    case maintenanceEnded
    /// Keep the dismissed notice, so it stays dismissed after the next launch.
    case rememberDismissed(StatusMessage)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    var next = state
    switch event {
    case .received(let status):
      next.status = status
      let ended = state.status.maintenance.active && !status.maintenance.active
      return (next, ended ? [.maintenanceEnded] : [])
    case .noticeDismissed:
      guard case .normal(let notice?) = state.screen else { return (state, []) }
      next.dismissedNotice = notice
      return (next, [.rememberDismissed(notice)])
    }
  }
}
