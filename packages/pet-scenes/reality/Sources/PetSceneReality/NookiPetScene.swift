import Foundation
import Pet
import PetScene
import SwiftUI

/// Nooki: the cat asleep in a small 3D room.
public struct NookiPetScene: PetScene {
  public let id = "nooki"
  public let title = "Nooki"

  private let cache = NookiRoomCache()
  private let styledRooms: GenzRoomCache
  private let tabs: TabStages

  public init() {
    let rooms = GenzRoomCache()
    styledRooms = rooms
    tabs = TabStages(rooms: rooms)
  }

  public let handlesTouches = true
  public let hasShop = true
  public var roomStyles: [RoomStyle] { RoomStyle.allCases }
  public var cats: [CatModel] { CatModel.allCases }

  public func makeShopPreview(item: ShopItem) -> AnyView? {
    AnyView(NookiShopPreview(item: item))
  }

  public func makePreparationView() -> AnyView? {
    AnyView(NookiRehearsal(cache: cache))
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

  public func makeShopScene(
    state: ShopSceneState, onEvent: @escaping @MainActor (ShopSceneEvent) -> Void
  ) -> AnyView? {
    AnyView(ShopSceneView(state: state, stages: tabs, onEvent: onEvent))
  }

  public func makeDeskScene(
    state: DeskSceneState, onEvent: @escaping @MainActor (DeskSceneEvent) -> Void
  ) -> AnyView? {
    AnyView(DeskSceneView(state: state, stages: tabs, onEvent: onEvent))
  }

  public func makeOnboardingScene(
    state: OnboardingSceneState, onEvent: @escaping @MainActor (OnboardingSceneEvent) -> Void
  ) -> AnyView? {
    AnyView(OnboardingSceneView(state: state, stages: tabs, onEvent: onEvent))
  }

  public func posePNG(_ pose: PetPose) -> Data? {
    guard
      let url = Bundle.module.url(forResource: "pose-\(pose.rawValue)", withExtension: "png")
    else { return nil }
    return try? Data(contentsOf: url)
  }
}
