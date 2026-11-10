import SwiftUI

/// A tile in an `ItemGrid`: art a little wider than tall, badges over its top corners, a one-line
/// title and subtitle, and a footer (a price, a buy or an owned state) at the bottom. In a grid
/// every tile of a row has the row's height, so the footers line up. With `open`, the art and the
/// title are one button and the footer stays its own. The art draws its own `Radius.inner` corners
/// (it is their container shape), so a glow around it is not cut off.
public struct ItemCard<Art: View, Leading: View, Trailing: View, Footer: View>: View {
  let title: String
  let subtitle: String?
  let open: (hint: String, action: () -> Void)?
  let art: Art
  let leading: Leading
  let trailing: Trailing
  let footer: Footer

  /// - Parameter opens: Read by VoiceOver for `open`, as in "Opens Cat tower".
  public init(
    _ title: String, subtitle: String? = nil, opens: String? = nil, open: (() -> Void)? = nil,
    @ViewBuilder art: () -> Art, @ViewBuilder leadingBadge: () -> Leading,
    @ViewBuilder trailingBadge: () -> Trailing, @ViewBuilder footer: () -> Footer
  ) {
    self.title = title
    self.subtitle = subtitle
    self.open = open.map { (opens ?? "Opens \(title)", $0) }
    self.art = art()
    self.leading = leadingBadge()
    self.trailing = trailingBadge()
    self.footer = footer()
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Space.s) {
      if let open {
        Button(action: open.action) { face.contentShape(.rect) }
          .buttonStyle(PressScaleStyle())
          .accessibilityElement(children: .combine)
          .accessibilityHint(open.hint)
      } else {
        face
      }
      Spacer(minLength: 0)
      footer
    }
    .padding(CardMetrics.padding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .cardSurface()
  }

  private var face: some View {
    VStack(alignment: .leading, spacing: Space.s) {
      art
        .frame(maxWidth: .infinity)
        .aspectRatio(ItemCardMetrics.artAspect, contentMode: .fit)
        .containerShape(.rect(cornerRadius: Radius.inner, style: .continuous))
        .overlay(alignment: .top) { badges }
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.ourioHeadline)
          .foregroundStyle(Ink.text)
        if let subtitle {
          Text(subtitle)
            .font(.ourioCaption)
            .foregroundStyle(Ink.textSecondary)
        }
      }
      .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Side by side while both fit inside the art, otherwise stacked at the leading corner, so a
  /// badge is never clipped or drawn over the other.
  private var badges: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: Space.xs) {
        leading
        Spacer(minLength: 0)
        trailing
      }
      VStack(alignment: .leading, spacing: Space.xs) {
        leading
        trailing
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(Space.s)
  }
}

extension ItemCard where Leading == EmptyView, Trailing == EmptyView {
  public init(
    _ title: String, subtitle: String? = nil, opens: String? = nil, open: (() -> Void)? = nil,
    @ViewBuilder art: () -> Art, @ViewBuilder footer: () -> Footer
  ) {
    self.init(
      title, subtitle: subtitle, opens: opens, open: open, art: art,
      leadingBadge: { EmptyView() }, trailingBadge: { EmptyView() }, footer: footer)
  }
}

enum ItemCardMetrics {
  static let artAspect: CGFloat = 1.05
}

/// Tiles in equal columns `Space.m` apart, each row as tall as its tallest tile. One column at
/// accessibility text sizes. Not lazy: for a shelf of tens of items, not a feed.
public struct ItemGrid<Content: View>: View {
  let columns: Int
  let content: Content
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(columns: Int = 2, @ViewBuilder content: () -> Content) {
    self.columns = columns
    self.content = content()
  }

  public var body: some View {
    EqualGridLayout(
      columns: dynamicTypeSize.isAccessibilitySize ? 1 : max(1, columns), spacing: Space.m
    ) {
      content
    }
  }
}

struct EqualGridLayout: Layout {
  let columns: Int
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 320
    let heights = rowHeights(width: width, subviews: subviews)
    let height = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let column = columnWidth(bounds.width)
    let heights = rowHeights(width: bounds.width, subviews: subviews)
    var y = bounds.minY
    for (row, height) in heights.enumerated() {
      for index in row * columns..<min(subviews.count, (row + 1) * columns) {
        let x = bounds.minX + CGFloat(index % columns) * (column + spacing)
        subviews[index].place(
          at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: column, height: height))
      }
      y += height + spacing
    }
  }

  func columnWidth(_ width: CGFloat) -> CGFloat {
    max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
  }

  func rowHeights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
    let column = columnWidth(width)
    return stride(from: 0, to: subviews.count, by: columns).map { start in
      subviews[start..<min(subviews.count, start + columns)]
        .map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }
        .max() ?? 0
    }
  }
}

#Preview("Item grid") {
  BothSchemes {
    ScrollView {
      ItemGrid {
        ForEach(["Cat tower", "Window seat, long name", "Lamp", "Rug", "Plant"], id: \.self) {
          name in
          ItemCard(name, subtitle: "Cosy in any corner", open: {}) {
            Ink.surfaceRaised
          } leadingBadge: {
            Chip("Legendary", style: .tinted(.orange))
          } trailingBadge: {
            Chip("−20%", style: .honey)
          } footer: {
            PriceButton(120, was: 150) {}
          }
        }
      }
      .padding(Space.gutter)
    }
  }
}
