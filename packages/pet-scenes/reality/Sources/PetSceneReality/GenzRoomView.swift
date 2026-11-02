import Foundation
import Pet
import PetScene
import RealityKit
import SwiftUI

/// Shows the room style the host asks for: one of the styled rooms, or the Nooki diorama.
///
/// The diorama has its own view and the styled rooms share one, each mounted the first time it
/// is needed and then kept, hidden while the other is shown. A styled room switched to another
/// is swapped inside the same RealityView. A RealityView made while another is mounted only
/// draws its first frame and then redraws for touches, so a second styled room in a view of its
/// own stayed dark, its lamp off, note missing and cat asleep, or showed nothing at all. A hidden
/// view is fully transparent, so it draws nothing, and its room is told it is off screen, so it
/// stops updating.
struct NookiStyledRoom: View {
  let world: PetWorld
  let play: PetPlayState
  let cache: NookiRoomCache
  let rooms: GenzRoomCache
  let onEvent: @MainActor (PetSceneEvent) -> Void

  @Environment(\.petSceneRoomStyle) private var style
  @Environment(\.petSceneFurniture) private var furniture
  @Environment(\.petSceneOnScreen) private var hostShowsScene
  @State private var roomSwitch = RoomSwitch()

  private struct Wanted: Equatable {
    var style: RoomStyle
    var canMount: Bool
  }

  var body: some View {
    ZStack {
      ForEach(roomSwitch.mounted, id: \.self) { stage in
        let isShown = stage == roomSwitch.shown.map(RoomStage.init)
        view(for: stage, isShown: isShown)
          .opacity(isShown ? 1 : 0)
          .allowsHitTesting(isShown)
          .accessibilityHidden(!isShown)
          .environment(\.petSceneOnScreen, hostShowsScene && isShown)
      }
    }
    .task(id: Wanted(style: style, canMount: hostShowsScene)) {
      var next = roomSwitch
      next.show(style, hostShowsScene: hostShowsScene)
      if roomSwitch.shown != nil, next.shown != roomSwitch.shown {
        NookiTrace.mark("room switch asked")
      }
      roomSwitch = next
    }
  }

  @ViewBuilder private func view(for stage: RoomStage, isShown: Bool) -> some View {
    switch stage {
    case .diorama:
      NookiView(world: world, play: play, cache: cache, isShown: isShown, onEvent: onEvent)
    case .styled:
      if let layout = roomSwitch.styled.flatMap({ GenzLayout.of($0, furniture: furniture) }) {
        GenzRoomView(
          layout: layout, world: world, play: play, rooms: rooms, isShown: isShown,
          onEvent: onEvent)
      }
    }
  }
}

/// The views a room is shown in: the diorama's own, or the one all styled rooms share.
enum RoomStage: Hashable {
  case diorama
  case styled

  init(_ style: RoomStyle) {
    switch style {
    case .nooki: self = .diorama
    case .sunsetLamp, .windowSeat: self = .styled
    }
  }
}

/// Which views are mounted, which room is shown, and which styled room the shared view holds.
struct RoomSwitch: Equatable {
  /// The mounted views, in the order they were first needed.
  var mounted: [RoomStage] = []
  var shown: RoomStyle?
  /// The styled room in the shared view: the one shown last.
  var styled: RoomStyle?

  /// Shows `style`, mounting its view if it has none. A RealityView that mounts while the host
  /// keeps the scene off screen, as a tab out of sight does, never draws, so a view needed for
  /// the first time waits until the host shows the scene. A mounted view shows it straight away.
  mutating func show(_ style: RoomStyle, hostShowsScene: Bool) {
    guard shown != style else { return }
    let stage = RoomStage(style)
    if !mounted.contains(stage) {
      guard hostShowsScene else { return }
      mounted.append(stage)
    }
    shown = style
    if stage == .styled { styled = style }
  }
}

/// What restarts the pet's pacing in a room: a new step, or the room coming on screen.
struct Pacing: Equatable {
  var step: PetWorld.Step
  var isShown: Bool
}

