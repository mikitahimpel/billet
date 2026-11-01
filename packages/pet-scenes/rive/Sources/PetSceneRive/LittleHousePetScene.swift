import Foundation
import Pet
import PetScene
import SwiftUI

/// The Little House: the Rive cat in a flat house at night.
public struct LittleHousePetScene: PetScene {
  public let id = "little-house"
  public let title = "Little House"

  public init() {}

  /// Mirrors the animation lengths in `LittleHouse.riv`. Deliver runs 590 frames at 60 fps, then
  /// the cat sits proudly for one 4 s Proud loop. Settle runs 150 frames at 60 fps.
  static let pacing = PetScenePacing(
    delivery: .seconds(590.0 / 60.0 + 4),
    settling: .seconds(150.0 / 60.0))

  public func makeView(
    world: PetWorld,
    onEvent: @escaping @MainActor (PetSceneEvent) -> Void
  ) -> AnyView {
    AnyView(LittleHouseView(world: world, onEvent: onEvent))
  }

  public func posePNG(_ pose: PetPose) -> Data? {
    guard
      let url = Bundle.module.url(forResource: "pose-\(pose.rawValue)", withExtension: "png")
    else { return nil }
    return try? Data(contentsOf: url)
  }
}

private struct LittleHouseView: View {
  let world: PetWorld
  let onEvent: @MainActor (PetSceneEvent) -> Void

  @State private var rive = PetWorldRive(fileName: "LittleHouse", artboardName: "LittleHouse")

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        Self.sky
        Self.hill
      }
      .ignoresSafeArea()
      if let rive {
        rive.view
          .accessibilityLabel("Little House with the cat")
      }
    }
    .onChange(of: world.noteArrived, initial: true) { _, arrived in
      rive?.setNoteArrived(arrived)
    }
    .task(id: world) {
      await LittleHousePetScene.pacing.play(world, onEvent: onEvent)
    }
  }

  // The artboard's top and bottom edge colours, so the art runs on into the taller screen.
  private static let sky = Color(red: 0x0E / 255, green: 0x2E / 255, blue: 0x2A / 255)
  private static let hill = Color(red: 0x14 / 255, green: 0x3B / 255, blue: 0x33 / 255)
}
