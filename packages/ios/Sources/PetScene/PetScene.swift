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
  /// The user opened the hanging note of `delivery`.
  case noteOpened(delivery: Int)
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

  /// PNG data for a pose, or `nil` when the scene has none.
  func posePNG(_ pose: PetPose) -> Data?
}

extension PetScene {
  public var credit: String? { nil }
  public var handlesTouches: Bool { false }

  public func makeView(
    world: PetWorld,
    play: PetPlayState,
    onEvent: @escaping @MainActor (PetSceneEvent) -> Void
  ) -> AnyView {
    makeView(world: world, onEvent: onEvent)
  }
}

extension PetMachine.Event {
  /// The pet's own event for a scene event, or `nil` when it concerns the host instead.
  public init?(_ event: PetSceneEvent) {
    switch event {
    case .deliveryFinished(let delivery):
      self = .deliveryFinished(delivery: delivery)
    case .settled(let delivery):
      self = .settled(delivery: delivery)
    case .petted, .noteOpened:
      return nil
    }
  }
}

extension EnvironmentValues {
  /// False while something covers the scene, so it can stop animating. Hosts set this; a scene
  /// also pauses by itself when its view leaves the screen or the app goes to the background.
  @Entry public var petSceneOnScreen = true
}
