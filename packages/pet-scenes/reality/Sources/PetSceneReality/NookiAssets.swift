import Foundation
import OSLog
import Pet
import RealityKit

/// Loads the room's models from compiled files, which open in a fraction of the time USD takes:
/// one for all the furniture, and one for each cat. The furniture's compiled file falls back to its
/// USD file if it will not open, so the room is never lost to a build tool's output.
@MainActor
final class NookiAssets {
  private var room: Task<Entity?, Never>?
  /// The generated props, in a file of their own: models named `Idol_…`.
  private var idolProps: Task<Entity?, Never>?
  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "NookiAssets")
  private static let roomName = "Room"

  /// The named model, ready to be added to a scene.
  func model(_ name: String) async throws(NookiLoadError) -> Entity {
    if name.hasPrefix("Idol_") {
      if idolProps == nil { idolProps = Task { await Self.compiled(GenzKit.idolFile) } }
      guard let piece = await idolProps?.value?.findEntity(named: name) else {
        throw .unreadable(name, reason: "not in \(GenzKit.idolFile)")
      }
      piece.removeFromParent()
      return piece
    }
    if room == nil {
      room = Task { try? await Self.whole(Self.roomName) }
    }
    guard let piece = await room?.value?.findEntity(named: name) else {
      throw .unreadable(name, reason: "not in \(Self.roomName)")
    }
    piece.removeFromParent()
    return piece
  }

  /// A cat from its compiled file, or nil when the file is missing or will not open, so the room
  /// can show the standard cat instead.
  static func compiledCat(_ model: CatModel) async -> Entity? {
    let name = CatCatalog.resourceName(model)
    guard
      let url = Bundle.module.url(
        forResource: name, withExtension: "reality", subdirectory: CatCatalog.folder)
    else {
      log.error("No file for cat \(name, privacy: .public)")
      return nil
    }
    do {
      let cat = try await Entity(contentsOf: url)
      SplatCat.dress(cat, as: model)
      CatSoftEdge.dress(cat, as: model)
      return cat
    } catch {
      log.error("\(name, privacy: .public): \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  private static func whole(_ name: String) async throws(NookiLoadError) -> Entity {
    if let compiled = await compiled(name) { return compiled }
    log.error("Falling back to USD for \(name, privacy: .public)")
    do {
      return try await Entity(named: name, in: .module)
    } catch {
      throw .unreadable(name, reason: String(describing: error))
    }
  }

  static func compiled(_ name: String) async -> Entity? {
    guard let url = Bundle.module.url(forResource: name, withExtension: "reality") else {
      return nil
    }
    do {
      return try await Entity(contentsOf: url)
    } catch {
      log.error("\(name, privacy: .public): \(String(describing: error), privacy: .public)")
      return nil
    }
  }
}

typealias NookiModelLoader = @MainActor @Sendable (String) async throws(NookiLoadError) -> Entity

enum NookiLoadError: Error, Equatable {
  case unreadable(String, reason: String)
  case noGeometry(String)
}
