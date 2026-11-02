import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// What a scene reports back to the pet. Each event names the delivery it belongs to.
public enum PetSceneEvent: Hashable, Sendable {
  case deliveryFinished(delivery: Int)
  case settled(delivery: Int)
  /// The user petted the pet in the scene. Same meaning as a pet given from any other control, so
  /// the host tells the partner the same way.
  case petted
  /// The user played with the pet in the scene, such as by moving a finger it batted at.
  case played
  /// The user opened the hanging note of `delivery`.
  case noteOpened(delivery: Int)
}

/// Where a scene's own note sits, so the received drawing can be laid exactly over it. Rects are in
/// the scene's artboard, which is fitted and centred in the scene's view.
public struct PetSceneNoteWall: Hashable, Sendable {
  public var artboard: CGSize
  public var paper: CGRect
  /// The point the paper swings from.
  public var peg: CGPoint
  /// How long into a delivery the scene's note first shows.
  public var revealDelay: Duration

  public init(artboard: CGSize, paper: CGRect, peg: CGPoint, revealDelay: Duration) {
    self.artboard = artboard
    self.paper = paper
    self.peg = peg
    self.revealDelay = revealDelay
  }
}

/// One way of showing the pet, usually backed by a graphics engine.
///
/// A scene only shows ``PetWorld`` and reports events; it never decides what happens next. It has
/// to cope with appearing at any point of a delivery, because the user can switch scenes during
/// one. Implementations live in their own packages, and only the App target links them.
@MainActor
public protocol PetScene {
  /// Stable across releases: it is what gets stored as the user's choice.
  var id: String { get }
  var title: String { get }
  /// Attribution the scene's assets require, shown with the scene list.
  var credit: String? { get }
  /// `nil` when the scene draws its own note and no drawing can be laid over it.
  var noteWall: PetSceneNoteWall? { get }

  /// True when the scene takes touches itself and reports ``PetSceneEvent/petted``, so the host
  /// must not lay its own pet target over it.
  var handlesTouches: Bool { get }

  /// `world` changes while the view stays alive, so the view reacts to the new value.
  func makeView(
    world: PetWorld,
    onEvent: @escaping @MainActor (PetSceneEvent) -> Void
  ) -> AnyView

  /// As ``makeView(world:onEvent:)``, for scenes that also show the pair's play. A change of `play`
  /// never restarts a step of `world`.
  func makeView(
    world: PetWorld,
    play: PetPlayState,
    onEvent: @escaping @MainActor (PetSceneEvent) -> Void
  ) -> AnyView

  /// True when the scene draws what the shop puts in the room and previews its items.
  var hasShop: Bool { get }

  /// The room styles the scene can show, chosen through ``EnvironmentValues/petSceneRoomStyle``.
  /// Empty for a scene with one look.
  var roomStyles: [RoomStyle] { get }

  /// The cats the scene can show, chosen through ``EnvironmentValues/petSceneCat``. Empty for a
  /// scene with one cat.
  var cats: [CatModel] { get }

  /// A live 3D preview of `item` that turns slowly, or `nil` when the scene has none. The host
  /// keeps one preview view alive and hands it a new item, so the view must swap models rather
  /// than rebuild.
  func makeShopPreview(item: ShopItem) -> AnyView?

  /// PNG data for a pose, or `nil` when the scene has none.
  func posePNG(_ pose: PetPose) -> Data?

  /// A view the host keeps out of sight, from after the app's first frame while another scene
  /// is showing. A scene that is slow to open does that work here, at low priority.
  func makePreparationView() -> AnyView?

  /// The shop as a 3D room with a keeper behind the counter, or `nil` when the scene has none.
  /// `state` changes while the view stays alive. The view mounts its renderer only once
  /// ``EnvironmentValues/petSceneOnScreen`` is true, so a host keeps it in a tab.
  func makeShopScene(
    state: ShopSceneState, onEvent: @escaping @MainActor (ShopSceneEvent) -> Void
  ) -> AnyView?

  /// The notes as a desk with paper under a board of pinned notes, or `nil` when the scene has
  /// none. Mounts like ``makeShopScene(state:onEvent:)``.
  func makeDeskScene(
    state: DeskSceneState, onEvent: @escaping @MainActor (DeskSceneEvent) -> Void
  ) -> AnyView?

  /// The first-launch scene, or `nil` when the scene has none. `state` changes while the view
  /// stays alive. It mounts its renderer as soon as it is on screen.
  func makeOnboardingScene(
    state: OnboardingSceneState, onEvent: @escaping @MainActor (OnboardingSceneEvent) -> Void
  ) -> AnyView?
}

extension PetScene {
  public var credit: String? { nil }
  public var noteWall: PetSceneNoteWall? { nil }
  public var handlesTouches: Bool { false }
  public var hasShop: Bool { false }
  public var roomStyles: [RoomStyle] { [] }
  public var cats: [CatModel] { [] }
  public func makeShopPreview(item: ShopItem) -> AnyView? { nil }

  public func makeView(
    world: PetWorld,
    play: PetPlayState,
    onEvent: @escaping @MainActor (PetSceneEvent) -> Void
  ) -> AnyView {
    makeView(world: world, onEvent: onEvent)
  }
  public func makePreparationView() -> AnyView? { nil }

  public func makeShopScene(
    state: ShopSceneState, onEvent: @escaping @MainActor (ShopSceneEvent) -> Void
  ) -> AnyView? { nil }

  public func makeDeskScene(
    state: DeskSceneState, onEvent: @escaping @MainActor (DeskSceneEvent) -> Void
  ) -> AnyView? { nil }

  public func makeOnboardingScene(
    state: OnboardingSceneState, onEvent: @escaping @MainActor (OnboardingSceneEvent) -> Void
  ) -> AnyView? { nil }
}

extension PetMachine.Event {
  /// The pet's own event for a scene event, or `nil` when it concerns the host instead.
  public init?(_ event: PetSceneEvent) {
    switch event {
    case .deliveryFinished(let delivery):
      self = .deliveryFinished(delivery: delivery)
    case .settled(let delivery):
      self = .settled(delivery: delivery)
    case .petted, .played, .noteOpened:
      return nil
    }
  }
}

extension EnvironmentValues {
  /// False while something covers the scene, so it can stop animating. Hosts set this; a scene
  /// also pauses by itself when its view leaves the screen or the app goes to the background.
  @Entry public var petSceneOnScreen = true
  /// Links a scene's renovate mode to the closet. `nil` when the host has no shop.
  @Entry public var petSceneRenovator: RoomRenovator?
  /// The drawing of the note being delivered, for scenes that show it themselves.
  @Entry public var petSceneDrawing: CGImage? = nil
}
