import SwiftUI

/// A line the cat says: one card-coloured bubble with one rim and a small tail toward her. No
/// shadow: `cardSurface()`'s shadow is cut for cards taller than two of its corners, and under a
/// one-line bubble it shows as a second, darker shape.
public struct SpeechBubble<Content: View>: View {
  let tail: SpeechTail
  let content: Content

  public init(tail: SpeechTail = .leading, @ViewBuilder content: () -> Content) {
    self.tail = tail
    self.content = content()
  }

  public var body: some View {
    let shape = SpeechBubbleShape(tail: tail)
    content
      .padding(.horizontal, Space.m)
      .padding(.vertical, Space.s)
      .padding(tail == .leading ? .leading : .top, SpeechBubbleShape.tailLength)
      .background { shape.fill(Ink.cardFill).flipsForRightToLeftLayoutDirection(true) }
      .overlay {
        shape.stroke(
          LinearGradient(
            stops: [
              .init(color: Ink.cardRimTop, location: 0),
              .init(color: Ink.cardRimBottom, location: 0.55),
            ],
            startPoint: .top, endPoint: .bottom),
          lineWidth: 1
        )
        .flipsForRightToLeftLayoutDirection(true)
        .allowsHitTesting(false)
      }
  }
}

/// Where a `SpeechBubble`'s speaker is.
public enum SpeechTail: Equatable, Sendable {
  /// Beside the bubble, on its leading side.
  case leading
  /// Above the bubble; the tail stands this far from its leading edge.
  case top(x: CGFloat)
}

/// The bubble's outline as one path, so the rim runs round the tail with no seam.
struct SpeechBubbleShape: Shape {
  let tail: SpeechTail

  static let tailLength: CGFloat = 7
  /// Half the tail's base.
  static let tailHalf: CGFloat = 6

  func path(in rect: CGRect) -> Path {
    let half = Self.tailHalf
    var body = rect
    switch tail {
    case .leading:
      body.origin.x += Self.tailLength
      body.size.width -= Self.tailLength
    case .top:
      body.origin.y += Self.tailLength
      body.size.height -= Self.tailLength
    }
    // The tail needs a straight run of edge to stand on.
    let corner = max(0, min(Radius.inner + Space.xs, (min(body.height, body.width) - 2 * half) / 2))
    let (minX, maxX, minY, maxY) = (body.minX, body.maxX, body.minY, body.maxY)

    var path = Path()
    path.move(to: CGPoint(x: minX + corner, y: minY))
    if case .top(let x) = tail {
      let tip = min(max(x, minX + corner + half), maxX - corner - half)
      path.addLine(to: CGPoint(x: tip - half, y: minY))
      path.addLine(to: CGPoint(x: tip, y: rect.minY))
      path.addLine(to: CGPoint(x: tip + half, y: minY))
    }
    path.addLine(to: CGPoint(x: maxX - corner, y: minY))
    path.addArc(
      tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + corner),
      radius: corner)
    path.addLine(to: CGPoint(x: maxX, y: maxY - corner))
    path.addArc(
      tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - corner, y: maxY),
      radius: corner)
    path.addLine(to: CGPoint(x: minX + corner, y: maxY))
    path.addArc(
      tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - corner),
      radius: corner)
    if case .leading = tail {
      path.addLine(to: CGPoint(x: minX, y: body.midY + half))
      path.addLine(to: CGPoint(x: rect.minX, y: body.midY))
      path.addLine(to: CGPoint(x: minX, y: body.midY - half))
    }
    path.addLine(to: CGPoint(x: minX, y: minY + corner))
    path.addArc(
      tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + corner, y: minY),
      radius: corner)
    path.closeSubpath()
    return path
  }
}
