import DesignSystem
import Ink
import SwiftUI
import Wire

extension Color {
  /// A stroke colour in `#RRGGBB`, or the ink colour when it cannot be read.
  init(strokeHex hex: String) {
    guard hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else {
      self = Palette.ink.color
      return
    }
    self = Swatch(value).color
  }
}

/// Unit-square strokes drawn into a square, the way a note is stored.
struct StrokesCanvas: View {
  let strokes: [Stroke]

  var body: some View {
    Canvas { context, size in
      for stroke in strokes {
        guard let first = stroke.points.first else { continue }
        var path = Path()
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.width))
        if stroke.points.count == 1 {
          path.addLine(to: CGPoint(x: first.x * size.width, y: first.y * size.width))
        }
        for point in stroke.points.dropFirst() {
          path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.width))
        }
        context.stroke(
          path, with: .color(Color(strokeHex: stroke.color)),
          style: StrokeStyle(
            lineWidth: stroke.width * size.width, lineCap: .round, lineJoin: .round))
      }
    }
  }
}

/// A note on its paper, with the ink appearing stroke by stroke. It plays once when it appears,
/// and again on request. Under Reduce Motion the finished note is shown at once.
public struct ReplayDrawing: View {
  private let normalized: [Stroke]

  @ScaledMetric(relativeTo: .body) private var buttonWidth: CGFloat = 220
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var started = Date.now

  public init(strokes: [Stroke]) {
    normalized = NoteImage.fitted(strokes)
  }

  public var body: some View {
    VStack(spacing: Spacing.small) {
      TimelineView(.animation(paused: reduceMotion)) { context in
        let duration = InkReplay.duration(of: normalized)
        let progress = reduceMotion ? 1 : context.date.timeIntervalSince(started) / duration
        RoundedRectangle(cornerRadius: Radius.paper)
          .fill(Palette.paper.color)
          .overlay { StrokesCanvas(strokes: InkReplay.strokes(of: normalized, progress: progress)) }
          .aspectRatio(1, contentMode: .fit)
          .clipShape(.rect(cornerRadius: Radius.paper))
          .shadow(color: Palette.pageDeep.color.opacity(0.5), radius: 3, x: 1, y: 2)
      }
      if !reduceMotion {
        BilletButton("Watch again", rank: .secondary) { started = .now }
          .frame(maxWidth: buttonWidth)
      }
    }
    .accessibilityElement(children: .contain)
  }
}
