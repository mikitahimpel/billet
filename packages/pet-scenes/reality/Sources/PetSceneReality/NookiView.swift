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
  let onEvent: @MainActor (PetSceneEvent) -> Void

  /// Taken from the cache after the first frame. A default value here would run on every parent
  /// update.
  @State private var diorama: NookiDiorama?
  @State private var poster: CGImage?
  @State private var isReady = false
  @State private var isMochiMissing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      if let diorama {
        NookiStage(diorama: diorama, world: world, play: play, onEvent: onEvent)
      }
      if !isReady, let poster {
        Image(decorative: poster, scale: 1)
          .resizable()
          .scaledToFit()
          .allowsHitTesting(false)
          .transition(.opacity)
      }
    }
    .overlay(alignment: .top) {
      if isMochiMissing {
        Text("Mochi couldn't load")
          .font(.footnote)
          .padding(8)
          .background(.thinMaterial, in: Capsule())
          .padding(.top, 8)
      }
    }
    .background(Self.backdrop)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isReady)
    .task {
      if poster == nil { poster = await NookiPoster.load() }
      await Task.yield()
      guard diorama == nil else { return }
      let made = cache.diorama()
      let ready = $isReady
      made.onReady = { ready.wrappedValue = true }
      let missing = $isMochiMissing
      made.onMochiMissing = { missing.wrappedValue = $0 }
      isMochiMissing = made.isMochiMissing
      diorama = made
      made.startLoading()
    }
    .task(id: world) {
      await NookiChoreography.pacing.play(world, onEvent: onEvent)
    }
  }

  private static let backdrop = Color(red: 0.13, green: 0.16, blue: 0.23)
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

  @State private var lastDrag = CGSize.zero
  @State private var lastPinch: CGFloat = 1
  @State private var isAppeared = false
  @State private var isRenovating = false
  @State private var paint = NookiSwatch.cream
  @State private var viewSize = SIMD2<Float>(1, 1)
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.petSceneOnScreen) private var hostShowsScene
  @Environment(\.petSceneDrawing) private var drawing
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    RealityView { content in
      content.camera = .virtual
      content.add(diorama.root)
      diorama.startUpdates(from: content)
    }
    .ignoresSafeArea()
    .onGeometryChange(for: CGSize.self) {
      $0.size
    } action: { size in
      viewSize = SIMD2(Float(size.width), Float(size.height))
    }
    .simultaneousGesture(orbit)
    .simultaneousGesture(pinch)
    .simultaneousGesture(lift)
    .simultaneousGesture(brush)
    .simultaneousGesture(tap)
    .overlay(alignment: .topLeading) {
      NookiRenovateControls(isOpen: $isRenovating, paint: $paint) { diorama.resetRoom() }
    }
    .onChange(of: isRenovating, initial: true) { _, isOn in diorama.renovation.isOn = isOn }
    .onChange(of: paint, initial: true) { _, paint in diorama.paint = paint }
    .accessibilityElement()
    .accessibilityLabel("Mochi's room")
    .accessibilityAction(named: "Pet Mochi") { perform(.mochi) }
    .accessibilityAction(named: "Turn the lamp on or off") { perform(.lamp) }
    .accessibilityAction(named: "Catch the paper plane") {
      if world.noteArrived { perform(.plane) }
    }
    .accessibilityAction(named: "Open the note") {
      if world.delivery > 0 { perform(.note) }
    }
    .onAppear { isAppeared = true }
    .onDisappear { isAppeared = false }
    .onChange(of: isOnScreen, initial: true) { _, onScreen in
      diorama.setOnScreen(onScreen)
    }
    .onChange(of: play, initial: true) { _, play in
      diorama.show(play)
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
  }

  private var isOnScreen: Bool {
    isAppeared && hostShowsScene && scenePhase == .active
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

  /// A swipe that starts on the yarn throws it. Any other swipe orbits.
  private var orbit: some Gesture {
    DragGesture(minimumDistance: 6)
      .targetedToAnyEntity()
      .onChanged { value in
        guard value.entity.name != NookiTarget.yarn.rawValue, !isHoldingPiece(value.entity) else {
          return
        }
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
        } else if value.entity.name == NookiTarget.yarn.rawValue {
          diorama.flickYarn(velocityX: Float(velocity.width), velocityY: Float(velocity.height))
        } else {
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
