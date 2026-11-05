import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// Paints a flat window view into images for a window pane in a 3D room.
///
/// The sky and each plane's still art are painted once per look (`prepare`), which is the slow
/// part. A frame (`frame`) then lays those plates out and draws only what moves over them:
/// lit windows, cars, rain, snow, fireflies, the haze and the glass. The pane shows the stage's
/// window, 100 units wide, from its top edge down.
@MainActor
public final class WindowPainter {
  public let size: CGSize
  private var look: ViewLook?
  private var sky: CGImage?
  private var skyPainted = -Double.infinity
  private var plates: [ViewPlane: CGImage] = [:]
  private let started = Date().timeIntervalSince1970

  /// A painter for panes of `size` pixels.
  public init(size: CGSize) {
    self.size = size
  }

  /// Whether `view` has anything that moves, worth painting more than once per look.
  public static func moves(_ view: WindowView) -> Bool {
    !ViewRecipes.recipe(for: view).livePlanes.isEmpty || view.weather != .clear
  }

  /// Paints the still parts of `view` at `hour` in `weather`, unless they are painted already.
  /// Returns whether anything was repainted.
  @discardableResult
  public func prepare(_ view: WindowView, hour: ViewHour, weather: ViewWeather) -> Bool {
    let look = ViewLook(view: view, hour: hour, weather: weather)
    guard look != self.look else { return false }
    self.look = look
    sky = nil
    plates = [:]
    let recipe = ViewRecipes.recipe(for: view)
    let frame = stageFrame
    for plane in ViewPlane.allCases {
      plates[plane] = render { context in
        var context = context
        context.translateBy(x: frame.origin.x, y: frame.origin.y)
        context.scaleBy(x: frame.unit, y: frame.unit)
        recipe.paint(plane, context, look: look)
      }
    }
    return true
  }

  /// One frame of the prepared view at `now` (wall-clock seconds): the plates with the view's life
  /// over them. `nil` before `prepare`.
  public func frame(now: Double = Date().timeIntervalSince1970) -> CGImage? {
    guard let look else { return nil }
    let moment = ViewMoment(look: look, now: now, time: now - started + 30)
    let recipe = ViewRecipes.recipe(for: look.view)
    let frame = stageFrame
    // Stars twinkle and clouds drift slowly: the sky is repainted every few seconds, not each frame.
    if sky == nil || now - skyPainted > 4 {
      let size = size
      sky = render { context in
        ViewSky.draw(context, size: size, frame: frame, moment: moment, moon: recipe.moon)
      }
      skyPainted = now
    }
    let plates = plates
    let sky = sky
    let size = size
    return render { context in
      let whole = CGRect(origin: .zero, size: size)
      if let sky { context.draw(Image(decorative: sky, scale: 1), in: whole) }
      for plane in ViewPlane.allCases {
        if let plate = plates[plane] { context.draw(Image(decorative: plate, scale: 1), in: whole) }
        Self.haze(context, after: plane, frame: frame, moment: moment, width: size.width)
        if recipe.livePlanes.contains(plane) {
          var life = context
          life.translateBy(x: frame.origin.x, y: frame.origin.y)
          life.scaleBy(x: frame.unit, y: frame.unit)
          recipe.life(plane, life, moment: moment)
        }
      }
      ViewAir.draw(context, frame: frame, moment: moment)
      ViewGlass.draw(context, frame: frame, moment: moment, lampOn: true)
    }
  }

  /// The stage laid over the pane: the window's 100 units across its width, its top at the top.
  private var stageFrame: ViewStage.Frame {
    ViewStage.Frame(unit: size.width / 100, origin: .zero)
  }

  private func render(_ draw: @escaping (GraphicsContext) -> Void) -> CGImage? {
    let size = size
    let renderer = ImageRenderer(
      content: Canvas { context, _ in draw(context) }.frame(width: size.width, height: size.height))
    renderer.scale = 1
    renderer.isOpaque = false
    return renderer.cgImage
  }

  /// Air between the planes, as the old room drew it: haze far off, thicker in rain, snow and fog,
  /// slowly thickening and thinning so fog seems to move.
  static func haze(
    _ context: GraphicsContext, after plane: ViewPlane, frame: ViewStage.Frame, moment: ViewMoment,
    width: CGFloat
  ) {
    let depth: Double =
      switch plane {
      case .far: 1
      case .middle: 0.55
      case .street: 0.18
      case .near: 0
      }
    let palette = moment.palette
    let breathing = 0.85 + 0.15 * sin(moment.now * 0.11 + Double(plane.rawValue))
    let level = palette.haze * depth * breathing
    guard level > 0.01 else { return }
    let top = frame.point(CGPoint(x: 0, y: 10)).y
    let bottom = frame.point(CGPoint(x: 0, y: 60)).y
    context.fill(
      Path(CGRect(x: 0, y: top, width: width, height: max(bottom - top, 1))),
      with: .linearGradient(
        Gradient(stops: [
          .init(color: palette.hazeColour.color(0), location: 0),
          .init(color: palette.hazeColour.color(0.55 * level), location: 0.55),
          .init(color: palette.hazeColour.color(0.4 * level), location: 1),
        ]), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
  }
}
