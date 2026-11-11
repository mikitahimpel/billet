import SwiftUI

/// One of a screen's few big actions: an icon, one label and a short status, such as "5 wishes".
public struct ActionTile: Identifiable {
  public let title: String
  public let status: String
  public let symbol: String
  public let tint: Color
  public let action: () -> Void

  public var id: String { title }

  public init(
    _ title: String, status: String, symbol: String, tint: Color, action: @escaping () -> Void
  ) {
    self.title = title
    self.status = status
    self.symbol = symbol
    self.tint = tint
    self.action = action
  }
}

/// Equal square tiles side by side while every label fits on one line; otherwise, as at large and
/// accessibility text sizes, the same actions as rows of one grouped section.
public struct ActionTiles: View {
  let tiles: [ActionTile]

  public init(_ tiles: [ActionTile]) { self.tiles = tiles }

  public var body: some View {
    ViewThatFits(in: .horizontal) {
      SquareRow(spacing: Space.m) {
        ForEach(tiles) { tile in
          Button(action: tile.action) { square(tile) }
            .buttonStyle(PressScaleStyle())
        }
      }
      GroupedSection {
        ForEach(tiles) { tile in
          Button(action: tile.action) {
            Row(tile.title, detail: tile.status, symbol: tile.symbol, tint: tile.tint) {
              RowChevron()
            }
          }
          .buttonStyle(RowButtonStyle())
        }
      }
    }
  }

  private func square(_ tile: ActionTile) -> some View {
    VStack(alignment: .leading, spacing: Space.xxs) {
      RowIcon(symbol: tile.symbol, tint: tile.tint, size: Size.tileMark, style: .clay)
      Spacer(minLength: Space.s)
      Text(tile.title)
        .font(.ourioHeadline)
        .foregroundStyle(Ink.text)
      Text(tile.status)
        .font(.ourioCaption.monospacedDigit())
        .foregroundStyle(Ink.textSecondary)
    }
    .lineLimit(1)
    .padding(Space.m)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .cardSurface()
    .contentShape(.rect(cornerRadius: Radius.card))
    .accessibilityElement(children: .combine)
  }
}

/// Columns of equal width and a row as tall as it is wide, or taller when a tile needs it. Its ideal
/// width is the sum of the tiles' one-line widths, so `ViewThatFits` drops it once a label would
/// not fit.
struct SquareRow: Layout {
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let gaps = spacing * CGFloat(max(0, subviews.count - 1))
    guard let width = proposal.width, width.isFinite else {
      let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
      return CGSize(
        width: ideal.map(\.width).reduce(0, +) + gaps, height: ideal.map(\.height).max() ?? 0)
    }
    return CGSize(width: width, height: height(width: width, subviews: subviews))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let column = column(bounds.width, count: subviews.count)
    let height = height(width: bounds.width, subviews: subviews)
    for (index, subview) in subviews.enumerated() {
      subview.place(
        at: CGPoint(x: bounds.minX + CGFloat(index) * (column + spacing), y: bounds.minY),
        proposal: ProposedViewSize(width: column, height: height))
    }
  }

  private func column(_ width: CGFloat, count: Int) -> CGFloat {
    guard count > 0 else { return 0 }
    return max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
  }

  private func height(width: CGFloat, subviews: Subviews) -> CGFloat {
    let column = column(width, count: subviews.count)
    let tallest =
      subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }
      .max() ?? 0
    return max(column, tallest)
  }
}

#Preview("Action tiles") {
  BothSchemes {
    ActionTiles([
      ActionTile("Dates", status: "2 matches", symbol: "dice.fill", tint: .blushPink) {},
      ActionTile("Wishlists", status: "5 wishes", symbol: "gift.fill", tint: .orange) {},
      ActionTile("Calendar", status: "In 3 days", symbol: "calendar", tint: .teal) {},
    ])
    .padding(Space.gutter)
  }
}
