import Transport

/// Whether the phone will let notifications through.
public enum NotificationAccess: Equatable, Sendable {
  case allowed
  case denied
  case notAsked
}

extension NotificationAccess {
  fileprivate var detail: String {
    switch self {
    case .allowed: "On"
    case .denied: "Off. Turn them on in iOS Settings so notes can reach you."
    case .notAsked: "Not asked yet. Allow them so notes can reach you."
    }
  }
}

/// What the delivery health check found.
public struct HealthReport: Equatable, Sendable {
  public var notifications: NotificationAccess
  /// How many Billet widgets are on the Home or Lock Screen.
  public var widgets: Int
  /// Whether the backend answered.
  public var backendReachable: Bool

  public init(notifications: NotificationAccess, widgets: Int, backendReachable: Bool) {
    self.notifications = notifications
    self.widgets = widgets
    self.backendReachable = backendReachable
  }

  /// A note can reach this phone only if notifications are allowed and the backend answers.
  /// Widgets are a choice, so none is not a failure.
  public var isHealthy: Bool {
    notifications == .allowed && backendReachable
  }

  public struct Line: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var ok: Bool
  }

  public var lines: [Line] {
    [
      Line(
        title: "Notifications", detail: notifications.detail, ok: notifications == .allowed),
      Line(
        title: "Widgets",
        detail: widgets == 0
          ? "None on your Home or Lock Screen."
          : widgets == 1 ? "1 widget." : "\(widgets) widgets.", ok: true),
      Line(
        title: "Billet",
        detail: backendReachable ? "Reachable" : "Can't be reached right now.",
        ok: backendReachable),
    ]
  }
}

/// The three things a delivery check reads, as closures so tests supply them.
public struct DeliveryHealth: Sendable {
  public var notifications: @Sendable () async -> NotificationAccess
  public var widgets: @Sendable () async -> Int
  public var backendReachable: @Sendable () async -> Bool

  public init(
    notifications: @escaping @Sendable () async -> NotificationAccess,
    widgets: @escaping @Sendable () async -> Int,
    backendReachable: @escaping @Sendable () async -> Bool
  ) {
    self.notifications = notifications
    self.widgets = widgets
    self.backendReachable = backendReachable
  }

  public func check() async -> HealthReport {
    async let notifications = notifications()
    async let widgets = widgets()
    async let reachable = backendReachable()
    return await HealthReport(
      notifications: notifications, widgets: widgets, backendReachable: reachable)
  }
}

extension DeliveryHealth {
  /// A backend that answers at all, even "not paired", is reachable.
  public static func reachability(of api: APIClient) -> @Sendable () async -> Bool {
    {
      do throws(TransportError) {
        _ = try await api.listNotes(nil)
        return true
      } catch {
        switch error {
        case .api(.notFound), .api(.unauthorized), .api(.invalidRequest): return true
        case .api(.unavailable), .api(.invalidInvite), .api(.alreadyPaired), .network, .status,
          .encoding, .decoding:
          return false
        }
      }
    }
  }
}
