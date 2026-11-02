import Foundation
import Pet
import PetScene
import RealityKit
import SwiftUI

/// Shows the room style the host asks for: one of the styled rooms, or the Nooki diorama.
struct NookiStyledRoom: View {
  let world: PetWorld
  let play: PetPlayState
  let cache: NookiRoomCache
  let rooms: GenzRoomCache
  let onEvent: @MainActor (PetSceneEvent) -> Void

  @Environment(\.petSceneRoomStyle) private var style
  /// The style on screen. It lags behind `style` while the last room's view comes down.
  @State private var shown: RoomStyle?

  var body: some View {
    ZStack {
      if let shown {
        if let layout = GenzLayout.of(shown) {
          GenzRoomView(layout: layout, world: world, play: play, rooms: rooms, onEvent: onEvent)
            .id(shown)
        } else {
          NookiView(world: world, play: play, cache: cache, onEvent: onEvent)
        }
      }
    }
    .task(id: style) {
      if let leaving = shown, leaving != style {
        self.shown = nil
        if GenzLayout.of(leaving) != nil { await rooms.untilLetGo() }
      }
      shown = style
    }
  }
}

/// A styled room: its flat night behind, the 3D room, then the glow and the opening's dark over
/// it. The cat's place on screen goes up to the host as ``PetSceneCatAnchorKey``.
struct GenzRoomView: View {
  let layout: GenzLayout
  let world: PetWorld
  let play: PetPlayState
  let rooms: GenzRoomCache
  let onEvent: @MainActor (PetSceneEvent) -> Void

  @State private var room: GenzRoom?
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
  @Environment(\.petSceneFlyIn) private var flyIn
  @Environment(\.petSceneGaze) private var gaze
  @Environment(\.petSceneOrbits) private var orbits
  @Environment(\.petSceneCatCue) private var catCue
  @Environment(\.petSceneDayLight) private var dayLight
  @Environment(\.petSceneFollowsTilt) private var followsTilt
  @Environment(\.petSceneOpeningEnded) private var openingEnded
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

  var body: some View {
    ZStack {
      if let room {
        layer(behind, room: room)
        theirSky
        stage(room)
        ForEach(over, id: \.self) { slot in layer(slot, room: room) }
        catAnchor(room)
      } else {
        layer(behind, room: nil)
      }
    }
    .ignoresSafeArea()
    .onAppear { isAppeared = true }
    .onDisappear { isAppeared = false }
    .task {
      guard room == nil else { return }
      let made = rooms.room(layout)
      made.startBuilding()
      room = made
    }
    .task(id: world.step) {
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

  /// One flat layer, redrawn every frame while the room is on screen.
  private func layer(_ slot: RoomLayerSlot, room: GenzRoom?) -> some View {
    TimelineView(.animation(paused: !isOnScreen || reduceMotion)) { context in
      let state = room?.screen.state(for: slot, at: context.date) ?? RoomLayerState()
      art(for: slot, state: state)
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
      let holder = Entity()
      holder.addChild(room.root)
      content.add(holder)
      room.startUpdates(from: content)
    }
    .onGeometryChange(for: CGSize.self) {
      $0.size
    } action: {
      room.fit(to: $0)
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
    .onAppear { room.art = replacementArt ?? GenzNativeArt() }
    .accessibilityElement()
    .accessibilityLabel(
      layout.style == .sunsetLamp ? "Bedroom lit by a sunset lamp" : "Window seat at night"
    )
    .accessibilityAction(named: "Pet the cat") { onEvent(room.petCat()) }
    .accessibilityAction(named: "Turn the lamp on or off") { room.toggleLamp() }
    .accessibilityAction(named: "Open the note") { onEvent(.noteOpened(delivery: world.delivery)) }
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
        }
        room.followFinger(at: value.location)
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
