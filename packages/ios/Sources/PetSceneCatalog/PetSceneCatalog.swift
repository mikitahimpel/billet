import Foundation
import OSLog
import Observation
import Persistence
import Pet
import PetScene

/// The scenes this build links and which one the user chose.
///
/// The choice is kept in `defaults`. A stored id whose scene is no longer linked falls back to the
/// first scene and stays stored, so it applies again if that scene comes back. Choosing a scene
/// publishes its poses to `poses`, the storage the widget reads.
@MainActor
@Observable
public final class PetSceneCatalog {
  public static let choiceKey = "petScene.selectedID"

  public let scenes: [any PetScene]
  public private(set) var selectedID: String?

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let poses: AppGroupStorage?
  @ObservationIgnored private let onPosesPublished: @MainActor () -> Void

  public init(
    scenes: [any PetScene],
    defaults: UserDefaults,
    poses: AppGroupStorage?,
    onPosesPublished: @escaping @MainActor () -> Void = {}
  ) {
    self.scenes = scenes
    self.defaults = defaults
    self.poses = poses
    self.onPosesPublished = onPosesPublished
    let stored = defaults.string(forKey: Self.choiceKey)
    selectedID = scenes.first { $0.id == stored }?.id ?? scenes.first?.id
    publishPoses()
  }

  public var selected: (any PetScene)? {
    scenes.first { $0.id == selectedID }
  }

  /// Ignores an id no linked scene has.
  public func select(_ id: String) {
    guard id != selectedID, scenes.contains(where: { $0.id == id }) else { return }
    selectedID = id
    defaults.set(id, forKey: Self.choiceKey)
    publishPoses()
  }

  private func publishPoses() {
    guard let poses, let selected else { return }
    do {
      for pose in PetPose.allCases {
        if let png = selected.posePNG(pose) {
          try poses.write(pose.fileName, png)
        } else {
          try poses.remove(pose.fileName)
        }
      }
    } catch {
      Self.log.error("Publishing pet poses failed: \(String(describing: error))")
    }
    onPosesPublished()
  }

  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "PetSceneCatalog")
}
