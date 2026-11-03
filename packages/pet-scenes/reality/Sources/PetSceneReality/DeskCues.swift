import CoreGraphics
import CoreText
import Observation
import SwiftUI

/// What the desk draws over its scene: where the paper is in the view, so a pencilled "draw here"
/// can lie on it, and whether the board is still empty.
@MainActor
@Observable
final class DeskScreen {
  /// The paper's corners in the view's points: far left, far right, near right, near left.
  var paper: [CGPoint] = []
  var isEmpty = false
}

/// A pencilled "draw here" written on the paper, with a looping underline that ends in an arrow
/// to the middle of the page. It writes itself out once, then stays.
struct DeskDoodleLayer: View {
  let screen: DeskScreen

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var written: CGFloat = 0

  /// The page the doodle is laid out on, in points, the paper's own proportions.
  static let page = CGSize(width: 240, height: 170)
  private static let pencil = Color(red: 0.36, green: 0.24, blue: 0.2)

  var body: some View {
    ZStack(alignment: .topLeading) {
      if let transform = Self.projection(onto: screen.paper) {
        doodle
          .frame(width: Self.page.width, height: Self.page.height)
          .projectionEffect(transform)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .task {
      if reduceMotion {
        written = 1
        return
      }
      try? await Task.sleep(for: .seconds(0.7))
      withAnimation(.easeInOut(duration: 1.8)) { written = 1 }
    }
  }

  private var doodle: some View {
    ZStack(alignment: .top) {
      Text(screen.isEmpty ? "draw your first note" : "draw here")
        .font(.custom("Noteworthy-Bold", size: screen.isEmpty ? 25 : 34))
        .foregroundStyle(Self.pencil.opacity(0.85))
        .rotationEffect(.degrees(-4))
        .padding(.top, 14)
        .mask(alignment: .leading) {
          Rectangle().frame(width: Self.page.width * min(written / 0.6, 1))
        }
      Underline()
        .trim(from: 0, to: max((written - 0.55) / 0.45, 0))
        .stroke(
          Self.pencil.opacity(0.75),
          style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
    }
    .frame(width: Self.page.width, height: Self.page.height, alignment: .top)
  }

  /// A loop under the words that swings down into an arrow at the middle of the page.
  private struct Underline: Shape {
    func path(in rect: CGRect) -> Path {
      let w = rect.width
      let h = rect.height
      var path = Path()
      path.move(to: CGPoint(x: w * 0.2, y: h * 0.42))
      path.addCurve(
        to: CGPoint(x: w * 0.78, y: h * 0.38), control1: CGPoint(x: w * 0.4, y: h * 0.48),
        control2: CGPoint(x: w * 0.62, y: h * 0.44))
      path.addCurve(
        to: CGPoint(x: w * 0.6, y: h * 0.62), control1: CGPoint(x: w * 0.92, y: h * 0.34),
        control2: CGPoint(x: w * 0.8, y: h * 0.62))
      path.addLine(to: CGPoint(x: w * 0.54, y: h * 0.63))
      path.move(to: CGPoint(x: w * 0.6, y: h * 0.56))
      path.addLine(to: CGPoint(x: w * 0.53, y: h * 0.63))
      path.addLine(to: CGPoint(x: w * 0.61, y: h * 0.69))
      return path
    }
  }

  /// The perspective that lays the page on the paper's four corners in the view: far left, far
  /// right, near right, near left. `nil` until the paper has been seen.
  static func projection(onto corners: [CGPoint]) -> ProjectionTransform? {
    guard corners.count == 4 else { return nil }
    let (x0, y0) = (corners[0].x, corners[0].y)
    let (x1, y1) = (corners[1].x, corners[1].y)
    let (x2, y2) = (corners[2].x, corners[2].y)
    let (x3, y3) = (corners[3].x, corners[3].y)
    let dx1 = x1 - x2
    let dx2 = x3 - x2
    let dx3 = x0 - x1 + x2 - x3
    let dy1 = y1 - y2
    let dy2 = y3 - y2
    let dy3 = y0 - y1 + y2 - y3
    let denominator = dx1 * dy2 - dx2 * dy1
    guard abs(denominator) > 1e-6 else { return nil }
    let g = (dx3 * dy2 - dx2 * dy3) / denominator
    let h = (dx1 * dy3 - dx3 * dy1) / denominator
    // The unit square to the corners, after the page is scaled down to the unit square.
    var transform = ProjectionTransform()
    transform.m11 = (x1 - x0 + g * x1) / page.width
    transform.m12 = (y1 - y0 + g * y1) / page.width
    transform.m13 = g / page.width
    transform.m21 = (x3 - x0 + h * x3) / page.height
    transform.m22 = (y3 - y0 + h * y3) / page.height
    transform.m23 = h / page.height
    transform.m31 = x0
    transform.m32 = y0
    transform.m33 = 1
    return transform
  }
}

/// The pictures the desk draws for itself.
@MainActor
enum DeskArt {
  /// A blank card for the empty board, with a dashed edge and "your first note goes here".
  static func placeholder(pixels: Int = 256) -> CGImage? {
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let side = CGFloat(pixels)
    context.setFillColor(GenzColour(0xFBF1E2).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let ink = GenzColour(0x8A6A58).cgColor
    context.setStrokeColor(ink)
    context.setLineWidth(side * 0.016)
    context.setLineCap(.round)
    context.setLineDash(phase: 0, lengths: [side * 0.05, side * 0.04])
    context.stroke(
      CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: side * 0.08, dy: side * 0.08))
    context.setLineDash(phase: 0, lengths: [])
    // A pencilled plus over the words.
    context.setLineWidth(side * 0.02)
    let middle = CGPoint(x: side / 2, y: side * 0.6)
    context.move(to: CGPoint(x: middle.x - side * 0.08, y: middle.y))
    context.addLine(to: CGPoint(x: middle.x + side * 0.08, y: middle.y))
    context.move(to: CGPoint(x: middle.x, y: middle.y - side * 0.08))
    context.addLine(to: CGPoint(x: middle.x, y: middle.y + side * 0.08))
    context.strokePath()
    for (index, line) in ["your first note", "goes here"].enumerated() {
      draw(
        line, in: context, size: side * 0.085, colour: ink, centreX: side / 2,
        baseline: side * (0.36 - 0.11 * CGFloat(index)))
    }
    return context.makeImage()
  }

  private static func draw(
    _ text: String, in context: CGContext, size: CGFloat, colour: CGColor, centreX: CGFloat,
    baseline: CGFloat
  ) {
    let font = CTFontCreateWithName("Noteworthy-Bold" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
    ]
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: attributes))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    context.textPosition = CGPoint(x: centreX - CGFloat(width) / 2, y: baseline)
    CTLineDraw(line, context)
  }
}
