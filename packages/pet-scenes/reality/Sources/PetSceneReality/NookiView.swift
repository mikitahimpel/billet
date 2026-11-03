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

/// What a drag in Nooki does, decided where it starts: plays with a toy Nooki adds, brings a
/// treat out of the bowl, or is the room's own drag.
enum NookiDrag: Equatable {
  case decided(CatToy?)
  /// A treat taken from the bowl.
  case treat

  static func of(_ target: CatTouchTarget) -> NookiDrag {
    switch target {
    case .bowl: .treat
    case .toy(let toy) where NookiDiorama.addedToys.contains(toy): .decided(toy)
    case .cat, .toy, .treats, .floor, .scenery, .nothing: .decided(nil)
    }
  }
}

private struct NookiStage: View {
  let diorama: NookiDiorama
  let world: PetWorld
  let play: PetPlayState
  let onEvent: @MainActor (PetSceneEvent) -> Void

  @State private var shopRoom: NookiShopRoom
  @State private var track = GestureTrack()
  /// Whether the drag in progress began on one of the toys Nooki adds, once that is known.
  @State private var toyDrag: NookiDrag?
  @State private var lastTap: CatTap?
  @State private var holding: CatHold?
  @State private var holdTimer: Task<Void, Never>?

  @State private var isAppeared = false
  @State private var isRenovating = false
  @State private var paint = NookiSwatch.cream
  @State private var decorStatus = DecorStatus()
  @State private var lastTwist: Double?
  @State private var viewSize = SIMD2<Float>(1, 1)
  @State private var viewID = UUID()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.petSceneOnScreen) private var hostShowsScene
  @Environment(\.petSceneRenovator) private var renovator
  @Environment(\.petSceneDrawing) private var drawing
  @Environment(\.petSceneCat) private var cat
  @Environment(\.petSceneFlyIn) private var flyIn
  @Environment(\.petSceneGaze) private var gaze
  @Environment(\.petSceneOrbits) private var orbits
  @Environment(\.petSceneCatCue) private var catCue
  @Environment(\.petSceneDayLight) private var dayLight
  @Environment(\.petSceneFillsView) private var fillsView
  @Environment(\.petSceneShowsControls) private var showsControls
  @Environment(\.petSceneOpeningEnded) private var openingEnded
  @Environment(\.petSceneOpeningStarted) private var openingStarted
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
        diorama.report = onEvent
        isAppeared = true
        connectRenovator()
        let decor = diorama.renovation.decor
        decor.onChange = { decorStatus = DecorStatus(decor) }
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
        diorama.onOpeningStarted = openingStarted
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
    decorated
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

  /// The room with the controls for decorating it, opened from here, the closet or the shop.
  private var decorated: some View {
    touchable
      .overlay { decorControls }
      .overlay(alignment: .topLeading) { decorButton }
      .onChange(of: renovator?.openRequests) { isRenovating = true }
      .onChange(of: renovator?.placements) { isRenovating = true }
      .onChange(of: isRenovating, initial: true) { _, isOn in
        diorama.renovation.isOn = isOn
        renovator?.isRenovating = isOn
      }
      .onChange(of: paint, initial: true) { _, paint in diorama.paint = paint }
  }

  /// The room with the gestures that move the view and the pieces in it.
  private var touchable: some View {
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
      .simultaneousGesture(hold)
      .simultaneousGesture(twist)
      .simultaneousGesture(tap)
      .simultaneousGesture(holdCat)
  }

  /// While the room is decorated: undo and done, the piece's tools, the closet and the paints.
  @ViewBuilder private var decorControls: some View {
    if isRenovating {
      DecorControls(
        status: decorStatus, closet: renovator?.closetFurniture ?? [],
        owned: { item in renovator?.owned(item) ?? 0 }, paint: $paint, onReset: resetRoom,
        onUndo: { touch.undo() }, onDone: { isRenovating = false },
        onRotate: { diorama.renovation.decor.rotateStep() }, onPutAway: { touch.putAway() },
        onAdd: { item in add(item) })
    }
  }

  /// The way into decorating where the room shows its own controls.
  @ViewBuilder private var decorButton: some View {
    if showsControls, !isRenovating {
      Button {
        isRenovating = true
      } label: {
        Image(systemName: "sofa")
          .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
          .frame(width: 44, height: 44)
          .background(.thinMaterial, in: Circle())
      }
      .buttonStyle(.plain)
      .padding(12)
      .accessibilityLabel("Decorate the room")
      .accessibilityIdentifier("decorOpen")
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
    .overlay { PartnerTouchOverlay(trigger: play.petsReceived) { diorama.catPointOnScreen } }
    .onChange(of: play.brain, initial: true) { _, brain in diorama.followBrain(brain) }
  }

  private var isOnScreen: Bool {
    isAppeared && hostShowsScene && scenePhase == .active
  }

  /// Puts this room's plan behind the closet, and sends what happens in the room to the shop.
  private func connectRenovator() {
    guard let renovator else { return }
    let renovation = diorama.renovation
    renovation.onPainted = { renovator.cleared($0) }
    renovation.onPlacementMoved = { id, box in
      renovator.moved(
        placement: id, x: Double(box.centre.x), z: Double(box.centre.y), yaw: Double(box.yaw))
      diorama.noticePiece(at: box)
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
        if isRenovating {
          if diorama.renovation.isSurface(value.entity) {
            diorama.paintSurface(value.entity)
          } else {
            touch.tap(value.entity)
          }
          return
        }
        let time = ProcessInfo.processInfo.systemUptime
        if !isRenovating {
          let target = diorama.tapTarget(at: value.location)
          let isDouble =
            lastTap.map { $0.isPartner(of: target, at: value.location, time) } ?? false
          lastTap = isDouble ? nil : CatTap(target: target, location: value.location, time: time)
          let route = CatTouchRouter.route(
            isDouble ? .doubleTap : .tap, on: target, isHoldingCat: diorama.isHoldingCat)
          switch route {
          case .trick:
            diorama.tapTimer = NookiTapTimer()
            diorama.askTrick().forEach(onEvent)
            return
          case .call:
            diorama.tapTimer = NookiTapTimer()
            diorama.callCat(to: value.location).forEach(onEvent)
            return
          case .fillBowl:
            diorama.fillBowl().forEach(onEvent)
            return
          case .fling(let toy) where NookiDiorama.addedToys.contains(toy):
            diorama.nudge(toy)
            return
          case .pat, .camera, .scenery, .ignore, .fling, .stroke, .lift, .carry, .offerTreat:
            break
          }
        }
        if let event = diorama.tap(value.entity, at: time) { onEvent(event) }
      }
  }

  /// What a finger and the controls do to the room's pieces.
  private var touch: DecorTouch {
    let size = viewSize
    return DecorTouch(
      session: diorama.renovation.decor, renovator: renovator,
      floor: { [diorama] point in
        diorama.floorPoint(under: SIMD2(Float(point.x), Float(point.y)), in: size)
      },
      name: { NookiRenovation.name(of: $0) })
  }

  /// Takes `item` from the closet into the open floor, picked up so it can be moved at once.
  private func add(_ item: ShopItem) {
    _ = touch.add(item, half: NookiShopRoom.footprint(of: item), near: NookiRenovation.openFloor)
  }

  /// A swipe that moves or turns a piece belongs to it, so the view stays still. While the room is
  /// open, any swipe from a piece moves it.
  private func isHoldingPiece(_ entity: Entity) -> Bool {
    let decor = diorama.renovation.decor
    return decor.isDragging || decor.isTurning
      || (isRenovating && decor.piece(containing: entity) != nil)
  }

  /// A swipe that starts on the yarn throws it, and one that starts on the cat strokes it. Any
  /// other swipe orbits. The cat's eyes follow the finger throughout.
  private var orbit: some Gesture {
    DragGesture(minimumDistance: 6)
      .targetedToAnyEntity()
      .onChanged { value in
        let location = value.gestureValue.location
        if diorama.isHoldingCat { return }
        if toyDrag == nil {
          let start = value.gestureValue.startLocation
          toyDrag = isRenovating ? .decided(nil) : NookiDrag.of(diorama.tapTarget(at: start))
        }
        if toyDrag == .treat {
          diorama.offerTreat(at: location).forEach(onEvent)
          return
        }
        if case .decided(let toy?) = toyDrag {
          diorama.followFinger(at: SIMD2(Float(location.x), Float(location.y)), in: viewSize)
          diorama.carry(toy, to: location)
          return
        }
        let point = SIMD2(Float(location.x), Float(location.y))
        diorama.followFinger(at: point, in: viewSize)
        diorama.fingerAt(point, in: viewSize)
        guard value.entity.name != NookiTarget.yarn.rawValue, !isHoldingPiece(value.entity) else {
          return
        }
        if value.entity.name == NookiTarget.cat.rawValue, !isRenovating {
          diorama.stroke(at: location).forEach(onEvent)
          return
        }
        guard orbits else { return }
        let translation = value.gestureValue.translation
        diorama.orbit(
          byX: Float(translation.width - track.drag.width),
          y: Float(translation.height - track.drag.height))
        track.drag = translation
      }
      .onEnded { value in
        let velocity = value.gestureValue.velocity
        track.drag = .zero
        diorama.fingerLifted()
        defer { toyDrag = nil }
        if toyDrag == .treat {
          diorama.endTreat()
          return
        }
        if diorama.isHoldingCat { return }
        if case .decided(let toy?) = toyDrag {
          diorama.release(toy, velocity: velocity, at: value.gestureValue.location)
          return
        }
        if isHoldingPiece(value.entity) {
          return
        } else if value.entity.name == NookiTarget.cat.rawValue, !isRenovating {
          diorama.strokeEnded()
          return
        } else if value.entity.name == NookiTarget.yarn.rawValue {
          diorama.flickYarn(velocityX: Float(velocity.width), velocityY: Float(velocity.height))
        } else if orbits {
          diorama.endOrbit(velocityX: Float(velocity.width), velocityY: Float(velocity.height))
        }
      }
  }

  /// While the room is open for changes, a finger on a piece picks it up, and the piece follows
  /// it until let go.
  private var lift: some Gesture {
    DragGesture(minimumDistance: 0)
      .targetedToAnyEntity()
      .onChanged { value in
        let drag = value.gestureValue
        let held = drag.time.timeIntervalSince(holdStart(value.entity, at: drag.time))
        let moved = hypot(drag.translation.width, drag.translation.height)
        let decor = diorama.renovation.decor
        guard decor.isDragging || (isRenovating && (moved > 3 || held > 0.25)) else { return }
        touch.drag(
          value.entity, from: drag.startLocation, to: drag.location, enter: { isRenovating = true })
      }
      .onEnded { _ in
        holdBegan = nil
        touch.endDrag()
      }
  }

  @State private var holdBegan: Date?

  private func holdStart(_ entity: Entity, at time: Date) -> Date {
    if let holdBegan { return holdBegan }
    holdBegan = time
    return time
  }

  /// Holding a piece still opens the room for decorating and picks the piece up.
  private var hold: some Gesture {
    LongPressGesture(minimumDuration: 0.45)
      .targetedToAnyEntity()
      .onEnded { value in
        let decor = diorama.renovation.decor
        guard !isRenovating, decor.piece(containing: value.entity) != nil else { return }
        isRenovating = true
        decor.isOn = true
        decor.select(value.entity)
      }
  }

  /// Two fingers turn the piece picked up.
  private var twist: some Gesture {
    RotateGesture()
      .onChanged { value in
        guard isRenovating else { return }
        touch.twist(by: value.rotation.radians)
      }
      .onEnded { _ in touch.endTwist() }
  }

  /// A finger held still on the cat picks it up; it hangs under the finger until let go.
  private var holdCat: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if holding == nil {
          holding = .pressing
          guard !isRenovating, diorama.tapTarget(at: value.startLocation) == .cat else {
            holding = .elsewhere
            return
          }
          holdTimer = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, holding == .pressing, diorama.liftCat() else { return }
            holding = .lifted
          }
        }
        if holding == .pressing, hypot(value.translation.width, value.translation.height) > 5 {
          holdTimer?.cancel()
          holding = .elsewhere
        }
        if holding == .lifted { diorama.moveLifted(to: value.location) }
      }
      .onEnded { _ in
        holdTimer?.cancel()
        if holding == .lifted { diorama.dropCat() }
        holding = nil
      }
  }

  private var pinch: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        guard diorama.renovation.decor.selected == nil else { return }
        diorama.zoom(by: Float(value.magnification / track.pinch))
        track.pinch = value.magnification
      }
      .onEnded { _ in
        track.pinch = 1
        diorama.endZoom()
      }
  }
}
