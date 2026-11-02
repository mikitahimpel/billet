import Foundation
import Pet
import PetScene
import SwiftUI

/// Nooki: Mochi asleep in a small 3D room.
public struct NookiPetScene: PetScene {
  public let id = "nooki"
  public let title = "Nooki"
  public let credit: String? =
    "Mochi's proportions are based on \"Chill Cat\" by Shix, CC BY 4.0, adapted into a new model."

  private let cache = NookiRoomCache()
  private let styledRooms = GenzRoomCache()

  public init() {}

  public let handlesTouches = true
  public let hasShop = true
  public var roomStyles: [RoomStyle] { RoomStyle.allCases }

  public func makeShopPreview(item: ShopItem) -> AnyView? {
    AnyView(NookiShopPreview(item: item))
  }

  public func makePreparationView() -> AnyView? {
    AnyView(NookiPreload(cache: cache))
  }

  public func makeView(
    world: PetWorld,
    onEvent: @escaping @MainActor (PetSceneEvent) -> Void
  ) -> AnyView {
    makeView(world: world, play: PetPlayState(), onEvent: onEvent)
  }

  public func makeView(
    world: PetWorld,
    play: PetPlayState,
    onEvent: @escaping @MainActor (PetSceneEvent) -> Void
  ) -> AnyView {
    AnyView(
      NookiStyledRoom(
        world: world, play: play, cache: cache, rooms: styledRooms, onEvent: onEvent))
  }

  public func posePNG(_ pose: PetPose) -> Data? {
    guard
      let url = Bundle.module.url(forResource: "pose-\(pose.rawValue)", withExtension: "png")
    else { return nil }
    return try? Data(contentsOf: url)
  }
}
