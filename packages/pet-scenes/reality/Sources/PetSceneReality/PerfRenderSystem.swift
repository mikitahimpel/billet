import PetScene
import RealityKit

/// Counts RealityKit's scene updates in a measuring run.
struct PerfRenderSystem: System {
  @MainActor private static var isRegistered = false

  init(scene: RealityKit.Scene) {}

  @MainActor static func registerOnce() {
    guard ScenePerf.isOn, !isRegistered else { return }
    isRegistered = true
    registerSystem()
  }

  func update(context: SceneUpdateContext) {
    MainActor.assumeIsolated { ScenePerf.count("renders") }
  }
}
