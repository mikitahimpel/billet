import Foundation
import Pet
import PetScene
import SwiftUI

/// Nooki: the cat in its Window Seat room, with the shop, the desk and the first launch as 3D
/// stages of their own.
public struct NookiPetScene: PetScene {
  public let id = "nooki"
  public let title = "Nooki"

  private let rooms: GenzRoomCache
  private let tabs: TabStages

  public init() {
    let rooms = GenzRoomCache()
    self.rooms = rooms
    tabs = TabStages(rooms: rooms)
  }

  public let handlesTouches = true
  public let hasShop = true
  public let hasRoom = true
  /// Every cat, except splat cats on a build or device that can't draw splats: there they would
  /// only repeat the Idol mesh they fall back to.
  public var cats: [CatModel] {
    CatModel.allCases.filter { $0.splatBody == nil || SplatCat.isAvailable }
  }

  public func makeShopPreview(item: ShopItem) -> AnyView? {
    AnyView(NookiShopPreview(item: item))
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
    AnyView(NookiRoom(world: world, play: play, rooms: rooms, onEvent: onEvent))
  }

  public func makeTabRehearsal(shop: ShopSceneState?, desk: Bool) -> AnyView? {
    AnyView(TabRehearsal(stages: tabs, shop: shop, desk: desk))
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

  public func makeAdoptionScene(
    state: AdoptionSceneState, onEvent: @escaping @MainActor (AdoptionSceneEvent) -> Void
  ) -> AnyView? {
    AnyView(AdoptionSceneView(state: state, stages: tabs, onEvent: onEvent))
  }

  public func makeFlameScene(
    state: FlameSceneState, onEvent: @escaping @MainActor (FlameSceneEvent) -> Void
  ) -> AnyView? {
    AnyView(FlameSceneView(state: state, stages: tabs, onEvent: onEvent))
  }

  public func posePNG(_ pose: PetPose) -> Data? {
    guard
      let url = Bundle.module.url(forResource: "pose-\(pose.rawValue)", withExtension: "png")
    else { return nil }
    return try? Data(contentsOf: url)
  }
}
