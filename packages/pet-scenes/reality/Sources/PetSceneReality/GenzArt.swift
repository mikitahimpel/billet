import CoreGraphics
import Foundation
import PetScene
import SwiftUI

/// Window Seat's flat layers, drawn natively. Each slot is what an artist's Rive file would
/// replace one for one; the list is in `docs/genz-rooms.md`.
@MainActor
struct GenzNativeArt: RoomLayerArt {
  func view(for slot: RoomLayerSlot, state: RoomLayerState) -> AnyView? {
    switch slot {
    case .windowBloom:
      AnyView(
        GenzBloomLayer(
          state: state, colour: Color(red: 1, green: 0.7, blue: 0.3), width: 10,
          level: 0.8 * GenzOpening.windowLED(state.time) * (state.lampOn ? 1 : 0.3)))
    case .windowBacklight: AnyView(GenzBacklightLayer(state: state))
    case .windowDim:
      AnyView(
        Color(red: 0.012, green: 0.024, blue: 0.047).opacity(GenzOpening.windowDim(state.time)))
    case .windowNight: nil
    }
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

/// The soft glow of an LED strip, along the outline, blended as light.
private struct GenzBloomLayer: View {
  let state: RoomLayerState
  let colour: Color
  let width: CGFloat
  let level: Double

  private static let blur: CGFloat = 5

  var body: some View {
    Canvas { context, _ in
      guard state.outline.count > 1, level > 0 else { return }
      var path = Path()
      path.addLines(state.outline)
      // The blur works over everything the context can draw into, so keep that to the strip
      // and what its glow spreads over.
      let reach = width / 2 + Self.blur * 3
      context.clip(to: Path(path.boundingRect.insetBy(dx: -reach, dy: -reach)))
      context.addFilter(.blur(radius: Self.blur))
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

/// Textures drawn into bitmaps: the note's paper.
enum GenzTextures {
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
