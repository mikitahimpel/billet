import BilletKit
import FeatureCanvas
import Pet
import PetScene
import SwiftUI

/// The main screen: the chosen pet scene, and the ways into the canvas and the scene list.
public struct HomeView: View {
  private let scenes: [any PetScene]
  @Binding private var selectedSceneID: String?
  @State private var store: Store<HomeMachine>
  @State private var choosingScene = false

  public init(
    scenes: [any PetScene],
    selectedSceneID: Binding<String?>,
    delivery: NoteDelivery = .localFake
  ) {
    self.scenes = scenes
    _selectedSceneID = selectedSceneID
    _store = State(
      initialValue: Store(
        initial: HomeMachine.State(),
        run: { await HomeRunner.run($0, delivery: delivery) }
      ))
  }

  public var body: some View {
    ZStack {
      home
      if store.state.screen == .canvas {
        CanvasView(
          onClose: { store.send(.canvasClosed) },
          onSend: { store.send(.drawingSent($0)) }
        )
        .background(.background)
        .transition(.move(edge: .bottom))
      }
    }
    .animation(.easeInOut(duration: 0.25), value: store.state.screen)
    .sheet(isPresented: $choosingScene) {
      NavigationStack {
        PetScenePicker(scenes: scenes, selectedSceneID: $selectedSceneID) {
          choosingScene = false
        }
      }
      .presentationDetents([.medium])
    }
  }

  private var selectedScene: (any PetScene)? {
    scenes.first { $0.id == selectedSceneID } ?? scenes.first
  }

  private var home: some View {
    ZStack(alignment: .bottom) {
      Color.clear
      if let scene = selectedScene {
        scene.makeView(world: store.state.pet.world) { store.send(.pet(PetMachine.Event($0))) }
          .id(scene.id)
      }
      Button("Draw a note") { store.send(.canvasOpened) }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Self.action)
        .padding(.bottom, 24)
    }
    .overlay(alignment: .topTrailing) {
      if scenes.count > 1 {
        Button {
          choosingScene = true
        } label: {
          Image(systemName: "paintpalette")
            .padding(10)
            .background(.thinMaterial, in: .circle)
        }
        .tint(.primary)
        .accessibilityLabel("Choose a scene")
        .padding(16)
      }
    }
    .accessibilityHidden(store.state.screen == .canvas)
  }

  private static let action = Color(red: 0.78, green: 0.3, blue: 0.16)
}
