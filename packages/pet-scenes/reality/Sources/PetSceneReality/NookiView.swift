import Foundation
import ImageIO
import Pet
import PetScene
import RealityKit
import SwiftUI

/// Opens instantly on a still of the room, builds the real one behind it, and fades across once
/// the room has rendered. The pet's steps keep their pace throughout.
struct NookiView: View {
  let world: PetWorld
  let play: PetPlayState
  let cache: NookiRoomCache
  /// Whether this is the room on screen. Only that room paces the pet's steps.
  var isShown = true
  let onEvent: @MainActor (PetSceneEvent) -> Void

  /// Taken from the cache after the first frame. A default value here would run on every parent
  /// update.
  @State private var diorama: NookiDiorama?
  @State private var poster: CGImage?
  @State private var isReady = false
  @State private var isCatMissing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.petSceneFlyIn) private var flyIn
  @Environment(\.petSceneFillsView) private var fillsView
  @Environment(\.petSceneLighting) private var lighting

  /// The still is framed for a fitted room on its own ground. An opening starts from far out, and
  /// a filled view frames the room closer on the host's ground, so either fades the room in alone.
  private var skipsPoster: Bool { fillsView || (flyIn.map { !$0.isSkipped } ?? false) }

  var body: some View {
    ZStack {
      if let diorama {
        NookiStage(diorama: diorama, world: world, play: play, onEvent: onEvent)
          // With no still, nothing shows until the room has rendered, rather than its parts.
          // Fully transparent, the view would stop drawing and the room would never report ready.
          .opacity(isReady || !skipsPoster ? 1 : 0.001)
      }
      if !isReady, !skipsPoster, let poster {
        Image(decorative: poster, scale: 1)
          .resizable()
          .scaledToFit()
          .allowsHitTesting(false)
          .transition(.opacity)
      }
      GlowGrade(look: .of(lighting))
      GlowVignette(look: .of(lighting))
    }
    .overlay(alignment: .top) {
      if isCatMissing {
        Text("The cat couldn't load")
          .font(.footnote)
          .padding(8)
          .background(.thinMaterial, in: Capsule())
          .padding(.top, 8)
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isReady)
    .task {
      if poster == nil { poster = await NookiPoster.load() }
      await Task.yield()
      guard diorama == nil else { return }
      let made = cache.diorama()
      let ready = $isReady
      made.onReady = { ready.wrappedValue = true }
      let missing = $isCatMissing
      made.onCatMissing = { missing.wrappedValue = $0 }
      isCatMissing = made.isCatMissing
      await cache.untilRehearsed()
      diorama = made
      made.startLoading()
    }
    .task(id: Pacing(step: world.step, isShown: isShown)) {
      guard isShown else { return }
      await NookiChoreography.pacing.play(world, onEvent: onEvent)
    }
  }
}

/// The still shown until the room has rendered, decoded away from the main actor.
enum NookiPoster {
  static func load() async -> CGImage? {
    await Task.detached(priority: .userInitiated) {
      guard
        let url = Bundle.module.url(forResource: "pose-sleeping", withExtension: "png"),
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)
      else { return nil }
      return CGImageSourceCreateImageAtIndex(
        source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }.value
  }
}

private struct NookiStage: View {
  let diorama: NookiDiorama
  let world: PetWorld
  let play: PetPlayState
  let onEvent: @MainActor (PetSceneEvent) -> Void

