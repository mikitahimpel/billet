import BilletKit
import CoreGraphics
import FeatureCanvas
import Ink
import SwiftUI

/// The main screen: the Little House with its cat, and the way into the canvas.
public struct HomeView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var store: Store<HomeMachine>
  @State private var delivery: NoteDelivery
  @State private var scene = LittleHouseScene()
  @State private var status = NoteDelivery.Status.connecting
  @State private var hungImage: CGImage?
  @State private var hangCount = 0

  private let code: String
  private let onChangeCode: () -> Void

  public init(delivery: NoteDelivery, code: String, onChangeCode: @escaping () -> Void) {
    _delivery = State(initialValue: delivery)
    _store = State(
      initialValue: Store(
        initial: HomeMachine.State(),
        run: { await HomeRunner.run($0, delivery: delivery) }
      ))
    self.code = code
    self.onChangeCode = onChangeCode
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
    .task { await DemoPush.requestPermission() }
    .onReceive(NotificationCenter.default.publisher(for: DemoPush.tokenDidChange)) { _ in
      Task { await delivery.pushTokenChanged() }
    }
    .task(id: scenePhase == .active) {
      guard scenePhase == .active else { return }
      for await update in delivery.updates() {
        switch update {
        case .status(let newStatus): status = newStatus
        case .note(let strokes): store.send(.noteReceived(strokes))
        }
      }
    }
    .task(id: store.state.noteArrived) {
      guard store.state.noteArrived else { return }
      hungImage = nil
      try? await Task.sleep(for: HungNote.revealDelay)
      guard !Task.isCancelled, let drawing = store.state.hungDrawing else { return }
      hungImage = NoteImage.cgImage(of: drawing)
      hangCount += 1
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
          .overlay {
            if let hungImage {
              HungNote(drawing: hungImage)
                .id(hangCount)
            }
          }
      }
      Button("Draw a note") { store.send(.canvasOpened) }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Self.door)
        .padding(.bottom, 24)
    }
    .overlay(alignment: .top) { roomStatus }
    .accessibilityHidden(store.state.screen == .canvas)
  }

  private var roomStatus: some View {
    VStack(spacing: 8) {
      Text(statusText)
        .font(.footnote.monospaced())
        .foregroundStyle(.white)
      if status != .partnerHere {
        Button("Change code", action: onChangeCode)
          .font(.footnote)
          .tint(.white)
      }
    }
    .padding(.top, 8)
  }

  private var statusText: String {
    switch status {
    case .connecting: "Connecting…"
    case .partnerAway: "Waiting for partner · \(code)"
    case .partnerHere: "Partner here"
    case .refused: "This room is full"
    }
  }

  // The artboard's top and bottom edge colours, so the art runs on into the taller screen.
  private static let sky = Color(red: 0x0E / 255, green: 0x2E / 255, blue: 0x2A / 255)
  private static let hill = Color(red: 0x14 / 255, green: 0x3B / 255, blue: 0x33 / 255)
  private static let door = Color(red: 0.78, green: 0.3, blue: 0.16)
}
