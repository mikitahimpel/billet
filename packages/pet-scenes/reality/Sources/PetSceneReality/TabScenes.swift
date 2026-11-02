import Pet
import PetScene
import SwiftUI

/// The shop tab's scene: the keeper behind the counter and the catalog on the shelves.
struct ShopSceneView: View {
  let state: ShopSceneState
  let stages: TabStages
  let onEvent: @MainActor (ShopSceneEvent) -> Void

  var body: some View {
    let stage = stages.shopStage
    TabSceneView(stage: stage)
      .onChange(of: state, initial: true) { _, state in
        stage.onPick = { onEvent(.picked($0)) }
        stage.show(state)
      }
      .accessibilityElement()
      .accessibilityLabel("The shop. \(state.keeper.title) behind the counter.")
      .accessibilityHint("Things for sale are on the shelves, the counter and the table.")
      .accessibilityActions {
        ForEach(state.items) { item in
          Button("Look at \(item.name)") { onEvent(.picked(item.id)) }
        }
      }
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
          : "A desk with blank paper under a board of \(state.notes.count) notes.")
      .accessibilityActions {
        Button("Draw a note") { onEvent(.paperTapped) }
        if let latest = state.notes.first {
          Button("Open the latest note") { onEvent(.noteTapped(latest.id)) }
        }
      }
  }
}
