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
  let onEvent: @MainActor (PetSceneEvent) -> Void

  /// Made once, after the first frame. A default value here would run on every parent update.
  @State private var diorama: NookiDiorama?
  @State private var poster: CGImage?
  @State private var isReady = false
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
    .background(Self.backdrop)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isReady)
    .task {
      if poster == nil { poster = await NookiPoster.load() }
      await Task.yield()
      guard diorama == nil else { return }
      let made = NookiDiorama()
      let ready = $isReady
      made.onReady = { ready.wrappedValue = true }
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.petSceneOnScreen) private var hostShowsScene
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    RealityView { content in
      content.camera = .virtual
      content.add(diorama.root)
      diorama.startUpdates(from: content)
    }
    .ignoresSafeArea()
    .simultaneousGesture(orbit)
    .simultaneousGesture(pinch)
    .gesture(tap)
    .accessibilityElement()
    .accessibilityLabel("Mochi's room")
    .accessibilityAction(named: "Pet Mochi") { perform(.mochi) }
    .accessibilityAction(named: "Turn the lamp on or off") { perform(.lamp) }
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

  private var orbit: some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { value in
        diorama.orbit(
          byX: Float(value.translation.width - lastDrag.width),
          y: Float(value.translation.height - lastDrag.height))
        lastDrag = value.translation
      }
      .onEnded { value in
        lastDrag = .zero
        diorama.endOrbit(
          velocityX: Float(value.velocity.width), velocityY: Float(value.velocity.height))
      }
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
