import Foundation

/// The pairing code and this device's ID. The code is the room's only credential.
struct DemoRoom: Hashable, Sendable {
  private static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTVWXYZ")
  private static let codeLength = 10
  private static let codeKey = "demo.roomCode"
  private static let deviceKey = "demo.deviceID"

  let code: String
  let device: String

  static func generateCode() -> String {
    String((0..<codeLength).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
  }

  static func isValid(code: String) -> Bool {
    code.count == codeLength && code.allSatisfy(alphabet.contains)
  }

  static func saved(in defaults: UserDefaults = .standard) -> DemoRoom? {
    guard let code = defaults.string(forKey: codeKey),
      let device = defaults.string(forKey: deviceKey)
    else { return nil }
    return DemoRoom(code: code, device: device)
  }

  /// Stores `code`, keeping the device ID from any earlier pairing.
  static func pair(code: String, in defaults: UserDefaults = .standard) -> DemoRoom {
    let device = defaults.string(forKey: deviceKey) ?? UUID().uuidString.lowercased()
    defaults.set(code, forKey: codeKey)
    defaults.set(device, forKey: deviceKey)
    return DemoRoom(code: code, device: device)
  }

  static func forget(in defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: codeKey)
  }

  func socketURL(host: String) -> URL? {
    let scheme = host.hasPrefix("127.0.0.1") ? "ws" : "wss"
    return URL(string: "\(scheme)://\(host)/demo/rooms/\(code)/socket?device=\(device)")
  }
}
