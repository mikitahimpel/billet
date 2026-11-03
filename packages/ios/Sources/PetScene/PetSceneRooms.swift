import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// One flat layer of a styled room. Each is drawn natively today; an artist's Rive file can take
/// any one over through ``RoomLayerArt`` without the room changing.
public enum RoomLayerSlot: String, CaseIterable, Hashable, Sendable {
  /// Sunset Lamp, behind the room: the night city seen through the window.
  case sunsetCity
  /// Sunset Lamp, a texture on the back wall: the lamp's orange disc.
  case sunsetDisc
  /// Sunset Lamp, a texture in the poster frame.
  case sunsetPoster
  /// Sunset Lamp, over the room: the LED strip's bloom.
  case sunsetBloom
  /// Sunset Lamp, over the room: the dark the room opens in, before the lamp clicks on.
  case sunsetDim
  /// Window Seat, behind the room and filling the screen: sky, suburb, street lamp, power lines.
  case windowNight
  /// Window Seat, over the room: the LED bloom around the window frame.
  case windowBloom
  /// Window Seat, over the room: the street light coming through the note's paper.
  case windowBacklight
  /// Window Seat, over the room: the dark the room opens in.
  case windowDim

  /// Whether the layer is a texture on a surface of the room rather than a view over or under it.
  public var isTexture: Bool {
    switch self {
    case .sunsetDisc, .sunsetPoster: true
    case .sunsetCity, .sunsetBloom, .sunsetDim, .windowNight, .windowBloom, .windowBacklight,
      .windowDim:
      false
    }
  }
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

  public init(
    time: Double = 0, parallax: CGSize = .zero, outline: [CGPoint] = [], warmth: Double = 0,
    lampOn: Bool = true
  ) {
    self.time = time
    self.parallax = parallax
    self.outline = outline
    self.warmth = warmth
    self.lampOn = lampOn
  }
}

/// Art for a styled room's flat layers. Return `nil` for a slot to keep the room's own drawing.
@MainActor
public protocol RoomLayerArt {
  /// A view for a slot that is not a texture, sized to the whole scene.
  func view(for slot: RoomLayerSlot, state: RoomLayerState) -> AnyView?
  /// An image for a texture slot, at most `pixels` on its longer side.
  func image(for slot: RoomLayerSlot, state: RoomLayerState, pixels: Int) -> CGImage?
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
  /// Bumped by the host to play a styled room's opening again.
  @Entry public var petSceneOpeningCount = 0
}
