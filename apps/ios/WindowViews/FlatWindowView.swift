import CoreGraphics
import Foundation
import Pet
import QuartzCore
import SwiftUI
import UIKit

/// A window view drawn flat at the screen's own pixels, as the old room drew its views: put it
/// behind a 3D room whose window is a hole, and feed it where the window lands on screen each frame.
///
/// The sky, each plane's plate (with the old grain), the haze between the planes, each live plane's
/// life, the weather in the air and the glass are layers of their own. A camera move only moves
/// them, each plane following the window by its own share (`ViewPlane.follow`), which is the
/// parallax; nothing is repainted for it. The plates are painted once per look and size, one per
/// turn of the main actor. The life, the sky's slow changes and the haze's breathing are
/// repainted `lifeRate` times a second, only while `tick` is called and only if the view moves.
@MainActor
public final class FlatWindowView: UIView {
  /// How often a moving view's life is repainted, per second.
  public static let lifeRate: Double = 8
  /// How often the sky is repainted for its stars, clouds and planes, in seconds.
  static let skyInterval: Double = 20
  /// How far the window may move on screen in a frame, in points, before the room counts as being
  /// turned or zoomed and the life holds still: the room's slow idle sway stays under it.
  static let still: CGFloat = 1.5
  /// What a live plane's life covers, in stage units: the window and a margin for parallax.
  static let lifeArea = CGRect(x: -20, y: -16, width: 140, height: 80)
  /// The widest plate painted, in pixels, whatever the zoom.
  static let maxPlatePixels = 4096
  /// The widest life or sky picture painted, in pixels.
  static let maxLifePixels = 2048

  private let opening = CALayer()
  private let clip = CAShapeLayer()
  private let sky = CALayer()
  private var plates: [ViewPlane: CALayer] = [:]
  private var hazes: [ViewPlane: CAGradientLayer] = [:]
  private var lives: [ViewPlane: CALayer] = [:]
  private let air = CALayer()
  private let glass = CALayer()

  private var look: ViewLook?
  private var lampOn = true
  private var live: ViewStage.Frame?
  private var home: ViewStage.Frame?
  private var outline: [CGPoint] = []
  /// The sky frame and the box it was last painted for, so the picture can be slid in between.
  private var skyPainted: (frame: ViewStage.Frame, box: CGRect)?
  private var plateKeys: [ViewPlane: PlateKey] = [:]
  private var waiting: [PlateKey] = []
  private var painting: Task<Void, Never>?
  private var lifeAge = Double.infinity
  private var skyAge = 0.0
  /// Seconds since the window last moved faster than `still`.
  private var restingFor = Double.infinity
  private var glassPainted = false
  private let started = Date().timeIntervalSince1970

  /// True once every plate of the current look is showing.
  public private(set) var isReady = false

  struct PlateKey: Hashable {
    var look: ViewLook
    var plane: ViewPlane
    var pixels: Int
  }

  public override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isOpaque = false
    backgroundColor = .clear
    opening.mask = clip
    layer.addSublayer(opening)
    opening.addSublayer(sky)
    for plane in ViewPlane.allCases {
      let plate = CALayer()
      let haze = CAGradientLayer()
      let life = CALayer()
      for sublayer in [plate, haze, life] { opening.addSublayer(sublayer) }
      plates[plane] = plate
      hazes[plane] = haze
      lives[plane] = life
    }
    opening.addSublayer(air)
    opening.addSublayer(glass)
    for sublayer in [sky, air, glass] + Array(plates.values) + Array(lives.values) {
      sublayer.contentsGravity = .resize
      // Each picture is painted at about the size it is shown, so it needs no mipmaps.
      sublayer.minificationFilter = .linear
    }
    accessibilityElementsHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  /// Shows `view` at `hour` in `weather`. Its plates are painted over the next few turns; the old
  /// look stays up until each new plate is ready.
  public func show(_ view: WindowView, hour: ViewHour, weather: ViewWeather, lampOn: Bool) {
    let look = ViewLook(view: view, hour: hour, weather: weather)
    let lampChanged = lampOn != self.lampOn
    self.lampOn = lampOn
    guard look != self.look || lampChanged else { return }
    if look != self.look { isReady = false }
    self.look = look
    lifeAge = .infinity
    glassPainted = false
    skyPainted = nil
    for plane in ViewPlane.allCases where !Self.recipe(look).livePlanes.contains(plane) {
      lives[plane]?.contents = nil
    }
    layOut()
  }

