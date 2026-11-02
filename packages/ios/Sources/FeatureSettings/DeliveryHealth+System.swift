#if canImport(UserNotifications) && canImport(WidgetKit)
  import Transport
  import UserNotifications
  import WidgetKit

  extension DeliveryHealth {
    /// Reads the real notification settings and installed widgets, and asks `api` whether the
    /// backend answers.
    public static func system(api: APIClient) -> DeliveryHealth {
      DeliveryHealth(
        notifications: {
          let settings = await UNUserNotificationCenter.current().notificationSettings()
          switch settings.authorizationStatus {
          case .authorized, .provisional, .ephemeral: return .allowed
          case .denied: return .denied
          case .notDetermined: return .notAsked
          @unknown default: return .denied
          }
        },
        widgets: {
          await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
              continuation.resume(returning: (try? result.get().count) ?? 0)
            }
          }
        },
        backendReachable: reachability(of: api))
    }
  }
#endif
