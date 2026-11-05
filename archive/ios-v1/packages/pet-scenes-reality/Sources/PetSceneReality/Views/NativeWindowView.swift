import CoreGraphics
import Foundation
import Observation
import Pet
import PetScene
import SwiftUI

/// The still planes of the views, each painted once into a bitmap for its view, hour, weather and
/// size, and kept while that look is shown. Painting waits for the next turn of the main actor,
/// so asking never stalls a frame; `version` moves on when a plate is ready.
@MainActor
@Observable
final class ViewPlateCache {
  struct Key: Hashable {
    var look: ViewLook
    var plane: ViewPlane
    /// The plate's width in pixels, rounded so small size changes reuse it.
    var pixels: Int
  }

  private(set) var version = 0
  @ObservationIgnored private var plates: [Key: CGImage] = [:]
  @ObservationIgnored private var waiting: [Key] = []
  @ObservationIgnored private var painting: Task<Void, Never>?

  /// True when no plate is waiting to be painted.
  var isIdle: Bool { waiting.isEmpty && painting == nil }

  /// The plate for `key`, or `nil` while it is being painted.
  func plate(_ key: Key) -> CGImage? {
    if let plate = plates[key] { return plate }
    if !waiting.contains(key) {
      waiting.append(key)
      startPainting()
    }
    return nil
  }

  private func startPainting() {
    guard painting == nil else { return }
    painting = Task { @MainActor [weak self] in
      while let self, !self.waiting.isEmpty {
        let key = self.waiting.removeFirst()
        if let image = Self.paint(key) {
          // Only the look being asked for stays: an old hour or weather is let go.
          self.plates = self.plates.filter {
            $0.key.look == key.look && $0.key.pixels == key.pixels
          }
          self.plates[key] = image
          self.version += 1
        }
        await Task.yield()
      }
      self?.painting = nil
    }
  }

  static func paint(_ key: Key) -> CGImage? {
    let plate = ViewStage.plate
    let recipe = ViewRecipes.recipe(for: key.look.view)
    let renderer = ImageRenderer(
      content: Canvas { context, size in
        context.scaleBy(x: size.width / plate.width, y: size.height / plate.height)
        context.translateBy(x: -plate.minX, y: -plate.minY)
        recipe.paint(key.plane, context, look: key.look)
        // A fine grain over whatever was painted, a pixel to a grain, so flat shapes read as
        // made rather than filled.
        if let grain = ViewGrain.tile {
          var grained = context
          grained.blendMode = .sourceAtop
          grained.fill(
            Path(plate),
            with: .tiledImage(
              Image(decorative: grain, scale: 1), origin: CGPoint(x: plate.minX, y: plate.minY),
              scale: plate.width / CGFloat(max(key.pixels, 1))))
        }
      }
      .frame(width: plate.width, height: plate.height))
    renderer.scale = CGFloat(key.pixels) / plate.width
    renderer.isOpaque = false
    return renderer.cgImage
  }
}

/// A window view drawn natively, filling the scene behind the room: the sky over everything,
/// then each plane's plate and life from the back, the weather in the air, and the glass, all but
/// the sky seen only through the window's opening. With the view in 3D, only the sky.
struct NativeWindowView: View {
  let state: WindowViewState
  let plates: ViewPlateCache
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    let look = ViewLook(view: state.view, hour: state.hour, weather: state.weather)
    let moment = ViewMoment(look: look, now: state.now, time: state.time)
    let recipe = ViewRecipes.recipe(for: state.view)
    let live = ViewStage.Frame(window: state.window)
    let home = ViewStage.Frame(window: state.home) ?? live
    ZStack {
      Canvas { context, size in
        guard let live, let home else {
          context.fill(
            Path(CGRect(origin: .zero, size: size)), with: .color(moment.palette.skyTop.color()))
          return
        }
        let frame = ViewStage.Frame.blend(home: home, live: live, follow: ViewSky.follow)
        ViewSky.draw(context, size: size, frame: frame, moment: moment, moon: recipe.moon)
      }
      // In 3D the room draws the street through the window itself, over this sky.
      if let live, let home, !state.inDepth {
        ZStack {
          ForEach(ViewPlane.allCases, id: \.self) { plane in
            let frame = ViewStage.Frame.blend(home: home, live: live, follow: plane.follow)
            plateImage(look: look, plane: plane, frame: frame, home: home)
            haze(after: plane, frame: frame, moment: moment)
            if recipe.livePlanes.contains(plane) {
              Canvas { context, _ in
                var context = context
                context.translateBy(x: frame.origin.x, y: frame.origin.y)
                context.scaleBy(x: frame.unit, y: frame.unit)
                recipe.life(plane, context, moment: moment)
              }
            }
          }
          Canvas { context, _ in
            ViewAir.draw(
              context, frame: ViewStage.Frame.blend(home: home, live: live, follow: 0.7),
              moment: moment)
            ViewGlass.draw(context, frame: live, moment: moment, lampOn: state.lampOn)
          }
        }
        .clipShape(Opening(points: state.window))
      }
    }
    .allowsHitTesting(false)
  }

  @ViewBuilder
  private func plateImage(
    look: ViewLook, plane: ViewPlane, frame: ViewStage.Frame, home: ViewStage.Frame
  )
    -> some View
  {
    let stage = ViewStage.plate
    let pixels = Int((stage.width * home.unit * max(displayScale, 1) / 64).rounded(.up)) * 64
    let _ = plates.version
    if let plate = plates.plate(.init(look: look, plane: plane, pixels: pixels)) {
      let origin = frame.point(stage.origin)
      let size = CGSize(width: stage.width * frame.unit, height: stage.height * frame.unit)
      Image(decorative: plate, scale: 1)
        .resizable()
        .interpolation(.high)
        .frame(width: size.width, height: size.height)
        .position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }
  }

  /// Air between the planes: haze always far off, thicker in rain, snow and fog. It slowly
  /// thickens and thins, so fog seems to move.
  @ViewBuilder
  private func haze(after plane: ViewPlane, frame: ViewStage.Frame, moment: ViewMoment) -> some View
  {
    let palette = moment.palette
    let depth: Double =
      switch plane {
      case .far: 1
      case .middle: 0.55
      case .street: 0.18
      case .near: 0
      }
    let breathing = 0.85 + 0.15 * sin(moment.now * 0.11 + Double(plane.rawValue))
    let level = palette.haze * depth * breathing
    if level > 0.01 {
      let top = frame.point(CGPoint(x: 0, y: 10)).y
      let bottom = frame.point(CGPoint(x: 0, y: 60)).y
      LinearGradient(
        stops: [
          .init(color: palette.hazeColour.color(0), location: 0),
          .init(color: palette.hazeColour.color(0.55 * level), location: 0.55),
          .init(color: palette.hazeColour.color(0.4 * level), location: 1),
        ], startPoint: .top, endPoint: .bottom
      )
      .frame(height: max(bottom - top, 1))
      .position(x: frame.point(CGPoint(x: 50, y: 0)).x, y: (top + bottom) / 2)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

/// The window's opening as a shape, a little larger than the glass so its edges hide behind the
/// frame. With no outline yet, the whole view.
struct Opening: Shape {
  var points: [CGPoint]

  func path(in rect: CGRect) -> Path {
    guard points.count > 2 else { return Path(rect) }
    let centre = CGPoint(
      x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
      y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
    var path = Path()
    path.addLines(
      points.map {
        CGPoint(x: centre.x + ($0.x - centre.x) * 1.03, y: centre.y + ($0.y - centre.y) * 1.03)
      })
    path.closeSubpath()
    return path
  }
}