  /// Where the window is on screen this frame (`window`, in this view's points) and where it would be
  /// with the room unturned (`home`), each as its outline; `hole` is the outline of the hole in the
  /// wall, which the view is clipped to. An empty outline hides the view.
  public func place(window: [CGPoint], home: [CGPoint], hole: [CGPoint]) {
    let live = ViewStage.Frame(window: window)
    let homeFrame = ViewStage.Frame(window: home) ?? live
    guard live != self.live || homeFrame != self.home || hole != outline else { return }
    if let live, let old = self.live,
      abs(live.origin.x - old.origin.x) > Self.still || abs(live.origin.y - old.origin.y) > Self.still
        || abs(live.unit - old.unit) * 100 > Self.still
    {
      restingFor = 0
    }
    self.live = live
    self.home = homeFrame
    outline = hole
    layOut()
  }

  /// Advances the view's own clock by `dt` seconds: its life, its sky and its haze move on a few
  /// times a second. Call it only while the view is on screen.
  public func tick(_ dt: Double) {
    guard let look else { return }
    lifeAge += dt
    skyAge += dt
    restingFor += dt
    // While a finger turns or zooms the room the eye follows the room, not the street: the life
    // waits, and only the layers move.
    guard lifeAge >= 1 / Self.lifeRate, restingFor > 0.3 else { return }
    guard Self.moves(look) || !glassPainted || skyAge > Self.skyInterval else { return }
    lifeAge = 0
    paintMoving(look)
  }

  // MARK: - Layout

  public override func layoutSubviews() {
    super.layoutSubviews()
    layOut()
  }

  private func layOut() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    guard let live, let home, let look, outline.count > 2 else {
      opening.isHidden = true
      return
    }
    opening.isHidden = false
    opening.frame = bounds
    clip.frame = bounds
    clip.path = Self.path(outline, grownBy: 1.03)
    let box = clip.path?.boundingBox ?? bounds

