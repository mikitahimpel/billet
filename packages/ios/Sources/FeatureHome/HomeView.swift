import BilletKit
import CoreGraphics
import DesignSystem
import FeatureCanvas
import Foundation
import Ink
import Pet
import PetScene
import SwiftUI

/// The main screen: the chosen pet scene, and the way into the canvas.
struct HomeView: View {
  @State private var hungImage: CGImage?
  @State private var hangCount = 0
  @State private var petBounce = false

  let session: PairSession
  let scene: (any PetScene)?
  let onChangeCode: () -> Void

  private var store: Store<HomeMachine> { session.store }

  private var line: ConnectionLine {
    ConnectionLine(status: session.status, hasConnected: session.hasConnected)
  }

  private var noteArrived: Bool { store.state.pet.world.noteArrived }

  var body: some View {
    home
      .animation(Motion.gentle, value: line)
      .task { await DemoPush.requestPermission() }
      .onReceive(NotificationCenter.default.publisher(for: DemoPush.tokenDidChange)) { _ in
        Task { await session.pushTokenChanged() }
      }
      .task(id: noteArrived) {
        guard noteArrived, let wall = scene?.noteWall else { return }
        hungImage = nil
        try? await Task.sleep(for: wall.revealDelay)
        guard !Task.isCancelled, let drawing = store.state.hungDrawing else { return }
        hungImage = NoteImage.cgImage(of: drawing)
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

  private var home: some View {
    ZStack {
      VStack(spacing: 0) {
        Palette.sky.color
        Palette.meadow.color
      }
      .ignoresSafeArea()
      VStack(spacing: Spacing.small) {
        roomStatus
        petScene
          .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
          .layoutPriority(-1)
        controls
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.bottom, Spacing.small)
    }
  }

  @ViewBuilder private var petScene: some View {
    if let scene {
      scene.makeView(world: store.state.pet.world) { store.send(.pet(PetMachine.Event($0))) }
        .id(scene.id)
        .scaleEffect(petBounce ? 1.015 : 1)
        .animation(Motion.settle, value: petBounce)
        .overlay { petTapTarget }
        .overlay { catReactions }
        .overlay {
          if let hungImage, let wall = scene.noteWall {
            HungNote(drawing: hungImage, wall: wall)
              .id(hangCount)
          }
        }
    }
  }

  private var controls: some View {
    VStack(spacing: Spacing.small) {
      if session.notes.isEmpty, !session.notesFailedToLoad {
        Text("The wall is empty. Draw the first note.")
          .billetType(.label)
          .foregroundStyle(Palette.paperTurned.color)
          .multilineTextAlignment(.center)
      }
      treatPanel
      Button("Draw a note") { store.send(.canvasOpened) }
        .buttonStyle(PrimaryButtonStyle())
    }
    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
  }

  /// The cat's middle third. A tap pets it on this phone and tells the partner's.
  private var petTapTarget: some View {
    Color.clear
      .contentShape(Rectangle())
      .padding(.horizontal, 60)
      .padding(.vertical, 140)
      .onTapGesture {
        session.pet()
        petBounce.toggle()
      }
      .accessibilityLabel("Pet the cat")
      .accessibilityAddTraits(.isButton)
  }

  private var catReactions: some View {
    ZStack {
      HeartBurst(trigger: session.play.petsGiven)
      HeartBurst(trigger: session.play.petsReceived, size: 18, tint: Palette.light.color)
        .offset(x: 40, y: -30)
      TreatDrop(trigger: session.treatFalling)
    }
  }

  private var treatPanel: some View {
    TimelineView(.everyMinute) { context in
      let calendar = Calendar.current
      let day = TreatDay.key(for: context.date, calendar: calendar)
      TreatPanel(
        status: session.play.status(on: day),
        streak: session.play.streak(today: day, calendar: calendar),
        onGive: { session.giveTreat(on: day) }
      )
    }
  }

  private var roomStatus: some View {
    VStack(spacing: Spacing.small) {
      statusPill
      if line == .refused {
        Button("Change code", action: onChangeCode)
          .buttonStyle(InlineButtonStyle())
      }
    }
    .padding(.top, Spacing.small)
    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
  }

  private var statusPill: some View {
    HStack(spacing: Spacing.small) {
      Circle()
        .fill(statusLight.color)
        .frame(width: 8, height: 8)
        .shadow(color: statusLight.color.opacity(0.8), radius: 4)
        .accessibilityHidden(true)
      Text(line.text)
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.vertical, Spacing.small)
    .litPanel(cornerRadius: Radius.control)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("connectionStatus")
  }

  private var statusLight: Swatch {
    switch line {
    case .partnerHere: Palette.gold
    case .partnerAway: Palette.muted
    case .connecting, .reconnecting: Palette.woodLit
    case .refused: Palette.clayLit
    }
  }
}