/// A styled room: its flat night behind, the 3D room, then the lighting preset's layers and the
/// opening's dark over it. The cat's place on screen goes up to the host as ``PetSceneCatAnchorKey``. A new `layout`
/// swaps its room into the same RealityView.
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
  @State private var lastDrag = CGSize.zero
  @State private var lastPinch: CGFloat = 1
  /// Whether the drag in progress began on the cat, so it strokes rather than turns the room.
  @State private var stroking: Bool?
  @State private var isAppeared = false
  @State private var viewID = UUID()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.petSceneOnScreen) private var hostShowsScene
  @Environment(\.petSceneDrawing) private var drawing
  @Environment(\.petSceneRoomArt) private var replacementArt
  @Environment(\.petSceneOpeningCount) private var openings
  @Environment(\.petSceneCat) private var cat
  @Environment(\.petSceneMoments) private var moments
  @Environment(\.petSceneFlyIn) private var flyIn
  @Environment(\.petSceneGaze) private var gaze
  @Environment(\.petSceneOrbits) private var orbits
  @Environment(\.petSceneCatCue) private var catCue
  @Environment(\.petSceneDayLight) private var dayLight
  @Environment(\.petSceneFollowsTilt) private var followsTilt
  @Environment(\.petSceneOpeningEnded) private var openingEnded
  @Environment(\.petSceneWindowView) private var windowView
  @Environment(\.petSceneViewArt) private var viewArt
  @State private var plates = ViewPlateCache()
  @Environment(\.scenePhase) private var scenePhase

  private var behind: RoomLayerSlot {
    layout.style == .sunsetLamp ? .sunsetCity : .windowNight
  }

  private var over: [RoomLayerSlot] {
    layout.style == .sunsetLamp
      ? [.sunsetBloom, .sunsetDim] : [.windowBacklight, .windowBloom, .windowDim]
  }

  private var isOnScreen: Bool {
    isAppeared && hostShowsScene && scenePhase == .active
  }

  /// The room for `layout`. The cache makes each room once, so this is the same room every time.
  private var room: GenzRoom { rooms.room(layout) }

  var body: some View {
    let room = room
    let look = LightingLook.of(lighting)
    ZStack {
      layer(behind, room: room)
      theirSky
      GlowHaze(look: look, window: room.screen.window)
      stage(room)
      ForEach(over, id: \.self) { slot in layer(slot, room: room) }
      GlowLights(
        look: look, style: layout.style, screen: room.screen,
        isPaused: !isOnScreen || reduceMotion)
      GlowGrade(look: look)
      GlowVignette(look: look)
      CatPurrOverlay(purr: room.purr)
      catAnchor(room)
    }
    .ignoresSafeArea()
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

  /// One flat layer, redrawn every frame while the room is on screen. The window's view is drawn
  /// by an artist's file for its slot or its view if there is one, else natively.
  private func layer(_ slot: RoomLayerSlot, room: GenzRoom) -> some View {
    TimelineView(.animation(paused: !isOnScreen || reduceMotion)) { context in
      let state = room.screen.state(for: slot, at: context.date)
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

  private func catAnchor(_ room: GenzRoom) -> some View {
    Color.clear
      .anchorPreference(key: PetSceneCatAnchorKey.self, value: .point(room.screen.cat ?? .zero)) {
        room.screen.cat == nil ? nil : $0
      }
      .allowsHitTesting(false)
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
      if let left = GenzLayout.of(old).map(rooms.room) {
        left.setOnScreen(false, in: viewID)
        left.setFollowsTilt(false)
      }
      set(up: room)
    }
    .simultaneousGesture(orbit(room))
    .simultaneousGesture(pinch(room))
    .simultaneousGesture(tap(room))
    .onChange(of: isOnScreen, initial: true) { _, onScreen in
      room.setOnScreen(onScreen, in: viewID)
    }
    .onChange(of: world, initial: true) { _, world in room.show(world) }
    .onChange(of: drawing, initial: true) { _, drawing in room.show(drawing: drawing) }
    .onChange(of: reduceMotion, initial: true) { _, reduced in room.setReduceMotion(reduced) }
    .onChange(of: openings) { room.replayOpening() }
    .onChange(of: flyIn, initial: true) { _, flyIn in
      room.onOpeningEnded = openingEnded
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
    .onChange(of: play.petsReceived) { room.react(.pet) }
    .onChange(of: cat, initial: true) { _, cat in room.setCat(cat) }
    .onChange(of: lighting, initial: true) { _, lighting in room.setLighting(lighting) }
    .onChange(of: windowView, initial: true) { _, choice in room.setWindowView(choice) }
    .onChange(of: moments, initial: true) { _, moments in room.setMoments(moments) }
    .onAppear { room.art = replacementArt ?? GenzNativeArt() }
    .accessibilityElement()
    .accessibilityLabel(
      layout.style == .sunsetLamp ? "Bedroom lit by a sunset lamp" : "Window seat at night"
    )
    .accessibilityAction(named: "Pet the cat") { onEvent(room.petCat()) }
    .accessibilityAction(named: "Turn the lamp on or off") { room.toggleLamp() }
    .accessibilityAction(named: "Open the note") { onEvent(.noteOpened(delivery: world.delivery)) }
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
    room.art = replacementArt ?? GenzNativeArt()
    if let size { room.fit(to: size) }
    room.setReduceMotion(reduceMotion)
    room.show(world)
    room.show(drawing: drawing)
    room.onOpeningEnded = openingEnded
    room.flyIn(flyIn)
    room.show(dayLight: dayLight)
    room.setFollowsTilt(followsTilt)
    room.setCat(cat)
    room.setLighting(lighting)
    room.setMoments(moments)
    room.setWindowView(windowView)
    room.setOnScreen(isOnScreen, in: viewID)
  }

  private func tap(_ room: GenzRoom) -> some Gesture {
    SpatialTapGesture()
      .targetedToAnyEntity()
      .onEnded { value in
        if let event = room.tap(value.entity, at: ProcessInfo.processInfo.systemUptime) {
          onEvent(event)
        }
      }
  }

  private func orbit(_ room: GenzRoom) -> some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { value in
        let stroking = self.stroking ?? room.isOverCat(value.startLocation)
        if self.stroking == nil {
          self.stroking = stroking
          if stroking, let event = room.stroke() { onEvent(event) }
        } else if stroking {
          room.strokeMoved()
        }
        room.followFinger(at: value.location)
        if !stroking { room.bat(at: value.location) }
        guard orbits, !stroking else { return }
        room.orbit(
          byX: Float(value.translation.width - lastDrag.width),
          y: Float(value.translation.height - lastDrag.height))
        lastDrag = value.translation
      }
      .onEnded { value in
        defer { stroking = nil }
        lastDrag = .zero
        guard orbits, stroking != true else { return }
        room.endOrbit(
          velocityX: Float(value.velocity.width), velocityY: Float(value.velocity.height))
      }
  }

  private func pinch(_ room: GenzRoom) -> some Gesture {
    MagnifyGesture()
      .onChanged { value in
        room.zoom(by: Float(value.magnification / lastPinch))
        lastPinch = value.magnification
      }
      .onEnded { _ in
        lastPinch = 1
        room.endZoom()
      }
  }
}
