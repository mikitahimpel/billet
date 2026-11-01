import Foundation
import Ink

/// The pairing code and this device's ID, shared with the extensions through the App Group.
/// The code is the room's only credential.
public struct DemoRoom: Hashable, Sendable {
  private static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTVWXYZ")
  private static let codeLength = 10
  private static let codeKey = "demo.roomCode"
  private static let deviceKey = "demo.deviceID"
  private static let pushTokenKey = "demo.pushToken"

  public let code: String
  public let device: String

  public init(code: String, device: String) {
    self.code = code
    self.device = device
  }

  public static var sharedDefaults: UserDefaults {
    UserDefaults(suiteName: NoteImage.appGroup) ?? .standard
  }

  public static func generateCode() -> String {
    String((0..<codeLength).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
  }

  public static func isValid(code: String) -> Bool {
    code.count == codeLength && code.allSatisfy(alphabet.contains)
  }

  /// Builds before the App Group kept pairing in `legacy`. A new device ID would be turned away
  /// from a full room, so it has to carry over.
  public static func saved(
    in defaults: UserDefaults = sharedDefaults, legacy: UserDefaults = .standard
  ) -> DemoRoom? {
    if defaults.string(forKey: deviceKey) == nil {
      defaults.set(legacy.string(forKey: codeKey), forKey: codeKey)
      defaults.set(legacy.string(forKey: deviceKey), forKey: deviceKey)
    }
    guard let code = defaults.string(forKey: codeKey),
      let device = defaults.string(forKey: deviceKey)
    else { return nil }
    return DemoRoom(code: code, device: device)
  }

  /// Stores `code`, keeping the device ID from any earlier pairing.
  public static func pair(code: String, in defaults: UserDefaults = sharedDefaults) -> DemoRoom {
    let device = defaults.string(forKey: deviceKey) ?? UUID().uuidString.lowercased()
    defaults.set(code, forKey: codeKey)
    defaults.set(device, forKey: deviceKey)
    return DemoRoom(code: code, device: device)
  }

  public static func forget(in defaults: UserDefaults = sharedDefaults) {
    defaults.removeObject(forKey: codeKey)
  }

  public static func pushToken(in defaults: UserDefaults = sharedDefaults) -> String? {
    defaults.string(forKey: pushTokenKey)
  }

  public static func savePushToken(_ token: String, in defaults: UserDefaults = sharedDefaults) {
    defaults.set(token, forKey: pushTokenKey)
  }

  public func socketURL(host: String) -> URL? {
    let scheme = host.hasPrefix("127.0.0.1") ? "ws" : "wss"
    return URL(string: "\(scheme)://\(host)/demo/rooms/\(code)/socket?device=\(device)")
  }

  /// The URL to fetch the note a push points at, or `nil` if `noteURL` is not this room's.
  public func noteRequestURL(noteURL: String) -> URL? {
    guard var components = URLComponents(string: noteURL), components.scheme == "https",
      components.path.hasPrefix("/demo/rooms/\(code)/notes/")
    else { return nil }
    components.queryItems = [URLQueryItem(name: "device", value: device)]
    return components.url
  }

  /// Saves the note a push points at as the latest note image, and reports whether it did.
  public func saveNote(
    noteURL: String, session: URLSession = .shared, to file: URL? = NoteImage.latestFile
  ) async -> Bool {
    struct StoredNote: Decodable {
      let ink: String
    }
    guard let url = noteRequestURL(noteURL: noteURL),
      let (data, response) = try? await session.data(from: url),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let note = try? JSONDecoder().decode(StoredNote.self, from: data),
      let strokes = try? NoteInk.decode(note.ink)
    else { return false }
    return NoteImage.saveLatest(strokes, to: file)
  }
}
