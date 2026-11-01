import Foundation
import Pet
import SwiftUI

/// What a scene reports back to the pet. Each event names the delivery it belongs to.
public enum PetSceneEvent: Hashable, Sendable {
  case deliveryFinished(delivery: Int)
  case settled(delivery: Int)
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

  /// `world` changes while the view stays alive, so the view reacts to the new value.
  func makeView(
    world: PetWorld,
    onEvent: @escaping @MainActor (PetSceneEvent) -> Void
  ) -> AnyView

  /// PNG data for a pose, or `nil` when the scene has none.
  func posePNG(_ pose: PetPose) -> Data?
}

extension PetScene {
  public var credit: String? { nil }
}

extension PetMachine.Event {
  public init(_ event: PetSceneEvent) {
    switch event {
    case .deliveryFinished(let delivery):
      self = .deliveryFinished(delivery: delivery)
    case .settled(let delivery):
      self = .settled(delivery: delivery)
    }
  }
}
