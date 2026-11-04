import Foundation
import Pet
import PetScene
import RealityKit
import SwiftUI

/// The scene's room, Window Seat, furnished with the set the host asks for.
///
/// Its RealityView mounts the first time the host shows the scene and then stays: one that mounts
/// while the host keeps the scene off screen, as a tab out of sight does, never draws.
struct NookiRoom: View {
  let world: PetWorld
  let play: PetPlayState
  let rooms: GenzRoomCache
  let onEvent: @MainActor (PetSceneEvent) -> Void

  @Environment(\.petSceneFurniture) private var furniture
  @Environment(\.petSceneOnScreen) private var hostShowsScene
  @State private var canMount = false

  var body: some View {
    ZStack {
      if canMount {
        GenzRoomView(
          layout: GenzLayout.of(furniture), world: world, play: play, rooms: rooms,
          isShown: true, onEvent: onEvent)
      }
    }
    .onChange(of: hostShowsScene, initial: true) { _, shown in
      if shown { canMount = true }
    }
  }
}

/// What restarts the pet's pacing in a room: a new step, or the room coming on screen.
struct Pacing: Equatable {
  var step: PetWorld.Step
  var isShown: Bool
}

/// The room: its flat night behind, the 3D room, then the lighting preset's layers and the
/// opening's dark over it. The cat's place on screen goes up to the host as
/// ``PetSceneCatAnchorKey``. A new `layout` swaps its room into the same RealityView.
struct GenzRoomView: View {
  let layout: GenzLayout
  let world: PetWorld
  let play: PetPlayState
  let rooms: GenzRoomCache
  /// Whether this is the room on screen. Only that room paces the pet's steps.
  let isShown: Bool
  let onEvent: @MainActor (PetSceneEvent) -> Void

