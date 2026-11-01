import Pet
import PetScene
import RealityKit
import SwiftUI

struct NookiView: View {
  let world: PetWorld
  let onEvent: @MainActor (PetSceneEvent) -> Void

  @State private var diorama = NookiDiorama()
  @State private var lastDrag = CGSize.zero
  @State private var lastPinch: CGFloat = 1
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    RealityView { content in
      content.camera = .virtual
      content.add(diorama.root)
      await diorama.load()
      diorama.startUpdates(from: content)
    }
    .ignoresSafeArea()
    .simultaneousGesture(orbit)
    .simultaneousGesture(pinch)
    .simultaneousGesture(TapGesture(count: 2).onEnded { diorama.returnCameraHome() })
    .accessibilityElement()
    .accessibilityLabel("Mochi's room")
    .onChange(of: reduceMotion, initial: true) { _, reduced in
      diorama.setReduceMotion(reduced)
    }
    .onChange(of: world, initial: true) { _, world in
      diorama.show(world)
    }
    .task(id: world.step) {
      await NookiChoreography.pacing.play(world, onEvent: onEvent)
    }
  }

  private var orbit: some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { value in
        diorama.orbit(
          byX: Float(value.translation.width - lastDrag.width),
          y: Float(value.translation.height - lastDrag.height))
        lastDrag = value.translation
      }
      .onEnded { value in
        lastDrag = .zero
        diorama.endOrbit(
          velocityX: Float(value.velocity.width), velocityY: Float(value.velocity.height))
      }
  }

  private var pinch: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        diorama.zoom(by: Float(value.magnification / lastPinch))
        lastPinch = value.magnification
      }
      .onEnded { _ in
        lastPinch = 1
        diorama.endZoom()
      }
  }
}
