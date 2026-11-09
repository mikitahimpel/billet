import Foundation

public struct AppGroupStorage: Sendable {
  /// The App Group shared by the app, the widget and the notification service.
  public static let billetIdentifier = "group.com.ourio.app"

  public var read: @Sendable (_ name: String) throws(PersistenceError) -> Data?
  public var write: @Sendable (_ name: String, _ data: Data) throws(PersistenceError) -> Void
  public var remove: @Sendable (_ name: String) throws(PersistenceError) -> Void

  public init(
    read: @escaping @Sendable (_ name: String) throws(PersistenceError) -> Data?,
    write: @escaping @Sendable (_ name: String, _ data: Data) throws(PersistenceError) -> Void,
    remove: @escaping @Sendable (_ name: String) throws(PersistenceError) -> Void
  ) {
    self.read = read
    self.write = write
    self.remove = remove
  }

  /// Storage in `directory`. Names are plain file names, never paths.
  public static func directory(_ directory: URL) -> AppGroupStorage {
    AppGroupStorage(
      read: { name throws(PersistenceError) -> Data? in
        let url = try file(name, in: directory)
        do {
          return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
          return nil
        } catch {
          throw .storage(error.localizedDescription)
        }
      },
      write: { name, data throws(PersistenceError) in
        let url = try file(name, in: directory)
        do {
          try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
          try data.write(to: url, options: .atomic)
        } catch {
          throw .storage(error.localizedDescription)
        }
      },
      remove: { name throws(PersistenceError) in
        let url = try file(name, in: directory)
        do {
          try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
          return
        } catch {
          throw .storage(error.localizedDescription)
        }
      }
    )
  }

  private static func file(
    _ name: String, in directory: URL
  ) throws(PersistenceError) -> URL {
    guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
      throw .invalidName(name)
    }
    return directory.appending(path: name, directoryHint: .notDirectory)
  }

  /// Storage in the container of the App Group `identifier`.
  public static func appGroup(identifier: String) throws(PersistenceError) -> AppGroupStorage {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: identifier)
    else {
      throw .appGroupUnavailable(identifier)
    }
    return directory(container)
  }
}

extension AppGroupStorage {
  public func readJSON<Value: Decodable>(
    _ type: Value.Type, named name: String
  ) throws(PersistenceError) -> Value? {
    guard let data = try read(name) else { return nil }
    do {
      return try JSONDecoder().decode(Value.self, from: data)
    } catch {
      throw .corrupted(name)
    }
  }

  public func writeJSON<Value: Encodable>(
    _ value: Value, named name: String
  ) throws(PersistenceError) {
    let data: Data
    do {
      data = try JSONEncoder().encode(value)
    } catch {
      throw .storage("could not encode \(name)")
    }
    try write(name, data)
  }
}
