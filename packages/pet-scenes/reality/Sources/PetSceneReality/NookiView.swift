import Pet
import PetScene
import RealityKit
import SwiftUI

struct NookiView: View {
  let world: PetWorld
  let onEvent: @MainActor (PetSceneEvent) -> Void

  @State private var diorama = NookiDiorama()

  var body: some View {
    RealityView { content in
      content.camera = .virtual
      content.add(diorama.root)
      content.add(Self.camera)
      await diorama.load()
      diorama.startUpdates(from: content)
    }
    .ignoresSafeArea()
    .background(Self.backdrop)
    .accessibilityElement()
    .accessibilityLabel("Mochi's room")
    .onChange(of: world, initial: true) { _, world in
      diorama.show(world)
    }
    .task(id: world) {
      await NookiChoreography.pacing.play(world, onEvent: onEvent)
    }
  }

  private static let backdrop = Color(red: 0.13, green: 0.16, blue: 0.23)

  /// A long lens from far away keeps the room nearly isometric on a tall screen.
  private static var camera: Entity {
    let camera = PerspectiveCamera()
    camera.camera.fieldOfViewInDegrees = 30
    let target: SIMD3<Float> = [0, 0.3, 0]
    let direction = simd_normalize(SIMD3<Float>(0.8, 0.75, 1))
    camera.look(at: target, from: target + direction * 8, relativeTo: nil)
    return camera
  }
}
