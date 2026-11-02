import CoreGraphics
import Foundation
import PetScene
import SwiftUI

/// The styled rooms' flat layers, drawn natively. Each slot is what an artist's Rive file would
/// replace one for one; the list is in `docs/genz-rooms.md`.
@MainActor
struct GenzNativeArt: RoomLayerArt {
  func view(for slot: RoomLayerSlot, state: RoomLayerState) -> AnyView? {
    switch slot {
    case .sunsetCity: AnyView(GenzCityLayer(state: state))
    case .sunsetBloom:
      AnyView(
        GenzBloomLayer(
          state: state, colour: Color(red: 1, green: 0.35, blue: 0.28), width: 12,
          level: GenzOpening.sunsetLED(state.time) * GenzArtMotion.shimmer(state.time)))
    case .sunsetDim:
      AnyView(
        Color(red: 0.027, green: 0.024, blue: 0.043)
          .opacity(GenzOpening.sunsetDim(state.time) + (state.lampOn ? 0 : 0.35)))
    case .windowBloom:
      AnyView(
        GenzBloomLayer(
          state: state, colour: Color(red: 1, green: 0.7, blue: 0.3), width: 10,
          level: 0.8 * GenzOpening.windowLED(state.time) * (state.lampOn ? 1 : 0.3)))
    case .windowBacklight: AnyView(GenzBacklightLayer(state: state))
    case .windowDim:
      AnyView(
        Color(red: 0.012, green: 0.024, blue: 0.047).opacity(GenzOpening.windowDim(state.time)))
    case .sunsetDisc, .sunsetPoster, .windowNight: nil
    }
  }

  func image(for slot: RoomLayerSlot, state: RoomLayerState, pixels: Int) -> CGImage? {
    switch slot {
    case .sunsetDisc: GenzTextures.disc(state: state, pixels: pixels)
    case .sunsetPoster: GenzTextures.poster(state: state, pixels: pixels)
    case .sunsetCity, .sunsetBloom, .sunsetDim, .windowNight, .windowBloom, .windowBacklight,
      .windowDim:
      nil
    }
  }
}

enum GenzArtMotion {
  /// The LED's slow shimmer, between 0.7 and 1.
  static func shimmer(_ time: Double) -> Double {
    0.85 + 0.15 * cos(time * .pi / 5)
  }

  /// Whether a lit city window is on: one in three blinks off for part of a nine-second cycle.
  static func cityWindowOn(_ index: Int, time: Double) -> Bool {
    guard index % 3 == 0 else { return true }
    let phase = (time + Double(index) * 0.7).truncatingRemainder(dividingBy: 9) / 9
    return phase < 0.41 || phase > 0.7
  }

}

/// Bounds of an outline, or `nil` when it is empty.
private func bounds(of outline: [CGPoint]) -> CGRect? {
  guard let first = outline.first else { return nil }
  return outline.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
    $0.union(CGRect(origin: $1, size: .zero))
  }
}

extension Color {
  fileprivate init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255, opacity: opacity)
  }
}

/// The night city behind Sunset Lamp's window, on the room's plum-ink ground. It slides with the
/// camera at 0.3 of the room's movement.
private struct GenzCityLayer: View {
  let state: RoomLayerState

  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x14121A)))
      guard let window = bounds(of: state.outline) else { return }
      let frame = window.insetBy(dx: -window.width * 0.4, dy: -window.height * 0.3)
        .offsetBy(dx: state.parallax.width * 0.3, dy: state.parallax.height * 0.3)
      context.fill(
        Path(frame),
        with: .linearGradient(
          Gradient(colors: [Color(hex: 0x0C1022), Color(hex: 0x28203A)]),
          startPoint: CGPoint(x: frame.midX, y: frame.minY),
          endPoint: CGPoint(x: frame.midX, y: frame.maxY)))
      let unit = frame.width / 140
      for (x, y, r) in [(96.0, 56.0, 1.2), (58, 48, 1), (80, 76, 0.9)] {
        let star = CGRect(
          x: frame.minX + x * unit - r * unit, y: frame.minY + y * unit - r * unit,
          width: 2 * r * unit, height: 2 * r * unit)
        context.fill(Path(ellipseIn: star), with: .color(Color(hex: 0xFFF1E2, opacity: 0.75)))
      }
      var index = 0
      let towers: [(Double, Double, Double)] = [
        (20, 130, 26), (44, 108, 18), (60, 142, 30), (86, 118, 16), (100, 150, 40),
      ]
      for (x, top, width) in towers {
        let tower = CGRect(
          x: frame.minX + x * unit, y: frame.minY + top * unit, width: width * unit,
          height: frame.maxY - frame.minY - top * unit)
        context.fill(Path(tower), with: .color(Color(hex: 0x0A0C18)))
        var row = top + 8
        while row < 230 {
          var column = x + 4
          while column < x + width - 4 {
            if Int(column * 7 + row * 3) % 5 < 2 {
              index += 1
              if GenzArtMotion.cityWindowOn(index, time: state.time) {
                let light = CGRect(
                  x: frame.minX + column * unit, y: frame.minY + row * unit, width: 3 * unit,
                  height: 4 * unit)
                context.fill(Path(light), with: .color(Color(hex: 0xFFC27A, opacity: 0.85)))
              }
            }
            column += 7
          }
          row += 12
        }
      }
    }
    .allowsHitTesting(false)
  }
}

