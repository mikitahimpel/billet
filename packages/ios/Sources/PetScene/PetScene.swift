import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// What a scene reports back to the pet. Each event names the delivery it belongs to.
public enum PetSceneEvent: Hashable, Sendable {
  case deliveryFinished(delivery: Int)
  case settled(delivery: Int)
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
  public var noteWall: PetSceneNoteWall? { nil }
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
