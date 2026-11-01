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
      .animation(.easeInOut(duration: 0.25), value: line)
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
    ZStack(alignment: .bottom) {
      Palette.skyNight.color.ignoresSafeArea()
      if let scene {
        scene.makeView(world: store.state.pet.world) { store.send(.pet(PetMachine.Event($0))) }
          .id(scene.id)
          .scaleEffect(petBounce ? 1.03 : 1)
          .animation(.spring(duration: 0.3, bounce: 0.6), value: petBounce)
          .overlay { petTapTarget }
          .overlay { catReactions }
          .overlay {
            if let hungImage, let wall = scene.noteWall {
              HungNote(drawing: hungImage, wall: wall)
                .id(hangCount)
            }
          }
      }
      VStack(spacing: Spacing.small) {
        treatPanel
        Button("Draw a note") { store.send(.canvasOpened) }
          .buttonStyle(PrimaryButtonStyle())
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.bottom, Spacing.medium)
    }
    .overlay(alignment: .top) { roomStatus }
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
      HeartBurst(trigger: session.play.petsReceived, size: 18, tint: .pink.opacity(0.8))
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
}
