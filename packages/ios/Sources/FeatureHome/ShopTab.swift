import DesignSystem
import Pet
import PetScene
import SwiftUI

/// The Shop tab: the shop's grid, with a picture of each item from the chosen scene. Tapping a
/// price buys at once; a piece goes into the room and a view into the window. Placing and trying
/// on happen in the room, so they switch to Home.
struct ShopTab: View {
  let session: PairSession
  let scene: any PetScene
  /// Shows Home, where pieces are placed and views tried on.
  let onShowRoom: () -> Void

  @State private var showsCloset = false
  @Environment(\.petSceneOnScreen) private var onScreen
  @Environment(\.appEvents) private var events

  var body: some View {
    ShopView(
      store: session.shop, checkout: session.checkout, style: session.play.roomStyle,
      thumbnail: { [scene] item, side, scale in
        await scene.shopThumbnail(item, side: side, scale: scale)
      },
      onPlace: { _ in inRoom { session.renovator.requestOpen() } },
      onTryOn: scene.hasRoom
        ? { choice in inRoom { session.renovator.requestTryOn(choice) } } : nil,
      onOpenCloset: { showsCloset = true }
    )
    .sheet(isPresented: $showsCloset) {
      ClosetView(
        store: session.shop, renovator: session.renovator,
        onOpenShop: { showsCloset = false }, onClose: { showsCloset = false }
      )
      .billetSheet([.medium, .large])
    }
    // A piece taken out of the closet is moved in the room itself.
    .onChange(of: session.renovator.placements) {
      guard showsCloset else { return }
      showsCloset = false
      onShowRoom()
    }
    .onChange(of: onScreen, initial: true) { _, shown in
      guard shown else { return }
      events(.shopOpened)
      ScenePerf.mark("shop on screen")
    }
  }

  /// Shows the room, then asks it for something once Home is on screen to hear it.
  private func inRoom(_ ask: @escaping @MainActor () -> Void) {
    onShowRoom()
    Task {
      try? await Task.sleep(for: Self.tabSettles)
      ask()
    }
  }

  private static let tabSettles = Duration.milliseconds(350)
}
