import Foundation
import Wire

extension PushPayload {
  /// The key under a push's custom data that holds a `PushPayload` (packages/contracts/push).
  public static let pushKey = "billet"

  public init?(push userInfo: [AnyHashable: Any]) {
    guard let object = userInfo[Self.pushKey], JSONSerialization.isValidJSONObject(object),
      let data = try? JSONSerialization.data(withJSONObject: object),
      let payload = try? JSONDecoder().decode(PushPayload.self, from: data)
    else { return nil }
    self = payload
  }
}