    let unit = live.unit
    for plane in ViewPlane.allCases {
      let frame = ViewStage.Frame.blend(home: home, live: live, follow: plane.follow)
      plates[plane]?.frame = Self.rect(ViewStage.plate, in: frame)
      lives[plane]?.frame = Self.rect(Self.lifeArea, in: frame)
      if let haze = hazes[plane] {
        let top = frame.point(CGPoint(x: 0, y: 10)).y
        let bottom = frame.point(CGPoint(x: 0, y: 60)).y
        haze.frame = CGRect(x: box.minX, y: top, width: box.width, height: max(bottom - top, 1))
      }
    }
    air.frame = Self.rect(
      Self.lifeArea, in: .blend(home: home, live: live, follow: 0.7))
    glass.frame = Self.rect(Self.lifeArea, in: live)
    if let skyPainted {
      let now = ViewStage.Frame.blend(home: home, live: live, follow: ViewSky.follow)
      let scale = now.unit / skyPainted.frame.unit
      let then = skyPainted.box
      sky.frame = CGRect(
        x: now.origin.x + (then.minX - skyPainted.frame.origin.x) * scale,
        y: now.origin.y + (then.minY - skyPainted.frame.origin.y) * scale,
        width: then.width * scale, height: then.height * scale)
      // A picture slid or stretched too far no longer covers the hole: paint it again now.
      if !sky.frame.contains(box) || abs(scale - 1) > 0.06 { paintSky(look) }
    } else {
      paintSky(look)
    }
    requestPlates(look, unit: unit)
  }

  static func rect(_ area: CGRect, in frame: ViewStage.Frame) -> CGRect {
    let origin = frame.point(area.origin)
    return CGRect(
      x: origin.x, y: origin.y, width: area.width * frame.unit, height: area.height * frame.unit)
  }

  /// The outline as a path, grown about its middle so its edges hide behind the wall.
  static func path(_ points: [CGPoint], grownBy factor: CGFloat) -> CGPath {
    let count = CGFloat(points.count)
    let centre = CGPoint(
      x: points.map(\.x).reduce(0, +) / count, y: points.map(\.y).reduce(0, +) / count)
    let path = CGMutablePath()
    path.addLines(
      between: points.map {
        CGPoint(
          x: centre.x + ($0.x - centre.x) * factor, y: centre.y + ($0.y - centre.y) * factor)
      })
    path.closeSubpath()
    return path
  }

  private var pixelScale: CGFloat { max(window?.screen.scale ?? traitCollection.displayScale, 1) }

  // MARK: - Plates

  /// A plate's width in pixels for a window `unit` points per stage unit: the screen's own pixels,
  /// rounded up to a step of a quarter more, so a pinch repaints a few times rather than every
  /// frame.
  static func platePixels(unit: CGFloat, scale: CGFloat) -> Int {
    let exact = ViewStage.plate.width * unit * scale
    guard exact > 64 else { return 64 }
    let step = pow(1.25, ceil(log(exact / 64) / log(1.25)))
    return min(Int((64 * step).rounded(.up)), maxPlatePixels)
  }

  private func requestPlates(_ look: ViewLook, unit: CGFloat) {
    let pixels = Self.platePixels(unit: unit, scale: pixelScale)
    for plane in ViewPlane.allCases {
      let key = PlateKey(look: look, plane: plane, pixels: pixels)
      guard plateKeys[plane] != key, !waiting.contains(key) else { continue }
      // A plate painted for a bigger window looks as sharp: only a new look or a closer zoom repaints.
      if let shown = plateKeys[plane], shown.look == look, shown.pixels >= pixels { continue }
      waiting.removeAll { $0.plane == plane }
      waiting.append(key)
    }
    startPainting()
  }

  private func startPainting() {
    guard painting == nil, !waiting.isEmpty else { return }
    painting = Task { @MainActor [weak self] in
      while let self, !self.waiting.isEmpty {
        let key = self.waiting.removeFirst()
        if key.look == self.look, let image = Self.paintPlate(key) {
          CATransaction.begin()
          CATransaction.setDisableActions(true)
          self.plates[key.plane]?.contents = image
          CATransaction.commit()
          self.plateKeys[key.plane] = key
          self.isReady = ViewPlane.allCases.allSatisfy { self.plateKeys[$0]?.look == key.look }
        }
        await Task.yield()
      }
      self?.painting = nil
    }
  }

  static func paintPlate(_ key: PlateKey) -> CGImage? {
    let plate = ViewStage.plate
    let recipe = recipe(key.look)
    let density = CGFloat(key.pixels) / plate.width
    return render(CGSize(width: plate.width, height: plate.height), scale: density) { context in
      var context = context
      context.translateBy(x: -plate.minX, y: -plate.minY)
      recipe.paint(key.plane, context, look: key.look)
      // The old room's fine grain, a pixel to a grain, so flat shapes read as made, not filled.
      if let grain = ViewGrain.tile {
        var grained = context
        grained.blendMode = .sourceAtop
        grained.fill(
          Path(plate),
          with: .tiledImage(
            Image(decorative: grain, scale: 1), origin: plate.origin, scale: 1 / density))
      }
    }
  }

  // MARK: - What moves

  /// Whether anything in `look` moves: life on a plane, or rain or snow in the air and on the glass.
  static func moves(_ look: ViewLook) -> Bool {
    !recipe(look).livePlanes.isEmpty || look.weather == .rain || look.weather == .snow
  }

  private func paintMoving(_ look: ViewLook) {
    guard let live, let home else { return }
    let now = Date().timeIntervalSince1970
    let moment = ViewMoment(look: look, now: now, time: now - started + 30)
    let recipe = Self.recipe(look)
    let scale = pixelScale
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    for plane in ViewPlane.allCases {
      if recipe.livePlanes.contains(plane) {
        let unit = ViewStage.Frame.blend(home: home, live: live, follow: plane.follow).unit
        lives[plane]?.contents = Self.paintLife(unit: unit * scale) { context in
          recipe.life(plane, context, moment: moment)
        }
      }
      hazes[plane].map { Self.shade($0, after: plane, moment: moment) }
    }
    if look.weather == .rain || look.weather == .snow {
      let unit = ViewStage.Frame.blend(home: home, live: live, follow: 0.7).unit
      air.contents = Self.paintLife(unit: unit * scale, frame: true) { context, frame in
        ViewAir.draw(context, frame: frame, moment: moment)
      }
    } else {
      air.contents = nil
    }
    if !glassPainted || look.weather == .rain || look.weather == .snow {
      glassPainted = true
      let lampOn = lampOn
      glass.contents = Self.paintLife(unit: live.unit * scale, frame: true) { context, frame in
        ViewGlass.draw(context, frame: frame, moment: moment, lampOn: lampOn)
      }
    }
    // Stars twinkle, clouds drift and now and then a plane blinks across, slowly enough to wait.
    if skyAge > Self.skyInterval { paintSky(look, moment: moment) }
  }

  /// Paints the life area at `unit` pixels per stage unit, drawn in stage units.
  private static func paintLife(unit: CGFloat, _ draw: @escaping (GraphicsContext) -> Void)
    -> CGImage?
  {
    paintLife(unit: unit, frame: false) { context, _ in draw(context) }
  }

  /// Paints the life area at `unit` pixels per stage unit. With `frame`, `draw` gets the context in
  /// pixels and the stage's frame in it, for painters that place themselves; otherwise the context
  /// is in stage units.
  private static func paintLife(
    unit: CGFloat, frame: Bool, _ draw: @escaping (GraphicsContext, ViewStage.Frame) -> Void
  ) -> CGImage? {
    let area = lifeArea
    let density = min(unit, CGFloat(maxLifePixels) / area.width)
    let size = CGSize(width: area.width * density, height: area.height * density)
    return render(size, scale: 1) { context in
      if frame {
        draw(
          context,
          ViewStage.Frame(
            unit: density, origin: CGPoint(x: -area.minX * density, y: -area.minY * density)))
      } else {
        var context = context
        context.scaleBy(x: density, y: density)
        context.translateBy(x: -area.minX, y: -area.minY)
        draw(context, ViewStage.Frame(unit: 1, origin: .zero))
      }
    }
  }

  private func paintSky(_ look: ViewLook, moment: ViewMoment? = nil) {
    guard let live, let home, let path = clip.path else { return }
    let now = Date().timeIntervalSince1970
    let moment = moment ?? ViewMoment(look: look, now: now, time: now - started + 30)
    let frame = ViewStage.Frame.blend(home: home, live: live, follow: ViewSky.follow)
    // Painted a margin around the hole, so the room's sway and a drag slide it before it must be
    // painted again.
    let box = path.boundingBox.insetBy(dx: -40, dy: -30).intersection(bounds.insetBy(dx: -40, dy: -30))
    guard box.width > 1, box.height > 1 else { return }
    // The sky is soft: half the screen's pixels are plenty, and stars stay round.
    let scale = min(pixelScale * 0.67, CGFloat(Self.maxLifePixels) / box.width)
    let size = bounds.size
    let moon = Self.recipe(look).moon
    let image = Self.render(box.size, scale: scale) { context in
      var context = context
      context.translateBy(x: -box.minX, y: -box.minY)
      ViewSky.draw(context, size: size, frame: frame, moment: moment, moon: moon)
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    sky.contents = image
    sky.frame = box
    CATransaction.commit()
    skyPainted = (frame, box)
    skyAge = 0
  }

  /// Air between the planes, as the old room laid it: haze always far off, thicker in rain, snow
  /// and fog, slowly thickening and thinning so fog seems to move.
  static func shade(_ layer: CAGradientLayer, after plane: ViewPlane, moment: ViewMoment) {
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
    guard level > 0.01 else {
      layer.isHidden = true
      return
    }
    layer.isHidden = false
    let colour = palette.hazeColour
    layer.colors = [0, 0.55 * level, 0.4 * level].map {
      UIColor(red: colour.red, green: colour.green, blue: colour.blue, alpha: $0).cgColor
    }
    layer.locations = [0, 0.55, 1]
  }

  private static func recipe(_ look: ViewLook) -> any ViewRecipe {
    ViewRecipes.recipe(for: look.view)
  }

  private static func render(
    _ size: CGSize, scale: CGFloat, _ draw: @escaping (GraphicsContext) -> Void
  ) -> CGImage? {
    let renderer = ImageRenderer(
      content: Canvas { context, _ in draw(context) }.frame(width: size.width, height: size.height))
    renderer.scale = scale
    renderer.isOpaque = false
    return renderer.cgImage
  }
}