  /// What the RealityView holds: the room shown, and nothing else.
  @State private var holder = Entity()
  @State private var size: CGSize?
  @Environment(\.petSceneLighting) private var lighting
  @State private var track = GestureTrack()
  /// Where the drag in progress goes, decided where it began: the cat, a toy or the camera.
  @State private var dragRoute: CatTouchRoute?
  /// When the finger in the room touched down, and when it began to move.
  @State private var touchedDown: Date?
  @State private var setOff: Date?
  @State private var lastTap: CatTap?
  @State private var holding: CatHold?
  @State private var holdTimer: Task<Void, Never>?
  @State private var isAppeared = false
  @State private var viewID = UUID()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.petSceneOnScreen) private var hostShowsScene
  @Environment(\.petSceneDrawing) private var drawing
  @Environment(\.petSceneRoomArt) private var replacementArt
  @Environment(\.petSceneCat) private var cat
  @Environment(\.petSceneFlyIn) private var flyIn
  @Environment(\.petSceneGaze) private var gaze
  @Environment(\.petSceneOrbits) private var orbits
  @Environment(\.petSceneCatCue) private var catCue
  @Environment(\.petSceneDayLight) private var dayLight
  @Environment(\.petSceneFollowsTilt) private var followsTilt
  @Environment(\.petSceneOpeningEnded) private var openingEnded
  @Environment(\.petSceneOpeningStarted) private var openingStarted
  @Environment(\.petSceneWindowView) private var windowView
  @Environment(\.petSceneViewArt) private var viewArt
  @State private var plates = ViewPlateCache()
  @Environment(\.petSceneRenovator) private var renovator
  @State private var isDecorating = false
  @State private var decorStatus = DecorStatus()
  @State private var holdBegan: Date?
  @Environment(\.scenePhase) private var scenePhase

  private let behind = RoomLayerSlot.windowNight
  private let over: [RoomLayerSlot] = [.windowBacklight, .windowBloom, .windowDim]

  private var isOnScreen: Bool {
    isAppeared && hostShowsScene && scenePhase == .active
  }

  /// The room for `layout`. The cache makes each room once, so this is the same room every time.
  private var room: GenzRoom { rooms.room(layout) }

  var body: some View {
    let room = room
    let look = room.screen.look
    let parts = RoomCostSwitches.shared
    ZStack {
      if parts.shows("layers") { layer(behind, room: room) }
      if parts.shows("sky") { theirSky }
      if parts.shows("haze") { RoomHaze(look: look, screen: room.screen) }
      stage(room)
      if parts.shows("layers") {
        ForEach(over, id: \.self) { slot in layer(slot, room: room) }
      }
      if parts.shows("halos") {
        GlowLights(
          look: look, screen: room.screen,
          isPaused: !isOnScreen || reduceMotion)
      }
      if parts.shows("grade") {
        GlowGrade(look: look)
        GlowVignette(look: look)
      }
      CatPurrOverlay(purr: room.purr)
      PartnerTouchOverlay(trigger: play.petsReceived) { room.screen.cat }
      RoomCatAnchor(screen: room.screen)
    }
    .ignoresSafeArea()
    .overlay { decorControls(room) }
    .sensoryFeedback(trigger: decorStatus, Self.gripFeedback)
    .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1), trigger: room.screen.switchPresses)
    .onChange(of: room.screen.switchPresses) { SwitchClick.play() }
    .modifier(GenzDecorFeeds(view: self, room: room))
    .onAppear { isAppeared = true }
    .onDisappear { isAppeared = false }
    .task(id: layout.key) {
      NookiTrace.mark("styled room mounted")
      room.startBuilding()
    }
    .task(id: Pacing(step: world.step, isShown: isShown)) {
      guard isShown else { return }
      await NookiChoreography.pacing.play(world, onEvent: onEvent)
    }
  }

  /// The partner's sky over the night outside, when the room follows the time of day.
  @ViewBuilder private var theirSky: some View {
    if let theirs = dayLight?.theirs {
      let sky = RoomDayLook.sky(theirs)
      // A lit sky glows down from the top of the night behind the room. Tinting the whole
      // backdrop instead only reads as brown on its dark colours.
      let colour = Color(
        red: Double(sky.colour.x), green: Double(sky.colour.y), blue: Double(sky.colour.z))
      LinearGradient(
        stops: [
          .init(color: colour.opacity(Double(sky.glow) * 0.6), location: 0),
          .init(color: colour.opacity(0), location: 0.45),
        ], startPoint: .top, endPoint: .bottom
      )
      .opacity(theirs.phase == .night ? 0 : 1)
      .blendMode(.screen)
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }

  private func art(for slot: RoomLayerSlot, state: RoomLayerState) -> AnyView? {
    replacementArt?.view(for: slot, state: state) ?? GenzNativeArt().view(for: slot, state: state)
  }

  /// One flat layer, redrawn every frame while the room opens and then only as often as it
  /// changes. The window's view is drawn by an artist's file for its slot or its view if there is
  /// one, else natively.
  private func layer(_ slot: RoomLayerSlot, room: GenzRoom) -> some View {
    // Art from a file may move all the time, so it keeps every frame.
    let isNative = replacementArt == nil && (slot != .windowNight || viewArt == nil)
    let schedule = RoomLayerSchedule(
      busyUntil: isNative ? room.screen.busyUntil : .distantFuture,
      steady: isNative ? slot.steadyInterval : RoomLayerSchedule.busy,
      isPaused: !isOnScreen || reduceMotion)
    return TimelineView(schedule) { context in
      let state = room.screen.state(
        for: slot, at: context.date, followsCamera: !isNative || slot.nativeFollowsCamera)
      if slot == .windowNight, replacementArt?.view(for: slot, state: state) == nil {
        let viewState = room.screen.viewState(at: context.date)
        if let art = viewArt?.view(viewState.view, state: viewState) {
          art
        } else {
          NativeWindowView(state: viewState, plates: plates)
        }
      } else {
        art(for: slot, state: state)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func stage(_ room: GenzRoom) -> some View {
    RealityView { content in
      content.camera = .virtual
      content.add(holder)
      hold(room)
    } update: { _ in
      hold(room)
    }
    .onGeometryChange(for: CGSize.self) {
      $0.size
    } action: {
      size = $0
      room.fit(to: $0)
    }
    .onChange(of: layout.key) { old, _ in
      let left = rooms.room(GenzLayout.of(old))
      left.setOnScreen(false, in: viewID)
      left.setFollowsTilt(false)
      set(up: room)
    }
    .simultaneousGesture(orbit(room))
    .simultaneousGesture(pinch(room))
    .simultaneousGesture(movePiece(room))
    .simultaneousGesture(pickUp(room))
    .simultaneousGesture(twist(room))
    .simultaneousGesture(tap(room))
    .simultaneousGesture(lift(room))
    .modifier(GenzRoomFeeds(view: self, room: room))
  }

  /// Hands the room everything it follows from the environment and the pet. Kept apart from
  /// the stage so each chain stays small enough to type-check.
  fileprivate struct GenzRoomFeeds: ViewModifier {
    let view: GenzRoomView
    let room: GenzRoom

    func body(content: Content) -> some View {
      view.feeds(content, room: room)
    }
  }

  fileprivate func feeds(_ content: some View, room: GenzRoom) -> some View {
    content
      .onChange(of: isOnScreen, initial: true) { _, onScreen in
        room.setOnScreen(onScreen, in: viewID)
      }
      .onChange(of: world, initial: true) { _, world in room.show(world) }
      .onChange(of: drawing, initial: true) { _, drawing in room.show(drawing: drawing) }
      .onChange(of: reduceMotion, initial: true) { _, reduced in room.setReduceMotion(reduced) }
      .onChange(of: flyIn, initial: true) { _, flyIn in
        room.onOpeningEnded = openingEnded
        room.onOpeningStarted = openingStarted
        room.flyIn(flyIn)
      }
      .onChange(of: gaze) { _, gaze in room.gaze(at: gaze) }
      .onChange(of: catCue) { _, request in
        if let request { room.cue(request.cue) }
      }
      .onChange(of: dayLight, initial: true) { _, light in room.show(dayLight: light) }
      .onChange(of: followsTilt, initial: true) { _, follows in room.setFollowsTilt(follows) }
      .onDisappear { room.setFollowsTilt(false) }
      // A treat or a pet from the partner wakes the cat, without telling anyone.
      .onChange(of: play.treatsUsed) { room.react(.treat) }
      .onChange(of: play.petsReceived) { room.partnerPetted() }
      .onChange(of: play.life, initial: true) { _, life in room.follow(life) }
      .onChange(of: play.brain, initial: true) { _, brain in
        room.followBrain(brain, speed: play.brainSpeed)
      }
      .onChange(of: play.lifeNeeds, initial: true) { _, needs in room.showLife(needs) }
      .onAppear {
        room.report = onEvent
      }
      .accessibilityElement()
      .accessibilityLabel("Window seat at night")
      .accessibilityAction(named: "Pet the cat") { onEvent(room.petCat()) }
      .accessibilityAction(named: "Turn the lamp on or off") { room.toggleLamp() }
      .accessibilityAction(named: Text("Press the light switch")) { onEvent(room.pressSwitch()) }
      .accessibilityAction(named: "Open the note") {
        onEvent(.noteOpened(delivery: world.delivery))
      }
  }

  /// Puts `room` in the RealityView in place of the room it held, and starts its updates.
  private func hold(_ room: GenzRoom) {
    guard room.root.parent !== holder else { return }
    for child in holder.children where child !== room.root { child.removeFromParent() }
    holder.addChild(room.root)
    room.startUpdates()
  }

  /// Gives a room swapped in everything the view has given the room before it.
  private func set(up room: GenzRoom) {
    room.report = onEvent
    if let size { room.fit(to: size) }
    room.setReduceMotion(reduceMotion)
    room.show(world)
    room.show(drawing: drawing)
    room.onOpeningEnded = openingEnded
    room.onOpeningStarted = openingStarted
    room.flyIn(flyIn)
    room.show(dayLight: dayLight)
    room.setFollowsTilt(followsTilt)
    room.setCat(cat)
    room.setLighting(lighting)
    room.setRoomLight(play.light, animated: false)
    room.setWindowView(windowView)
    room.setOnScreen(isOnScreen, in: viewID)
  }

  // MARK: - Decorating

  /// Keeps decorating in step with the closet and the shop, and the controls with the room.
  fileprivate struct GenzDecorFeeds: ViewModifier {
    let view: GenzRoomView
    let room: GenzRoom

    func body(content: Content) -> some View {
      view.decorFeeds(content, room: room)
    }
  }

  fileprivate func decorFeeds(_ content: some View, room: GenzRoom) -> some View {
    content
      .onAppear {
        let decor = room.decor
        decor.onChange = { decorStatus = DecorStatus(decor, title: GenzRoom.title(ofDecorName:)) }
      }
      .onDisappear { renovator?.isRenovating = false }
      .onChange(of: renovator?.openRequests) { if isShown { isDecorating = true } }
      .onChange(of: isDecorating, initial: true) { _, isOn in
        room.decor.isOn = isOn
        renovator?.isRenovating = isOn
      }
      .onChange(of: layout.key) { isDecorating = false }
      .onChange(of: cat, initial: true) { _, cat in room.setCat(cat) }
      .onChange(of: lighting, initial: true) { _, lighting in room.setLighting(lighting) }
      .onChange(of: play.light, initial: true) { _, light in room.setRoomLight(light) }
      .onChange(of: windowView, initial: true) { _, choice in room.setWindowView(choice) }
  }

  @ViewBuilder private func decorControls(_ room: GenzRoom) -> some View {
    if isDecorating {
      // The room draws none of the shop's furniture, so it offers no closet to add from.
      DecorControls(
        status: decorStatus, onUndo: { touch(room).undo() }, onDone: { isDecorating = false },
        onRotate: { room.decor.rotateStep() }, onPutAway: { touch(room).putAway() })
    }
  }

  /// A soft tap as a piece is picked up, and a lighter one as it is set down.
  private static func gripFeedback(_ old: DecorStatus, _ new: DecorStatus) -> SensoryFeedback? {
    switch new.grip(from: old) {
    case .pickUp: .impact(flexibility: .soft, intensity: 0.55)
    case .drop: .impact(flexibility: .soft, intensity: 0.35)
    case nil: nil
    }
  }

  private func touch(_ room: GenzRoom) -> DecorTouch {
    DecorTouch(
      session: room.decor, renovator: nil, floor: { [room] point in room.floorPoint(under: point) })
  }

  /// While decorating, a finger on a piece picks it up, and the piece follows it until let go.
  private func movePiece(_ room: GenzRoom) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .targetedToAnyEntity()
      .onChanged { value in
        let drag = value.gestureValue
        let began = holdBegan ?? drag.time
        if holdBegan == nil { holdBegan = drag.time }
        let held = drag.time.timeIntervalSince(began)
        let moved = hypot(drag.translation.width, drag.translation.height)
        let decor = room.decor
        let picksUp =
          decor.isDragging || (isDecorating && (moved > 3 || held > 0.25))
        guard picksUp else { return }
        touch(room).drag(
          value.entity, from: drag.startLocation, to: drag.location,
          enter: { isDecorating = true })
      }
      .onEnded { _ in
        holdBegan = nil
        touch(room).endDrag()
      }
  }

  /// Holding a piece still opens the room for decorating and picks the piece up.
  private func pickUp(_ room: GenzRoom) -> some Gesture {
    LongPressGesture(minimumDuration: 0.45)
      .targetedToAnyEntity()
      .onEnded { value in
        guard !isDecorating, room.decor.piece(containing: value.entity) != nil else { return }
        isDecorating = true
        room.decor.isOn = true
        room.decor.select(value.entity)
      }
  }

  /// Two fingers turn the piece picked up.
  private func twist(_ room: GenzRoom) -> some Gesture {
    RotateGesture()
      .onChanged { value in
        guard isDecorating else { return }
        touch(room).twist(by: value.rotation.radians)
      }
      .onEnded { _ in touch(room).endTwist() }
  }

  /// A tap on the cat pats it and one on the bowl fills it. Two quick taps on the cat ask for a
  /// trick and on the floor call the cat there; two anywhere else send the camera home, as the
  /// room's own taps do.
  private func tap(_ room: GenzRoom) -> some Gesture {
    SpatialTapGesture()
      .targetedToAnyEntity()
      .onEnded { value in
        if isDecorating {
          touch(room).tap(value.entity)
          return
        }
        let target = room.tapTarget(at: value.location)
        let now = ProcessInfo.processInfo.systemUptime
        let isDouble = lastTap.map { $0.isPartner(of: target, at: value.location, now) } ?? false
        lastTap = isDouble ? nil : CatTap(target: target, location: value.location, time: now)
        let route = CatTouchRouter.route(
          isDouble ? .doubleTap : .tap, on: target, isHoldingCat: room.isHoldingCat)
        switch route {
        case .trick:
          room.tapTimer = NookiTapTimer()
          room.askTrick().forEach(onEvent)
        case .call:
          room.tapTimer = NookiTapTimer()
          room.callCat(to: value.location).forEach(onEvent)
        case .fillBowl:
          room.fillBowl().forEach(onEvent)
        case .fling(let toy):
          room.nudge(toy)
        case .pat, .camera, .scenery, .ignore:
          if let event = room.tap(value.entity, at: now) { onEvent(event) }
        case .stroke, .lift, .carry, .offerTreat:
          break
        }
      }
  }

  /// A finger held still on the cat picks it up; it hangs under the finger until let go.
  private func lift(_ room: GenzRoom) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if holding == nil {
          touchedDown = value.time
          holding = .pressing
          guard !isDecorating, room.isOverCat(value.startLocation) else {
            holding = .elsewhere
            return
          }
          holdTimer = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, holding == .pressing, room.liftCat() else { return }
            holding = .lifted
          }
        }
        let moved = hypot(value.translation.width, value.translation.height)
        if holding == .pressing, moved > 5 {
          holdTimer?.cancel()
          holding = .elsewhere
        }
        if holding == .lifted { room.moveLifted(to: value.location) }
      }
      .onEnded { _ in
        holdTimer?.cancel()
        if holding == .lifted { room.dropCat() }
        holding = nil
      }
  }

  /// A drag from the cat strokes it and one from a toy plays with it, as ``startingRoute`` tells;
  /// any other drag turns the room. The cat's eyes follow the finger throughout.
  private func orbit(_ room: GenzRoom) -> some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { value in
        guard var route = dragRoute ?? startingRoute(room, value) else {
          room.followFinger(at: value.location)
          return
        }
        // A drag that moves or turns a piece is the piece's, to its end.
        if room.decor.isDragging || room.decor.isTurning { route = .ignore }
        let isFirst = dragRoute == nil
        dragRoute = route
        room.followFinger(at: value.location)
        switch route {
        case .stroke:
          if isFirst {
            room.stroke(at: value.location).forEach(onEvent)
          } else {
            room.strokeMoved(to: value.location).forEach(onEvent)
          }
        case .carry(let toy), .fling(let toy):
          room.carry(toy, to: value.location)
        case .offerTreat:
          room.offerTreat(at: value.location).forEach(onEvent)
        case .camera:
          room.fingerAt(value.location)
          guard orbits else { return }
          room.orbit(
            byX: Float(value.translation.width - track.drag.width),
            y: Float(value.translation.height - track.drag.height))
          track.drag = value.translation
        case .pat, .trick, .lift, .fillBowl, .call, .scenery, .ignore:
          break
        }
      }
      .onEnded { value in
        defer {
          dragRoute = nil
          setOff = nil
        }
        track.drag = .zero
        switch dragRoute {
        case .stroke: room.strokeEnded()
        case .offerTreat: room.endTreat()
        case .carry(let toy), .fling(let toy):
          room.release(toy, velocity: value.velocity, at: value.location)
        case .camera:
          room.fingerLifted()
          guard orbits else { return }
          room.endOrbit(
            velocityX: Float(value.velocity.width), velocityY: Float(value.velocity.height))
        case .pat, .trick, .lift, .fillBowl, .call, .scenery, .ignore, nil:
          break
        }
      }
  }

  /// Where a drag goes once it has begun: to the cat, a toy or the treats only when it starts on
  /// them and either rested there first or sets off along what they do. Nil while too short to
  /// tell.
  private func startingRoute(_ room: GenzRoom, _ value: DragGesture.Value) -> CatTouchRoute? {
    let moved = setOff ?? value.time
    setOff = moved
    let start = CatDragStart(
      rested: touchedDown.map { max(moved.timeIntervalSince($0), 0) } ?? 0,
      movement: SIMD2(Double(value.translation.width), Double(value.translation.height)),
      axis: room.catBody().map { $0.tail - $0.head })
    return CatTouchRouter.routeDrag(
      on: room.dragTarget(at: value.startLocation), start: start, isHoldingCat: room.isHoldingCat)
  }

  private func pinch(_ room: GenzRoom) -> some Gesture {
    MagnifyGesture()
      .onChanged { value in
        guard room.decor.selected == nil else { return }
        room.zoom(by: Float(value.magnification / track.pinch))
        track.pinch = value.magnification
      }
      .onEnded { _ in
        track.pinch = 1
        room.endZoom()
      }
  }
}

/// One tap, kept to tell a double tap from two single ones.
struct CatTap: Equatable {
  let target: CatTouchTarget
  let location: CGPoint
  let time: TimeInterval

  /// Whether a tap on `target` at `location` and `time` makes a double tap with this one.
  func isPartner(of target: CatTouchTarget, at location: CGPoint, _ time: TimeInterval) -> Bool {
    target == self.target && time - self.time <= NookiTapTimer.window
      && hypot(location.x - self.location.x, location.y - self.location.y) < 60
  }
}

/// A finger down that may become a hold on the cat.
enum CatHold: Equatable {
  case pressing
  case lifted
  case elsewhere
}
