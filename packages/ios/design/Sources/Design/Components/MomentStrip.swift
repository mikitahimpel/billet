import SwiftUI

/// One stop on a `MomentStrip`: what happened and when, in a word or two each.
public struct StripMoment: Identifiable, Hashable, Sendable {
  public let id: String
  let symbol: String
  let tint: Color
  let title: String
  let time: String

  public init(id: String, symbol: String, tint: Color, title: String, time: String) {
    self.id = id
    self.symbol = symbol
    self.tint = tint
    self.title = title
    self.time = time
  }
}

/// A day as a short timeline on a card of its own: marks along a rail, oldest first, opened at the
/// latest. It scrolls sideways under the card's edges, which fade it out; at accessibility sizes
/// it is a list, newest first.
public struct MomentStrip: View {
  let moments: [StripMoment]
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(_ moments: [StripMoment]) { self.moments = moments }

  static let mark: CGFloat = Size.tileMark
  /// How far in from each edge the strip fades out.
  static let fade: CGFloat = CardMetrics.padding

  public var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      GroupedSection {
        ForEach(moments.reversed()) { moment in
          Row(moment.title, detail: moment.time, symbol: moment.symbol, tint: moment.tint)
        }
      }
    } else {
      ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: Space.xs) {
          ForEach(moments) { moment in
            if moment.id != moments.first?.id { link }
            stop(moment)
          }
        }
        .padding(.horizontal, CardMetrics.padding)
      }
      .scrollIndicators(.hidden)
      // Opened at the latest moment; a day too short to scroll still starts at the leading edge.
      .defaultScrollAnchor(.trailing, for: .initialOffset)
      .mask { edges }
      .padding(.vertical, CardMetrics.padding)
      .cardSurface()
    }
  }

  private func stop(_ moment: StripMoment) -> some View {
    VStack(spacing: Space.xs) {
      RowIcon(symbol: moment.symbol, tint: moment.tint, size: Self.mark, style: .well)
      Text(moment.title)
        .font(.ourioCaption)
        .foregroundStyle(Ink.text)
      Text(moment.time)
        .font(.ourioMicro)
        .foregroundStyle(Ink.textSecondary)
    }
    .lineLimit(1)
    .fixedSize()
    .frame(minWidth: Size.button)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(moment.title), \(moment.time)")
  }

  /// The rail between two marks, at their mid-height.
  private var link: some View {
    Capsule()
      .fill(Ink.separator)
      .frame(width: Space.m, height: Space.xxs)
      .padding(.top, Self.mark / 2)
      .accessibilityHidden(true)
  }

  private var edges: some View {
    HStack(spacing: 0) {
      LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
        .frame(width: Self.fade)
      Color.black
      LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
        .frame(width: Self.fade)
    }
  }
}

#Preview("Moment strip") {
  BothSchemes {
    MomentStrip([
      StripMoment(id: "1", symbol: "moon.zzz.fill", tint: .lilac, title: "Slept", time: "till 7"),
      StripMoment(id: "2", symbol: "fork.knife", tint: .honey, title: "Ate", time: "8:12"),
      StripMoment(id: "3", symbol: "binoculars.fill", tint: .sage, title: "Watched", time: "10"),
      StripMoment(id: "4", symbol: "heart.fill", tint: .blushPink, title: "Petted", time: "12:40"),
      StripMoment(id: "5", symbol: "moon.zzz.fill", tint: .lilac, title: "Napped", time: "14"),
      StripMoment(id: "6", symbol: "tennisball.fill", tint: .sage, title: "Played", time: "18:05"),
    ])
    .padding(Space.gutter)
  }
}
