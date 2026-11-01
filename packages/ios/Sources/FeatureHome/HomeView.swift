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
  private static let drawButton = "draw"

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var zoom
  @State private var hungImage: CGImage?
  @State private var hangCount = 0
  @State private var petBounce = false
  @State private var showsStatus = true

  let session: PairSession
  let scene: (any PetScene)?
  let onChangeCode: () -> Void
  let onOpenNotes: () -> Void

  private var store: Store<HomeMachine> { session.store }

  private var line: ConnectionLine {
    ConnectionLine(status: session.status, hasConnected: session.hasConnected)
  }

  private var delivery: Int { store.state.pet.world.delivery }

  var body: some View {
    home
      .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: session.play.petsGiven)
      .sensoryFeedback(.success, trigger: session.treatFalling) { _, falling in falling }
      .task { await DemoPush.requestPermission() }
      .onReceive(NotificationCenter.default.publisher(for: DemoPush.tokenDidChange)) { _ in
        Task { await session.pushTokenChanged() }
      }
      .task(id: delivery) {
        guard delivery > 0, let wall = scene?.noteWall else { return }
        hungImage = nil
        try? await Task.sleep(for: wall.revealDelay)
        guard !Task.isCancelled, let drawing = store.state.hungDrawing else { return }
        hungImage = NoteImage.cgImage(of: drawing)
        hangCount += 1
      }
      .task(id: line) {
        withAnimation(Motion.spring) { showsStatus = true }
        guard line.settles else { return }
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled else { return }
        withAnimation(Motion.spring) { showsStatus = false }
      }
      #if os(iOS)
        .fullScreenCover(isPresented: canvasPresented) {
          CanvasView(
            onClose: { store.send(.canvasClosed) },
            onSend: { session.send($0) }
          )
          .navigationTransition(.zoom(sourceID: Self.drawButton, in: zoom))
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
      LinearGradient(
        stops: [
          .init(color: Palette.sky.color, location: 0.2),
          .init(color: Palette.meadow.color, location: 0.75),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
      VStack(spacing: Spacing.small) {
        petScene
          .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
          .layoutPriority(-1)
        controls
          .padding(.horizontal, Spacing.medium)
      }
      .padding(.bottom, Spacing.small)
    }
    .overlay(alignment: .top) { roomStatus }
  }

  @ViewBuilder private var petScene: some View {
    if let scene {
      scene.makeView(world: store.state.pet.world, play: playState, onEvent: handle)
        .id(scene.id)
        .environment(\.petSceneOnScreen, store.state.screen == .home)
        .transition(.opacity)
        .scaleEffect(petBounce && !reduceMotion ? 1.012 : 1)
        .calmAnimation(value: petBounce)
        .overlay {
          if !scene.handlesTouches {
            petTapTarget
          }
        }
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
          .transition(.opacity)
      }
      treatPanel
      BilletButton("Draw a note", rank: .primary) { store.send(.canvasOpened) }
        .matchedTransitionSourceIfAvailable(id: Self.drawButton, in: zoom)
    }
    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    .calmAnimation(value: session.notes.isEmpty)
  }

  /// The cat's middle third. A tap pets it on this phone and tells the partner's.
  private var petTapTarget: some View {
    Color.clear
      .contentShape(Rectangle())
      .padding(.horizontal, Spacing.page)
      .padding(.vertical, Spacing.page * 2)
      .onTapGesture(perform: pet)
      .accessibilityLabel("Pet the cat")
      .accessibilityAddTraits(.isButton)
  }

  private func pet() {
    session.pet()
    petBounce.toggle()
  }

  private func handle(_ event: PetSceneEvent) {
    if let event = PetMachine.Event(event) {
      store.send(.pet(event))
      return
    }
    switch event {
    case .petted: pet()
    case .noteOpened: onOpenNotes()
    case .deliveryFinished, .settled: break
    }
  }

  /// What the pair has done today, as the scene shows it.
  private var playState: PetPlayState {
    let calendar = Calendar.current
    let today = Date.now
    let day = TreatDay.key(for: today, calendar: calendar)
    return PetPlayState(
      treat: PetPlayState.Treat(session.play.status(on: day)),
      streak: session.play.streak(today: day, calendar: calendar),
      petsReceived: session.play.petsReceived
    )
  }

  private var catReactions: some View {
    ZStack {
      HeartBurst(trigger: session.play.petsGiven)
      HeartBurst(trigger: session.play.petsReceived, tint: Palette.light.color)
        .offset(x: Spacing.wide, y: -Spacing.wide)
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

  @ViewBuilder private var roomStatus: some View {
    if showsStatus {
      VStack(spacing: Spacing.small) {
        statusPill
        if line == .refused {
          BilletButton("Change code", rank: .secondary, action: onChangeCode)
            .frame(maxWidth: 200)
        }
      }
      .padding(.top, Spacing.small)
      .padding(.horizontal, Spacing.medium)
      .dynamicTypeSize(...DynamicTypeSize.accessibility2)
      .transition(.opacity)
    }
  }

  private var statusPill: some View {
    HStack(spacing: Spacing.small) {
      Circle()
        .fill(statusLight.color)
        .frame(width: Spacing.small, height: Spacing.small)
        .accessibilityHidden(true)
      Text(line.text)
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
        .multilineTextAlignment(.center)
        .contentTransition(.opacity)
    }
    .calmAnimation(value: line)
    .padding(.horizontal, Spacing.medium)
    .frame(minHeight: Target.minimum)
    .floatingGlass()
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

extension ConnectionLine {
  /// A steady state fades away once read. A problem stays on screen.
  fileprivate var settles: Bool {
    switch self {
    case .partnerHere, .partnerAway: true
    case .connecting, .reconnecting, .refused: false
    }
  }
}

extension View {
  fileprivate func matchedTransitionSourceIfAvailable(
    id: String, in namespace: Namespace.ID
  ) -> some View {
    #if os(iOS)
      matchedTransitionSource(id: id, in: namespace)
    #else
      self
    #endif
  }
}

extension PetPlayState.Treat {
  fileprivate init(_ status: TreatLedger.Status) {
    switch status {
    case .neither: self = .neither
    case .waitingOnPartner: self = .waitingOnPartner
    case .waitingOnMe: self = .waitingOnMe
    case .fed: self = .fed
    }
  }
}
