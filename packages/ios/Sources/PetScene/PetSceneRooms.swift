import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// One flat layer of a styled room. Each is drawn natively today; an artist's Rive file can take
/// any one over through ``RoomLayerArt`` without the room changing.
public enum RoomLayerSlot: String, CaseIterable, Hashable, Sendable {
  /// Window Seat, behind the room and filling the screen: sky, suburb, street lamp, power lines.
  case windowNight
  /// Window Seat, over the room: the LED bloom around the window frame.
  case windowBloom
  /// Window Seat, over the room: the street light coming through the note's paper.
  case windowBacklight
  /// Window Seat, over the room: the dark the room opens in.
  case windowDim

}

/// What a room layer is drawn from at one moment.
public struct RoomLayerState: Equatable, Sendable {
  /// Seconds since the room started opening.
  public var time: Double
  /// How far the camera has turned from its home view, in points the layer should slide.
  public var parallax: CGSize
  /// The outline the layer follows, in the view's points: the LED strip, the window's opening or
  /// the note's paper. Empty for a layer that fills the view.
  public var outline: [CGPoint]
  /// From 0 to 1, how warm the room is: it rises for a moment when a note lands.
  public var warmth: Double
  /// False while the room's own lamp is off.
  public var lampOn: Bool
  /// From 0 to 1, how bright the LED strip round the window is as the room's light switch has it.
  public var ledLevel: Double

  public init(
    time: Double = 0, parallax: CGSize = .zero, outline: [CGPoint] = [], warmth: Double = 0,
    lampOn: Bool = true, ledLevel: Double = 1
  ) {
    self.time = time
    self.parallax = parallax
    self.outline = outline
    self.warmth = warmth
    self.lampOn = lampOn
    self.ledLevel = ledLevel
  }
}

/// Art for a styled room's flat layers. Return `nil` for a slot to keep the room's own drawing.
@MainActor
public protocol RoomLayerArt {
  /// A view for a slot, sized to the whole scene.
  func view(for slot: RoomLayerSlot, state: RoomLayerState) -> AnyView?
}

/// Where the cat is on screen, so the host can pin a control beside it.
public struct PetSceneCatAnchorKey: PreferenceKey {
  public static let defaultValue: Anchor<CGPoint>? = nil

  public static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
    value = nextValue() ?? value
  }
}

extension EnvironmentValues {
  /// The cat a scene with more than one cat should show. Scenes with one cat ignore it.
  @Entry public var petSceneCat: CatChoice = .standard
  /// Art that replaces some of a styled room's flat layers. `nil` keeps every native drawing.
  @Entry public var petSceneRoomArt: (any RoomLayerArt)? = nil
}
