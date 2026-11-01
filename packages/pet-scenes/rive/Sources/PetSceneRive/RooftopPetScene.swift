import CoreGraphics
import Foundation
import Pet
import PetScene
import SwiftUI

/// The Rooftop: an evening for two under the stars, with the cat, the lights and the note line.
public struct RooftopPetScene: PetScene {
  public let id = "rooftop"
  public let title = "Rooftop"

  /// Mirrors the `NoteNew` node. Frame 640 of Deliver at 60 fps is when it first shows.
  public let noteWall: PetSceneNoteWall? = PetSceneNoteWall(
    artboard: CGSize(width: 780, height: 980),
    paper: CGRect(x: 336, y: 545, width: 112, height: 138),
    peg: CGPoint(x: 392, y: 536),
    revealDelay: .seconds(640.0 / 60.0))

  public init() {}

  /// Mirrors the animation lengths in `Rooftop.riv`. Deliver runs 790 frames at 60 fps, then the
  /// cat sits proudly for one 4 s Proud loop. Settle runs 180 frames at 60 fps.
  static let pacing = PetScenePacing(
    delivery: .seconds(790.0 / 60.0 + 4),
    settling: .seconds(180.0 / 60.0))

  public func makeView(
    world: PetWorld,
    onEvent: @escaping @MainActor (PetSceneEvent) -> Void
  ) -> AnyView {
    AnyView(RooftopView(world: world, onEvent: onEvent))
  }

  public func posePNG(_ pose: PetPose) -> Data? {
    guard
      let url = Bundle.module.url(
        forResource: "rooftop-pose-\(pose.rawValue)", withExtension: "png")
    else { return nil }
    return try? Data(contentsOf: url)
  }
}

private struct RooftopView: View {
  let world: PetWorld
  let onEvent: @MainActor (PetSceneEvent) -> Void

  @State private var rive = PetWorldRive(fileName: "Rooftop", artboardName: "Rooftop")

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        Self.sky
        Self.street
      }
      .ignoresSafeArea()
      if let rive {
        rive.view
          .accessibilityLabel("A rooftop at night with the cat")
      }
    }
    .onChange(of: world.noteArrived, initial: true) { _, arrived in
      rive?.setNoteArrived(arrived)
    }
    .task(id: world) {
      await RooftopPetScene.pacing.play(world, onEvent: onEvent)
    }
  }

  // The artboard's top and bottom edge colours, so the art runs on into the taller screen.
  private static let sky = Color(red: 0x0E / 255, green: 0x2E / 255, blue: 0x2A / 255)
  private static let street = Color(red: 0x14 / 255, green: 0x3B / 255, blue: 0x33 / 255)
}