  @State private var shopRoom: NookiShopRoom
  @State private var lastDrag = CGSize.zero
  @State private var lastPinch: CGFloat = 1
  @State private var isAppeared = false
  @State private var isRenovating = false
  @State private var paint = NookiSwatch.cream
  @State private var viewSize = SIMD2<Float>(1, 1)
  @State private var viewID = UUID()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.petSceneOnScreen) private var hostShowsScene
  @Environment(\.petSceneRenovator) private var renovator
  @Environment(\.petSceneDrawing) private var drawing
  @Environment(\.petSceneCat) private var cat
  @Environment(\.petSceneMoments) private var moments
  @Environment(\.petSceneFlyIn) private var flyIn
  @Environment(\.petSceneGaze) private var gaze
  @Environment(\.petSceneOrbits) private var orbits
  @Environment(\.petSceneCatCue) private var catCue
  @Environment(\.petSceneDayLight) private var dayLight
  @Environment(\.petSceneFillsView) private var fillsView
  @Environment(\.petSceneShowsControls) private var showsControls
  @Environment(\.petSceneOpeningEnded) private var openingEnded
  @Environment(\.scenePhase) private var scenePhase

  init(
    diorama: NookiDiorama, world: PetWorld, play: PetPlayState,
    onEvent: @escaping @MainActor (PetSceneEvent) -> Void
  ) {
    self.diorama = diorama
    self.world = world
    self.play = play
    self.onEvent = onEvent
    _shopRoom = State(initialValue: NookiShopRoom(renovation: diorama.renovation))
  }

  var body: some View {
    room
      .onAppear {
        isAppeared = true
        connectRenovator()
        diorama.whenAmbientIsReady { shopRoom.ambient = $0 }
      }
      .onDisappear {
        isAppeared = false
        renovator?.openSpot = nil
        renovator?.isRenovating = false
      }
      .onChange(of: isOnScreen, initial: true) { _, onScreen in
        diorama.setOnScreen(onScreen, in: viewID)
      }
      .onChange(of: play, initial: true) { _, play in
        diorama.show(play)
      }
      .onChange(of: play.room, initial: true) { _, room in shopRoom.apply(room) }
      .onChange(of: play.treatsUsed) {
        shopRoom.drop(play.lastTreat)
        reactToTreat()
      }
      .onChange(of: reduceMotion, initial: true) { _, reduced in
        diorama.setReduceMotion(reduced)
      }
      .onChange(of: world, initial: true) { _, world in
        diorama.show(world)
      }
      .onChange(of: drawing, initial: true) { _, drawing in
        diorama.show(drawing: drawing)
      }
      .onChange(of: cat, initial: true) { _, cat in
        diorama.setCat(cat)
      }
      .onChange(of: flyIn, initial: true) { _, flyIn in
        diorama.onOpeningEnded = openingEnded
        diorama.flyIn(flyIn)
      }
      .onChange(of: gaze) { _, gaze in diorama.gaze(at: gaze, in: viewSize) }
      .onChange(of: catCue) { _, request in
        if let request { diorama.cue(request.cue) }
      }
      .onChange(of: dayLight, initial: true) { _, light in diorama.show(dayLight: light) }
      .onChange(of: fillsView, initial: true) { _, fills in diorama.fillsView = fills }
  }

  /// The rendered room with its gestures, its controls and what VoiceOver offers.
  private var room: some View {
    stage
      .onGeometryChange(for: CGSize.self) {
        $0.size
      } action: { size in
        viewSize = SIMD2(Float(size.width), Float(size.height))
        diorama.fit(to: viewSize)
      }
      .simultaneousGesture(orbit)
      .simultaneousGesture(pinch)
      .simultaneousGesture(lift)
      .simultaneousGesture(brush)
      .simultaneousGesture(tap)
      .overlay(alignment: .topLeading) {
        if showsControls || isRenovating {
          NookiRenovateControls(isOpen: $isRenovating, paint: $paint, onReset: resetRoom)
        }
      }
      .onChange(of: renovator?.openRequests) { isRenovating = true }
      .onChange(of: isRenovating, initial: true) { _, isOn in
        diorama.renovation.isOn = isOn
        renovator?.isRenovating = isOn
      }
      .onChange(of: renovator?.placements) { isRenovating = true }
      .onChange(of: paint, initial: true) { _, paint in diorama.paint = paint }
      .accessibilityElement()
      .accessibilityLabel("The cat's room")
      .accessibilityAction(named: "Pet the cat") { perform(.cat) }
      .accessibilityAction(named: "Turn the lamp on or off") { perform(.lamp) }
      .accessibilityAction(named: "Catch the paper plane") {
        if world.noteArrived { perform(.plane) }
      }
      .accessibilityAction(named: "Open the note") {
        if world.delivery > 0 { perform(.note) }
      }
  }

  /// The room itself, with the purr's hearts over it.
  private var stage: some View {
    RealityView { content in
      content.camera = .virtual
      // The room outlives its view. A view that goes removes only its own holder, so it cannot
      // take the room away from the view that came after it.
      let holder = Entity()
      holder.addChild(diorama.root)
      content.add(holder)
      content.add(shopRoom.root)
      diorama.startUpdates()
    }
    .ignoresSafeArea()
    // In the same frame as the gestures, so a heart rises from under the stroking finger.
    .overlay { CatPurrOverlay(purr: diorama.purr) }
    .onChange(of: moments, initial: true) { _, moments in diorama.setMoments(moments) }
  }

  private var isOnScreen: Bool {
    isAppeared && hostShowsScene && scenePhase == .active
  }

  /// Puts this room's plan behind the closet, and sends what happens in the room to the shop.
  private func connectRenovator() {
    guard let renovator else { return }
    let renovation = diorama.renovation
    renovation.onPainted = { renovator.cleared($0) }
    renovation.onPlacementMoved = { id, position in
      renovator.moved(placement: id, x: Double(position.x), z: Double(position.z))
    }
    renovator.openSpot = { item in
      renovation.openSpot(half: NookiShopRoom.footprint(of: item)).map {
        (x: Double($0.x), z: Double($0.y))
      }
    }
  }

  /// Bare walls and floor, free paint and the shop's materials alike. Furniture stays bought.
  private func resetRoom() {
    diorama.resetRoom()
    renovator?.cleared(.wall)
    renovator?.cleared(.floor)
  }

  /// The cat wakes and hops once the treat has landed. Only the cat reacts: nothing is sent upward.
  private func reactToTreat() {
    Task {
      try? await Task.sleep(for: .seconds(NookiShopRoom.fallDuration))
      _ = diorama.perform(.cat)
      diorama.reactToTreat()
    }
  }

  private func perform(_ target: NookiTarget) {
    if let event = diorama.perform(target) { onEvent(event) }
  }

  private var tap: some Gesture {
    SpatialTapGesture()
      .targetedToAnyEntity()
      .onEnded { value in
        let time = ProcessInfo.processInfo.systemUptime
        if let event = diorama.tap(value.entity, at: time) { onEvent(event) }
      }
  }

  /// While the room is open a swipe from a piece or a surface belongs to it, so the view stays
  /// still while the hold that lifts a piece is deciding, and while paint goes on.
  private func isHoldingPiece(_ entity: Entity) -> Bool {
    diorama.renovation.isLifting
      || (isRenovating
        && (diorama.renovation.isPiece(entity) || diorama.renovation.isSurface(entity)))
  }

  /// A swipe that starts on the yarn throws it, and one that starts on the cat strokes it. Any
  /// other swipe orbits. The cat's eyes follow the finger throughout.
  private var orbit: some Gesture {
    DragGesture(minimumDistance: 6)
      .targetedToAnyEntity()
      .onChanged { value in
        let location = value.gestureValue.location
        let point = SIMD2(Float(location.x), Float(location.y))
        diorama.followFinger(at: point, in: viewSize)
        diorama.bat(at: point, in: viewSize)
        guard value.entity.name != NookiTarget.yarn.rawValue, !isHoldingPiece(value.entity) else {
          return
        }
        if value.entity.name == NookiTarget.cat.rawValue, !isRenovating {
          diorama.stroke(at: location)
          return
        }
        guard orbits else { return }
        let translation = value.gestureValue.translation
        diorama.orbit(
          byX: Float(translation.width - lastDrag.width),
          y: Float(translation.height - lastDrag.height))
        lastDrag = translation
      }
      .onEnded { value in
        let velocity = value.gestureValue.velocity
        lastDrag = .zero
        if isHoldingPiece(value.entity) {
          return
        } else if value.entity.name == NookiTarget.cat.rawValue, !isRenovating {
          return
        } else if value.entity.name == NookiTarget.yarn.rawValue {
          diorama.flickYarn(velocityX: Float(velocity.width), velocityY: Float(velocity.height))
        } else if orbits {
          diorama.endOrbit(velocityX: Float(velocity.width), velocityY: Float(velocity.height))
        }
      }
  }

  /// While the room is open, a touch on a wall or the floor paints it, whether a tap or a stroke.
  private var brush: some Gesture {
    DragGesture(minimumDistance: 0)
      .targetedToAnyEntity()
      .onChanged { value in
        guard isRenovating, !diorama.renovation.isLifting else { return }
        diorama.paintSurface(value.entity)
      }
  }

  /// Holding a piece while the room is open lifts it, and it follows the finger until let go.
  private var lift: some Gesture {
    LongPressGesture(minimumDuration: 0.3, maximumDistance: 24)
      .sequenced(before: DragGesture(minimumDistance: 0))
      .targetedToAnyEntity()
      .onChanged { value in
        guard isRenovating, case .second(true, let drag) = value.gestureValue else { return }
        if !diorama.renovation.isLifting, !diorama.lift(value.entity) { return }
        if let drag {
          diorama.moveLifted(
            to: SIMD2(Float(drag.location.x), Float(drag.location.y)), in: viewSize)
        }
      }
      .onEnded { _ in diorama.dropLifted() }
  }

  private var pinch: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        diorama.zoom(by: Float(value.magnification / lastPinch))
        lastPinch = value.magnification
      }
      .onEnded { _ in
        lastPinch = 1
        diorama.endZoom()
      }
  }
}
