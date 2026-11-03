/// What the service says to every app, signed in or not. `minVersion` is the oldest build that may
/// run: an older one shows "Update billet" and nothing else. `notice` is a soft, dismissible line.
/// Fields this client does not know are ignored.
public struct AppStatus: Codable, Hashable, Sendable {
  public let maintenance: MaintenanceStatus
  public let minVersion: AppVersion?
  public let notice: StatusMessage?

  public init(
    maintenance: MaintenanceStatus, minVersion: AppVersion? = nil, notice: StatusMessage? = nil
  ) {
    self.maintenance = maintenance
    self.minVersion = minVersion
    self.notice = notice
  }

  /// No maintenance, no minimum, no notice: what the server serves when nothing was ever set.
  public static let normal = AppStatus(maintenance: MaintenanceStatus(active: false))
}
