/// What the service says to every app, signed in or not. `minVersion` is the oldest build that may
/// run: an older one shows "Update billet" and nothing else. `notice` is a soft, dismissible line.
/// `analytics` switches the app's event reports. Fields this client does not know are ignored.
public struct AppStatus: Codable, Hashable, Sendable {
  public let maintenance: MaintenanceStatus
  public let minVersion: AppVersion?
  public let notice: StatusMessage?
  public let analytics: AnalyticsStatus?

  public init(
    maintenance: MaintenanceStatus, minVersion: AppVersion? = nil, notice: StatusMessage? = nil,
    analytics: AnalyticsStatus? = nil
  ) {
    self.maintenance = maintenance
    self.minVersion = minVersion
    self.notice = notice
    self.analytics = analytics
  }

  /// No maintenance, no minimum, no notice: what the server serves when nothing was ever set.
  public static let normal = AppStatus(maintenance: MaintenanceStatus(active: false))

  /// Whether the app may report events: yes unless the status says `analytics.enabled: false`.
  public var analyticsEnabled: Bool { analytics?.enabled != false }
}

/// Product analytics, the events of ``ClientEventName``. On unless `enabled` is false: then the
/// app stops reporting and drops what it was holding.
public struct AnalyticsStatus: Codable, Hashable, Sendable {
  public let enabled: Bool

  public init(enabled: Bool) {
    self.enabled = enabled
  }
}
