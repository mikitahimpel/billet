/// Served to every app, signed in or not. An app older than `minVersion` shows "Update billet"
/// and nothing else. `notice` is a soft, dismissible line. Unknown fields are ignored.
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

  /// What the server serves when nothing was ever set.
  public static let normal = AppStatus(maintenance: MaintenanceStatus(active: false))

  public var analyticsEnabled: Bool { analytics?.enabled != false }
}

/// When `enabled` is false the app stops reporting and drops what it was holding.
public struct AnalyticsStatus: Codable, Hashable, Sendable {
  public let enabled: Bool

  public init(enabled: Bool) {
    self.enabled = enabled
  }
}
