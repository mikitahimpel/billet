import BilletKit
import CoreGraphics
import DesignSystem
import FeatureCanvas
import SwiftUI

/// The main screen: the Little House with its cat, and the way into the canvas.
struct HomeView: View {
  @State private var scene = LittleHouseScene()
  @State private var hungImage: CGImage?
  @State private var hangCount = 0

  let session: PairSession
  let onChangeCode: () -> Void

  private var store: Store<HomeMachine> { session.store }

  private var line: ConnectionLine {
    ConnectionLine(status: session.status, hasConnected: session.hasConnected)
  }

  var body: some View {
    house
      .animation(.easeInOut(duration: 0.25), value: line)
      .onChange(of: store.state.noteArrived) { _, arrived in
        scene?.setNoteArrived(arrived)
      }
      .task(id: store.state.noteArrived) {
        guard store.state.noteArrived else { return }
        hungImage = nil
        try? await Task.sleep(for: HungNote.revealDelay)
        guard !Task.isCancelled, let drawing = store.state.hungDrawing else { return }
        hungImage = HungNote.image(of: drawing)
        hangCount += 1
      }
      #if os(iOS)
        .fullScreenCover(isPresented: canvasPresented) {
          CanvasView(
            onClose: { store.send(.canvasClosed) },
            onSend: { session.send($0) }
          )
          .background(Palette.page.color)
        }
      #endif
  }

  private var canvasPresented: Binding<Bool> {
    Binding(
      get: { store.state.screen == .canvas },
      set: { if !$0 { store.send(.canvasClosed) } }
    )
  }

  private var house: some View {
    ZStack(alignment: .bottom) {
      VStack(spacing: 0) {
        Self.sky
        Self.hill
      }
      .ignoresSafeArea(edges: .top)
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
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, Spacing.medium)
    }
    .overlay(alignment: .top) { roomStatus }
  }

  private var roomStatus: some View {
    VStack(spacing: Spacing.small) {
      statusPill
      if line == .refused {
        Button("Change code", action: onChangeCode)
          .billetType(.label)
          .foregroundStyle(Palette.paper.color)
          .frame(minHeight: Target.minimum)
      }
      if session.notes.isEmpty, !session.notesFailedToLoad {
        emptyHint
      }
    }
    .padding(.top, Spacing.small)
    .padding(.horizontal, Spacing.medium)
  }

  private var statusPill: some View {
    Text(line.text)
      .billetType(.label)
      .foregroundStyle(Palette.paper.color)
      .multilineTextAlignment(.center)
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.small)
      .background(Palette.plate.color, in: .rect(cornerRadius: Radius.control))
      .accessibilityIdentifier("connectionStatus")
  }

  private var emptyHint: some View {
    VStack(spacing: Spacing.hair) {
      Text("The wall is empty")
        .billetType(.heading)
        .foregroundStyle(Palette.paper.color)
      Text("Draw the first note. It will hang here when your partner sends one back.")
        .billetType(.label)
        .foregroundStyle(Palette.paperTurned.color)
    }
    .multilineTextAlignment(.center)
    .padding(Spacing.medium)
    .background(Palette.plate.color, in: .rect(cornerRadius: Radius.control))
    .accessibilityElement(children: .combine)
  }

  // The artboard's top and bottom edge colours, so the art runs on into the taller screen.
  private static let sky = Color(red: 0x0E / 255, green: 0x2E / 255, blue: 0x2A / 255)
  private static let hill = Color(red: 0x14 / 255, green: 0x3B / 255, blue: 0x33 / 255)
}
