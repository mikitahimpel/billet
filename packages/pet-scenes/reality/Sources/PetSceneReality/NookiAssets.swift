import Foundation
import OSLog
import RealityKit

/// Loads the room's models from their compiled files: one for Mochi and one for all the furniture,
/// which open in a fraction of the time USD takes. A compiled file that will not open falls back to
/// its USD file, so the room is never lost to a build tool's output.
@MainActor
final class NookiAssets {
  private var room: Task<Entity?, Never>?
  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "NookiAssets")
  static let mochiName = "Cat"
  private static let roomName = "Room"

  /// The named model, ready to be added to a scene.
  func model(_ name: String) async throws(NookiLoadError) -> Entity {
    if name == Self.mochiName {
      return try await Self.whole(name)
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
