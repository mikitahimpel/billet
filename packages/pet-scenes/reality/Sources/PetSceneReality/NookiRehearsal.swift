import RealityKit
import SwiftUI

/// Builds the room out of sight and draws it a few times in a real RealityView, which is the
/// costly first use of the engine, so that the stalls happen before anyone is looking. A view
/// that shows the room takes it from here, and the rehearsal never takes it back.
struct NookiRehearsal: View {
  let cache: NookiRoomCache

  /// Cleared when the rehearsal ends, so that only the cache keeps the room.
  @State private var diorama: NookiDiorama?
  @State private var shown = Shown()

  var body: some View {
    ZStack {
      if let diorama {
        RealityView { content in
          content.camera = .virtual
          guard !diorama.hasRehearsed else { return }
          let holder = diorama.makeHolder()
          content.add(holder)
          shown.holder = holder
          diorama.startRehearsal(from: content) { finish() }
        }
      }
    }
    .onDisappear { finish() }
    .task {
      let made = cache.diorama()
      guard !made.hasRehearsed else { return }
      cache.beginRehearsal()
      made.startLoading(priority: .utility)
      await made.untilLoaded()
      guard !made.hasRehearsed else {
        cache.endRehearsal()
        return
      }
      diorama = made
    }
  }

  /// Takes the rehearsal's view down, and lets the room's own view mount once that view has let
  /// go of its scene. SwiftUI can take a RealityView down well after it leaves, and a RealityView
  /// that mounts while another still has its scene can stay empty for good.
  private func finish() {
    guard !shown.isFinished else { return }
    shown.isFinished = true
    diorama = nil
    let holder = shown.holder
    shown.holder = nil
    Task {
      let deadline = ContinuousClock.now + Self.longestTeardown
      while holder?.scene != nil, ContinuousClock.now < deadline {
        try? await Task.sleep(for: Self.teardownCheck)
      }
      try? await Task.sleep(for: Self.settle)
      cache.endRehearsal()
    }
  }

  private static let teardownCheck = Duration.milliseconds(50)
  private static let settle = Duration.milliseconds(100)
  /// The poster stays up while the room waits, so this bounds how long a teardown can hold it.
  private static let longestTeardown = Duration.seconds(5)
}

/// What the rehearsal's view added, so that its teardown can be watched.
@MainActor
private final class Shown {
  var holder: Entity?
  var isFinished = false
}
