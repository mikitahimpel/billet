import BilletKit
import FeatureCanvas
import SwiftUI

/// The main screen: the Little House with its cat, and the way into the canvas.
public struct HomeView: View {
  @State private var store: Store<HomeMachine>
  @State private var scene = LittleHouseScene()

  public init(delivery: NoteDelivery = .localFake) {
    _store = State(
      initialValue: Store(
        initial: HomeMachine.State(),
        run: { await HomeRunner.run($0, delivery: delivery) }
      ))
  }

  public var body: some View {
    ZStack {
      house
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
    .onChange(of: store.state.noteArrived) { _, arrived in
      scene?.setNoteArrived(arrived)
    }
  }

  private var house: some View {
    ZStack(alignment: .bottom) {
      VStack(spacing: 0) {
        Self.sky
        Self.hill
      }
      .ignoresSafeArea()
      if let scene {
        scene.view
          .accessibilityLabel("Little House with the cat")
      }
      Button("Draw a note") { store.send(.canvasOpened) }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Self.door)
        .padding(.bottom, 24)
    }
    .accessibilityHidden(store.state.screen == .canvas)
  }

  // The artboard's top and bottom edge colours, so the art runs on into the taller screen.
  private static let sky = Color(red: 0x0E / 255, green: 0x2E / 255, blue: 0x2A / 255)
  private static let hill = Color(red: 0x14 / 255, green: 0x3B / 255, blue: 0x33 / 255)
  private static let door = Color(red: 0.78, green: 0.3, blue: 0.16)
}
