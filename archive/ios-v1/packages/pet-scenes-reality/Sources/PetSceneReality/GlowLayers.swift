import Pet
import SwiftUI
import simd

/// The haze the room sits in: brightest right around it and falling off to the preset's edge
/// colour, over the night behind it. A full cover replaces that night, except through the window,
/// whose view still shows.
struct GlowHaze: View {
  let look: LightingLook
  /// The window's corners in the view, left clear of haze.
  var window: [CGPoint] = []

  var body: some View {
    if look.haze.cover > 0 {
      let cover = Double(look.haze.cover)
      ZStack {
        EllipticalGradient(
          stops: [
            .init(color: look.haze.centre.colour.opacity(cover), location: 0),
            .init(
              color: LightingLook.RGB.mix(look.haze.centre, look.haze.edge, by: 0.6).colour
                .opacity(cover), location: 0.45),
            .init(color: look.haze.edge.colour.opacity(cover), location: 1),
          ], center: UnitPoint(x: 0.5, y: 0.46), startRadiusFraction: 0, endRadiusFraction: 0.7)
        EllipticalGradient(
          stops: [
            .init(color: look.haze.centre.colour.opacity(0.5 * cover), location: 0),
            .init(color: .clear, location: 1),
          ], center: UnitPoint(x: 0.5, y: 0.46), startRadiusFraction: 0, endRadiusFraction: 0.45
        )
        .blendMode(.screen)
      }
      .mask {
        Canvas { canvas, size in
          var path = Path(CGRect(origin: .zero, size: size))
          if window.count > 2 { path.addLines(window + [window[0]]) }
          canvas.fill(path, with: .color(.black), style: FillStyle(eoFill: true))
        }
      }
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}

/// The colour grade over the whole view: a tint multiplied in, and a lift added under the darks
/// so nothing is black and the shadows lose contrast. Brighter areas get a soft film of the lift
/// too, like light scattering in the lens.
struct GlowGrade: View {
  let look: LightingLook

  var body: some View {
    let grade = look.grade
    if grade.tintAmount > 0 || grade.liftAmount > 0 {
      ZStack {
        LightingLook.RGB.mix(.one, grade.tint, by: grade.tintAmount).colour
          .blendMode(.multiply)
        grade.lift.colour.opacity(Double(grade.liftAmount))
          .blendMode(.screen)
      }
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}

/// The edges of the view darkened to the preset's colour, so the eye rests on the lit room.
struct GlowVignette: View {
  let look: LightingLook

  var body: some View {
    if look.vignette.amount > 0 {
      EllipticalGradient(
        stops: [
          .init(color: .clear, location: 0.4),
          .init(
            color: look.vignette.colour.colour.opacity(Double(min(look.vignette.amount, 0.95))),
            location: 1),
        ], center: UnitPoint(x: 0.5, y: 0.46), startRadiusFraction: 0, endRadiusFraction: 0.78
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
}

/// Where a styled room's lights are in the view, in points.
struct GlowSpots: Equatable {
  /// Each fairy light.
  var bulbs: [CGPoint] = []
  /// Points along the LED strip.
  var led: [CGPoint] = []
  /// The lamp's bulb.
  var lamp: CGPoint?
  /// Where the light pools on the floor.
  var pool: CGPoint?
  /// How many points one unit of the room spans near its middle, to size the glows by.
  var pointsPerUnit: CGFloat = 40

  /// Points along the path through `corners`, about `spacing` apart in the room.
  static func along(_ corners: [GenzRoomPoint], every spacing: Float) -> [GenzRoomPoint] {
    var points: [GenzRoomPoint] = []
    for (start, end) in zip(corners, corners.dropFirst()) {
      let length = simd_distance(start.scene, end.scene)
      let count = max(Int((length / spacing).rounded()), 1)
      for step in 0..<count {
        let along = Float(step) / Float(count)
        points.append(
          GenzRoomPoint(
            start.x + (end.x - start.x) * along, start.y + (end.y - start.y) * along,
            start.z + (end.z - start.z) * along))
      }
    }
    if let last = corners.last { points.append(last) }
    return points
  }
}

/// Soft halos over a styled room's lights, added onto what is under them, in the preset's colours:
/// the fairy lights twinkle a little, the LED glows along its length and the lamp throws a wide
/// pool. Drawn in the view rather than the renderer, since RealityKit's own post-processing is not
/// available on every device the app runs on.
struct GlowLights: View {
  let look: LightingLook
  let screen: GenzRoomScreen
  let isPaused: Bool

  /// The cream at the middle of a halo, so its brightest point is never hard white.
  static let cream = Color(red: 1, green: 0.88, blue: 0.68)

  var body: some View {
    if look.halos > 0 {
      TimelineView(
        RoomLayerSchedule(
          busyUntil: screen.busyUntil, steady: steadyInterval, isPaused: isPaused)
      ) { context in
        let state = screen.state(for: .windowBloom, at: context.date, followsCamera: false)
        let lights = screen.lights
        let amount = Double(look.halos)
        let lit = Self.level(time: state.time)
        let flicker = Self.flicker(look.key.flicker, time: isPaused ? 0 : state.time)
        let lamp = state.lampOn ? Self.lampLevel(time: state.time) * flicker : 0
        let bulb = look.fairy.colour.colour
        let led = (look.led ?? look.fairy.colour).colour
        let key = look.key.colour.colour
        let cat = screen.cat
        Canvas { canvas, _ in
          let unit = lights.pointsPerUnit
          if let pool = lights.pool {
            Self.halo(
              in: &canvas, at: pool, radius: unit * 2.6, colour: key, opacity: 0.32 * amount)
          }
          if let cat {
            // The warm bed of light the cat lies in.
            let bed = CGPoint(x: cat.x, y: cat.y + unit * 0.5)
            Self.halo(in: &canvas, at: bed, radius: unit * 1.8, colour: key, opacity: 0.3 * amount)
          }
          for (index, point) in lights.bulbs.enumerated() {
            let twinkle = 0.82 + 0.18 * sin(state.time * 1.7 + Double(index) * 2.3)
            Self.halo(
              in: &canvas, at: point, radius: unit * 0.55, colour: bulb,
              opacity: 0.55 * amount * lit * twinkle)
          }
          for point in lights.led {
            Self.halo(
              in: &canvas, at: point, radius: unit * 0.7, colour: led, opacity: 0.22 * amount * lit)
          }
          if let point = lights.lamp, lamp > 0 {
            Self.halo(
              in: &canvas, at: point, radius: unit * 3.4, colour: key,
              opacity: 0.38 * amount * lamp)
            Self.halo(
              in: &canvas, at: point, radius: unit * 0.9, colour: Self.cream,
              opacity: 0.55 * amount * lamp)
          }
        }
      }
      .blendMode(.screen)
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }

  /// How often the halos change once the room has opened: a flame flickers fast, fairy lights
  /// twinkle slowly, and otherwise they hold still.
  private var steadyInterval: TimeInterval? {
    if look.key.flicker > 0 { return 1 / 30 }
    // From the look alone: reading the lights here would redraw this view on every camera move.
    if look.fairy.shown { return 1 / 15 }
    return nil
  }

  /// How bright a flickering flame is at `time`, from 1 down by up to `amount`.
  static func flicker(_ amount: Float, time: Double) -> Double {
    guard amount > 0 else { return 1 }
    let wave = sin(time * 9.1) * 0.5 + sin(time * 23.7 + 1.3) * 0.3 + sin(time * 3.3) * 0.2
    return 1 - Double(amount) * (0.5 + 0.5 * wave)
  }

  /// How far the room's small lights have come on in its opening.
  static func level(time: Double) -> Double {
    GenzOpening.windowLED(time)
  }

  /// How far the lamp has come on in the room's opening.
  static func lampLevel(time: Double) -> Double {
    GenzOpening.eased(time, from: 1.4, length: 0.8)
  }

  private static func halo(
    in canvas: inout GraphicsContext, at point: CGPoint, radius: CGFloat, colour: Color,
    opacity: Double
  ) {
    guard opacity > 0.005, radius > 0 else { return }
    let rect = CGRect(
      x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    canvas.fill(
      Path(ellipseIn: rect),
      with: .radialGradient(
        Gradient(stops: [
          .init(color: colour.opacity(min(opacity, 1)), location: 0),
          .init(color: colour.opacity(min(opacity, 1) * 0.35), location: 0.35),
          .init(color: colour.opacity(0), location: 1),
        ]), center: point, startRadius: 0, endRadius: radius))
  }
}
