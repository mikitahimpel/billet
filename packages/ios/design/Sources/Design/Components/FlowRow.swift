import SwiftUI

/// Chips, tags or small buttons side by side, wrapping onto the next line when the width runs out,
/// so a row of them is never clipped or squeezed into a column of half-words. A piece wider than the
/// whole width gets the whole width.
public struct FlowRow<Content: View>: View {
  let spacing: CGFloat
  let content: Content

  public init(spacing: CGFloat = Space.s, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  public var body: some View {
    FlowLayout(spacing: spacing) { content }
  }
}

struct FlowLayout: Layout {
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let lines = lines(width: proposal.width ?? .infinity, subviews: subviews)
    let width = lines.map(\.width).max() ?? 0
    let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, lines.count - 1))
    return CGSize(width: proposal.width ?? width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for line in lines(width: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for (index, size) in zip(line.indices, line.sizes) {
        subviews[index].place(
          at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
          proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += line.height + spacing
    }
  }

  struct Line {
    var indices: [Int] = []
    var sizes: [CGSize] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  func lines(width: CGFloat, subviews: Subviews) -> [Line] {
    var lines: [Line] = []
    var line = Line()
    for index in subviews.indices {
      var size = subviews[index].sizeThatFits(.unspecified)
      if size.width > width {
        size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
      }
      let needed = line.indices.isEmpty ? size.width : line.width + spacing + size.width
      if needed > width, !line.indices.isEmpty {
        lines.append(line)
        line = Line(indices: [index], sizes: [size], width: size.width, height: size.height)
      } else {
        line.indices.append(index)
        line.sizes.append(size)
        line.width = needed
        line.height = max(line.height, size.height)
      }
    }
    if !line.indices.isEmpty { lines.append(line) }
    return lines
  }
}

#Preview("Flow row") {
  BothSchemes {
    FlowRow {
      ForEach(["Legendary", "−20%", "Owned", "New", "For the window", "Cats"], id: \.self) {
        Chip($0)
      }
    }
    .padding(Space.gutter)
  }
}