/// The soft glow of an LED strip, along the outline, blended as light.
private struct GenzBloomLayer: View {
  let state: RoomLayerState
  let colour: Color
  let width: CGFloat
  let level: Double

  var body: some View {
    Canvas { context, _ in
      guard state.outline.count > 1, level > 0 else { return }
      var path = Path()
      path.addLines(state.outline)
      context.addFilter(.blur(radius: 5))
      context.stroke(
        path, with: .color(colour.opacity(level)),
        style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
    .blendMode(.screen)
    .allowsHitTesting(false)
  }
}

/// The street light through the note's paper: a warm glow over the note, blended as light.
private struct GenzBacklightLayer: View {
  let state: RoomLayerState

  var body: some View {
    Canvas { context, _ in
      guard let note = bounds(of: state.outline) else { return }
      let level = GenzOpening.backlight(state.time) * GenzOpening.streetLamp(state.time)
      guard level > 0 else { return }
      let glow = note.insetBy(dx: -note.width * 0.3, dy: -note.height * 0.25)
      context.fill(
        Path(ellipseIn: glow),
        with: .radialGradient(
          Gradient(stops: [
            .init(color: Color(hex: 0xFFE2B0, opacity: 0.32 * level), location: 0),
            .init(color: Color(hex: 0xFFC36B, opacity: 0.12 * level), location: 0.6),
            .init(color: .clear, location: 1),
          ]), center: CGPoint(x: glow.midX, y: glow.midY), startRadius: 0,
          endRadius: max(glow.width, glow.height) / 2))
    }
    .blendMode(.screen)
    .allowsHitTesting(false)
  }
}

/// Textures drawn into bitmaps: the sunset disc, the poster and the note's paper.
enum GenzTextures {
  /// The lamp's disc on Sunset Lamp's back wall, 8 by 5.4 units, transparent around it.
  static func disc(state: RoomLayerState, pixels: Int) -> CGImage? {
    let wall = CGSize(width: 8, height: 5.4)
    return draw(width: pixels, aspect: wall.height / wall.width) { context, size in
      let unit = size.width / wall.width
      let bloom = GenzOpening.discBloom(state.time)
      guard bloom > 0, state.lampOn else { return }
      let centre = CGPoint(x: 3.1 * unit, y: size.height - 2.35 * unit)
      let scale = 0.35 + 0.65 * bloom
      let warm = state.warmth
      halo(context, centre: centre, radius: 4.6 * unit * scale, alpha: 0.3 * bloom)
      let stops: [(UInt32, CGFloat, CGFloat)] = [
        (warm > 0 ? 0xFFD9A0 : 0xFFC27A, 0, 1), (0xFF8A3D, 0.4, 1), (0xE5503A, 0.76, 1),
        (0xB9384A, 0.9, 0.5), (0xB9384A, 1, 0),
      ]
      radial(
        context, centre: centre, radius: 3.15 * unit * scale,
        stops: stops.map { ($0.0, $0.1, $0.2 * bloom * (0.9 + 0.1 * warm)) })
    }
  }

  /// The poster: a sun on deep green with a bar that turns once every 24 seconds.
  static func poster(state: RoomLayerState, pixels: Int) -> CGImage? {
    draw(width: pixels, aspect: 1.9) { context, size in
      let unit = size.width
      context.setFillColor(GenzColour(0x2F4A42).cgColor)
      context.fill(CGRect(origin: .zero, size: size))
      let centre = CGPoint(x: 0.52 * unit, y: size.height - 0.7 * unit)
      context.setFillColor(GenzColour(0xE9DCC8).cgColor)
      context.fillEllipse(
        in: CGRect(
          x: centre.x - 0.34 * unit, y: centre.y - 0.34 * unit, width: 0.68 * unit,
          height: 0.68 * unit))
      context.saveGState()
      context.translateBy(x: centre.x, y: centre.y)
      context.rotate(by: CGFloat(state.time / 24 * 2 * .pi))
      context.setFillColor(GenzColour(0x2F4A42).cgColor)
      context.fill(
        CGRect(x: -0.36 * unit, y: -0.04 * unit, width: 0.72 * unit, height: 0.08 * unit))
      context.restoreGState()
      context.setFillColor(GenzColour(0xE9DCC8).cgColor)
      context.fill(
        CGRect(x: 0.14 * unit, y: size.height - 1.37 * unit, width: 0.6 * unit, height: 0.09 * unit)
      )
      context.setAlpha(0.6)
      context.fill(
        CGRect(x: 0.14 * unit, y: size.height - 1.5 * unit, width: 0.42 * unit, height: 0.06 * unit)
      )
    }
  }

  /// The note's paper with the drawing on it and two strips of tape, or a small heart when there
  /// is no drawing yet. `corners` puts the tape across the top corners instead of the middle.
  static func note(
    drawing: CGImage?, paper: GenzColour, aspect: CGFloat, corners: Bool, pixels: Int = 512
  ) -> CGImage? {
    draw(width: pixels, aspect: aspect) { context, size in
      context.setFillColor(paper.cgColor)
      context.fill(CGRect(origin: .zero, size: size))
      let margin = size.width * 0.08
      let area = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)
      if let drawing {
        let side = min(area.width, area.height)
        context.interpolationQuality = .high
        context.draw(
          drawing,
          in: CGRect(x: area.midX - side / 2, y: area.midY - side / 2, width: side, height: side))
      } else {
        heart(
          context, centre: CGPoint(x: size.width / 2, y: size.height / 2), size: size.width * 0.18)
      }
      context.setFillColor(GenzColour(0xF0E2C8).cgColor)
      context.setAlpha(0.85)
      let tape = CGSize(width: size.width * (corners ? 0.2 : 0.3), height: size.width * 0.08)
      let spots: [(CGPoint, CGFloat)] =
        corners
        ? [
          (CGPoint(x: size.width * 0.06, y: size.height - size.width * 0.01), 0.52),
          (CGPoint(x: size.width * 0.94, y: size.height - size.width * 0.01), -0.52),
        ]
        : [(CGPoint(x: size.width / 2, y: size.height - size.width * 0.01), 0.05)]
      for (centre, turn) in spots {
        context.saveGState()
        context.translateBy(x: centre.x, y: centre.y)
        context.rotate(by: turn)
        context.fill(
          CGRect(x: -tape.width / 2, y: -tape.height / 2, width: tape.width, height: tape.height))
        context.restoreGState()
      }
    }
  }

  private static func heart(_ context: CGContext, centre: CGPoint, size: CGFloat) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: centre.x, y: centre.y - size * 0.55))
    path.addCurve(
      to: CGPoint(x: centre.x, y: centre.y + size * 0.3),
      control1: CGPoint(x: centre.x - size * 1.1, y: centre.y + size * 0.1),
      control2: CGPoint(x: centre.x - size * 0.5, y: centre.y + size * 0.9))
    path.addCurve(
      to: CGPoint(x: centre.x, y: centre.y - size * 0.55),
      control1: CGPoint(x: centre.x + size * 0.5, y: centre.y + size * 0.9),
      control2: CGPoint(x: centre.x + size * 1.1, y: centre.y + size * 0.1))
    context.addPath(path)
    context.setFillColor(GenzColour(0xE5503A).cgColor)
    context.fillPath()
  }

  private static func halo(_ context: CGContext, centre: CGPoint, radius: CGFloat, alpha: CGFloat) {
    radial(
      context, centre: centre, radius: radius, stops: [(0xFF6A3D, 0, alpha), (0xFF6A3D, 1, 0)])
  }

  private static func radial(
    _ context: CGContext, centre: CGPoint, radius: CGFloat, stops: [(UInt32, CGFloat, CGFloat)]
  ) {
    let colours = stops.map { stop -> CGColor in
      let colour = GenzColour(stop.0)
      return CGColor(
        srgbRed: CGFloat(colour.red), green: CGFloat(colour.green), blue: CGFloat(colour.blue),
        alpha: stop.2)
    }
    guard
      let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colours as CFArray,
        locations: stops.map(\.1))
    else { return }
    context.drawRadialGradient(
      gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius,
      options: [])
  }

  private static func draw(
    width: Int, aspect: CGFloat, _ body: (CGContext, CGSize) -> Void
  ) -> CGImage? {
    let height = max(1, Int((CGFloat(width) * aspect).rounded()))
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    body(context, CGSize(width: width, height: height))
    return context.makeImage()
  }
}
