import Foundation
import PetScene
import RealityKit
import SwiftUI

/// A tab's stage that can be built before its tab opens.
@MainActor
protocol RehearsedStage: TabStage {
  var isBuilt: Bool { get }
  /// Builds the scene if it is not yet, and shows it whole while it is copied for a rehearsal.
  func setRehearsing(_ rehearsing: Bool)
}

/// Draws the shop and the desk once each, out of sight, so that the engine's costly first draw of
/// a scene (its shaders, meshes and textures) happens before anyone opens the tab. Until a scene
/// has been drawn the renderer shows nothing for a second or more.
///
/// It draws a copy of each stage, which shares the stage's meshes and materials: a RealityView
/// that takes over entities another RealityView still holds can stay empty for good, and SwiftUI
/// can keep a RealityView long after it leaves. The copy is dropped when the rehearsal ends, and
/// each stage is rehearsed at most once per launch.
struct TabRehearsal: View {
  let stages: TabStages
  let shop: ShopSceneState?
  let desk: Bool

  @Environment(\.petSceneLighting) private var lighting
  @State private var copy: Entity?

  var body: some View {
    ZStack {
      if let copy {
        RealityView { content in
          content.camera = .virtual
          content.add(copy)
        }
        .id(ObjectIdentifier(copy))
      }
    }
    .task {
      guard Self.isWanted else { return }
      var queue: [any RehearsedStage] = []
      if shop != nil { queue.append(stages.shopStage) }
      if desk { queue.append(stages.deskStage) }
      for stage in queue {
        guard !Task.isCancelled else { break }
        // A stage its tab already shows has had its first draw.
        guard stages.claimRehearsal(of: stage), stage.root.scene == nil else { continue }
        if let shop, let shopStage = stage as? ShopStage { shopStage.show(shop) }
        stage.setLighting(.of(lighting))
        stage.setRehearsing(true)
        await Self.until { stage.isBuilt }
        // The stock, the keeper and the cat load after the room; their first draws belong here
        // too.
        try? await Task.sleep(for: Self.loads)
        copy = stage.root.clone(recursive: true)
        stage.setRehearsing(false)
        try? await Task.sleep(for: Self.drawn)
      }
      copy = nil
    }
  }

  /// Not under Low Power Mode, and not while a cold launch is measured.
  private static var isWanted: Bool {
    !ProcessInfo.processInfo.isLowPowerModeEnabled && ScenePerf.script != "launch"
  }

  private static func until(_ done: () -> Bool) async {
    let deadline = ContinuousClock.now + longestBuild
    while !done(), ContinuousClock.now < deadline, !Task.isCancelled {
      try? await Task.sleep(for: check)
    }
  }

  private static let check = Duration.milliseconds(50)
  private static let longestBuild = Duration.seconds(10)
  private static let loads = Duration.seconds(2.5)
  private static let drawn = Duration.seconds(1.5)
}
