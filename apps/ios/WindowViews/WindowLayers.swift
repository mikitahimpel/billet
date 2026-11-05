import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// One layer of a window view built in depth: the sky at the back, the four planes, and the air and
/// glass at the front.
public enum PaneLayer: Int, CaseIterable, Hashable, Sendable {
  case sky, far, middle, street, near, air

  var plane: ViewPlane? {
    switch self {
    case .far: .far
    case .middle: .middle
    case .street: .street
    case .near: .near
    case .sky, .air: nil
    }
  }

  init(_ plane: ViewPlane) {
    switch plane {
    case .far: self = .far
    case .middle: self = .middle
    case .street: self = .street
    case .near: self = .near
    }
  }
}

/// Paints a window view as separate layers, for a pane that sets each one at its own depth so the
/// view has real parallax as the room turns.
///
/// The still layers (the sky and each plane's art, with its grain and the haze in front of it)
/// are painted one at a time, sharp enough for the room's closest zoom. What moves (each live
/// plane's life, the weather in the air, the glass) is painted together into one atlas, a slice
/// per layer, so a frame of life costs one picture and one upload.
@MainActor
public final class WindowLayerPainter {
  /// The stage units every still layer covers: the window, 100 × `windowHeight`, with room around
  /// it to slide into view as the room turns.
  public static let stillArea = CGRect(x: -40, y: -35, width: 180, height: 100)
  /// What the moving layers cover, closer around the window: life far outside it is never seen.
  public static let lifeArea = CGRect(x: -15, y: -12, width: 130, height: 76)
  /// The window's height in stage units; its width is 100.
  public static let windowHeight = Float(ViewStage.windowHeight)
  /// Pixels per stage unit for the moving layers.
  public static let lifeDensity: CGFloat = 5

  /// Pixels per stage unit for a still layer: the sky is soft anyway, the far plane is hazed.
  public static func density(_ layer: PaneLayer) -> CGFloat {
    switch layer {
    case .sky: 5
    case .far: 8
    case .middle, .street, .near, .air: 10
    }
  }

  /// A still layer, freshly painted.
  public struct Still {
    public let layer: PaneLayer
    public let image: CGImage
  }

  private var look: ViewLook?
  private var waiting: [PaneLayer] = []
  private var skyPainted = -Double.infinity
  private let started = Date().timeIntervalSince1970

  public init() {}

  /// The layers in the life atlas, top slice first: each live plane from the back, then the air.
  public private(set) var lifeLayers: [PaneLayer] = [.air]

  /// Whether the prepared view moves, worth painting its life more than once.
  public private(set) var moves = false

  /// The colour behind everything, for anything the layers don't cover.
  public var backdrop: (red: Float, green: Float, blue: Float) {
    let colour = look?.palette.skyMiddle ?? ViewColour(0x8FA6C0)
    return (Float(colour.red), Float(colour.green), Float(colour.blue))
  }

  /// Takes `view` at `hour` in `weather`, unless it is the look already shown: its still layers are
  /// then painted one per `nextStill`. Returns whether the look changed.
  @discardableResult
  public func prepare(_ view: WindowView, hour: ViewHour, weather: ViewWeather) -> Bool {
    let look = ViewLook(view: view, hour: hour, weather: weather)
    guard look != self.look else { return false }
    self.look = look
    let recipe = ViewRecipes.recipe(for: view)
    lifeLayers = ViewPlane.allCases.filter(recipe.livePlanes.contains).map(PaneLayer.init) + [.air]
    moves = WindowPainter.moves(view)
    waiting = [.sky, .far, .middle, .street, .near]
    return true
  }

  /// The next still layer, painted now, or `nil` when all are painted. A new look's layers come one
  /// per call, so changing views is spread over frames; the sky comes again every few seconds for
  /// its stars and clouds.
  public func nextStill(now: Double = Date().timeIntervalSince1970) -> Still? {
    guard let look else { return nil }
    if waiting.isEmpty, now - skyPainted > 4 { waiting = [.sky] }
    guard !waiting.isEmpty else { return nil }
    let layer = waiting.removeFirst()
    if layer == .sky { skyPainted = now }
    guard let image = Self.paint(layer, look: look, now: now, time: now - started + 30) else {
      return nil
    }
    return Still(layer: layer, image: image)
  }

  /// The life atlas at `now`: `lifeLayers.count` slices of `lifeArea`, stacked top to bottom.
  public func life(now: Double = Date().timeIntervalSince1970) -> CGImage? {
    guard let look else { return nil }
    let moment = ViewMoment(look: look, now: now, time: now - started + 30)
    let recipe = ViewRecipes.recipe(for: look.view)
    let area = Self.lifeArea
    let density = Self.lifeDensity
    let slice = CGSize(width: area.width * density, height: area.height * density)
    let layers = lifeLayers
    return Self.render(CGSize(width: slice.width, height: slice.height * CGFloat(layers.count))) {
      context in
      for (index, layer) in layers.enumerated() {
        var slot = context
        slot.clip(to: Path(CGRect(x: 0, y: slice.height * CGFloat(index), width: slice.width, height: slice.height)))
        let frame = ViewStage.Frame(
          unit: density,
          origin: CGPoint(x: -area.minX * density, y: slice.height * CGFloat(index) - area.minY * density))
        if let plane = layer.plane {
          slot.translateBy(x: frame.origin.x, y: frame.origin.y)
          slot.scaleBy(x: density, y: density)
          recipe.life(plane, slot, moment: moment)
        } else {
          ViewAir.draw(slot, frame: frame, moment: moment)
          ViewGlass.draw(slot, frame: frame, moment: moment, lampOn: true)
        }
      }
    }
  }

  static func paint(_ layer: PaneLayer, look: ViewLook, now: Double, time: Double) -> CGImage? {
    let area = stillArea
    let density = density(layer)
    let size = CGSize(width: area.width * density, height: area.height * density)
    let frame = ViewStage.Frame(
      unit: density, origin: CGPoint(x: -area.minX * density, y: -area.minY * density))
    let moment = ViewMoment(look: look, now: now, time: time)
    let recipe = ViewRecipes.recipe(for: look.view)
    return render(size) { context in
      guard let plane = layer.plane else {
        ViewSky.draw(context, size: size, frame: frame, moment: moment, moon: recipe.moon)
        return
      }
      var art = context
      art.translateBy(x: frame.origin.x, y: frame.origin.y)
      art.scaleBy(x: density, y: density)
      recipe.paint(plane, art, look: look)
      // The old room's fine grain, a pixel to a grain, so flat shapes read as made, not filled.
      if let grain = ViewGrain.tile {
        var grained = art
        grained.blendMode = .sourceAtop
        grained.fill(
          Path(area),
          with: .tiledImage(
            Image(decorative: grain, scale: 1), origin: area.origin, scale: 1 / density))
      }
      // The haze in front of this plane veils everything behind it too, so it fills the layer.
      WindowPainter.haze(context, after: plane, frame: frame, moment: moment, width: size.width)
    }
  }

  private static func render(_ size: CGSize, _ draw: @escaping (GraphicsContext) -> Void) -> CGImage? {
    let renderer = ImageRenderer(
      content: Canvas { context, _ in draw(context) }.frame(width: size.width, height: size.height))
    renderer.scale = 1
    renderer.isOpaque = false
    return renderer.cgImage
  }
}
