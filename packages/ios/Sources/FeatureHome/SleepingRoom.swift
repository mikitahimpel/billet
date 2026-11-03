import Pet
import PetScene
import SwiftUI
import WidgetBridge

/// The chosen scene with its cat asleep and nothing to touch, dressed in the room, cat and light
/// chosen in Labs, the way Home dresses it.
struct SleepingRoom: View {
  let scene: any PetScene
  let labs: WidgetFeaturesModel

  var body: some View {
    scene.makeView(world: PetWorld(activity: .sleeping), onEvent: { _ in })
      .environment(\.petSceneCat, labs.cat)
      .environment(\.petSceneWindowView, labs.windowView)
      .environment(\.petSceneLighting, labs.lighting)
      .environment(\.petSceneFurniture, labs.furniture)
      .environment(\.petSceneRoomStyle, labs.roomStyle)
      .environment(\.petSceneShowsControls, false)
  }
}
