import RealityKit
import SwiftUI

/// Builds the room out of sight and draws it a few times in a real RealityView, which is the
/// costly first use of the engine, so that the stalls happen before anyone is looking.
struct NookiRehearsal: View {
  let cache: NookiRoomCache

  /// Cleared when the rehearsal ends, so that only the cache keeps the room.
  @State private var diorama: NookiDiorama?

  var body: some View {
    ZStack {
      if let diorama {
        RealityView { content in
          content.camera = .virtual
          content.add(diorama.root)
          diorama.startRehearsal(from: content) { self.diorama = nil }
        }
      }
    }
    .task {
      let made = cache.diorama()
      guard !made.hasRehearsed else { return }
      made.startLoading(priority: .utility)
      await made.untilLoaded()
      diorama = made
    }
  }
}
