import Pet
import PetScene
import SwiftUI

/// The shop tab's scene: the keeper behind the counter and the catalog on the shelves, each with
/// its price tag, and the room's own window view through the shop window.
struct ShopSceneView: View {
  let state: ShopSceneState
  let stages: TabStages
  let onEvent: @MainActor (ShopSceneEvent) -> Void

  @Environment(\.petSceneWindowView) private var windowView
  @Environment(\.petSceneDayLight) private var dayLight
  @Environment(\.petSceneViewArt) private var viewArt
  @Environment(\.petSceneOnScreen) private var onScreen
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var plates = ViewPlateCache()

  var body: some View {
    let stage = stages.shopStage
    TabSceneView(
      stage: stage, behind: AnyView(outside(stage)),
      overlay: AnyView(
        ShopTagLayer(screen: stage.shopScreen) { stage.pick($0) })
    )
    .onChange(of: state, initial: true) { _, state in
      stage.onPick = { onEvent(.picked($0)) }
      stage.show(state)
    }
    .accessibilityElement()
    .accessibilityLabel("The shop. \(state.keeper.title) behind the counter.")
    .accessibilityHint("Everything on the shelves, the counter and the table is for sale.")
    .accessibilityActions {
      ForEach(state.items) { item in
        Button("Look at \(item.name), \(item.price) stamps") { onEvent(.picked(item.id)) }
      }
    }
  }

  /// The view through the shop window: the room's window view, in its weather and hour, seen
  /// only through the opening.
  private func outside(_ stage: ShopStage) -> some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: !onScreen || reduceMotion)) {
      context in
      let state = stage.windowState(choice: windowView, dayLight: dayLight, at: context.date)
      Group {
        if let art = viewArt?.view(state.view, state: state) {
          art
        } else {
          NativeWindowView(state: state, plates: plates)
        }
      }
      .clipShape(Opening(points: state.window))
      .opacity(state.window.isEmpty ? 0 : 1)
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// The notes tab's scene: paper on the desk to draw on, the notes pinned on the board above.
struct DeskSceneView: View {
  let state: DeskSceneState
  let stages: TabStages
  let onEvent: @MainActor (DeskSceneEvent) -> Void

  @Environment(\.petSceneCat) private var cat

  var body: some View {
    let stage = stages.deskStage
    TabSceneView(stage: stage)
      .onChange(of: state, initial: true) { _, state in
        stage.onEvent = { onEvent($0) }
        stage.show(state)
      }
      .onChange(of: cat, initial: true) { _, cat in stage.setCat(cat) }
      .accessibilityElement()
      .accessibilityLabel(
        state.notes.isEmpty
          ? "A desk with blank paper under an empty board."
          : "A desk with blank paper under a board of \(state.notes.count) notes."
      )
      .accessibilityActions {
        Button("Draw a note") { onEvent(.paperTapped) }
        if let latest = state.notes.first {
          Button("Open the latest note") { onEvent(.noteTapped(latest.id)) }
        }
      }
  }
}

/// The first-launch scene: a soft heart over candles on a windowsill at night.
struct OnboardingSceneView: View {
  let state: OnboardingSceneState
  let stages: TabStages
  let onEvent: @MainActor (OnboardingSceneEvent) -> Void

  var body: some View {
    let stage = stages.onboardingStage
    TabSceneView(stage: stage)
      .onAppear {
        stage.onEvent = { onEvent($0) }
        stage.begin(state)
      }
      .onChange(of: state) { _, state in
        stage.onEvent = { onEvent($0) }
        stage.show(state)
      }
      .accessibilityElement()
      .accessibilityLabel("A soft red heart floating over candles on a windowsill at night.")
  }
}
