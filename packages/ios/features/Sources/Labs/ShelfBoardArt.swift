import DesignSystem
import SwiftUI

/// The warm wall behind the shelves, lit from the two lamps and falling away into the evening.
struct ShelfWall: View {
  private static let sparkles: [(x: Double, y: Double, size: CGFloat)] = [
    (0.9, 0.09, 12), (0.1, 0.27, 8), (0.46, 0.25, 7), (0.95, 0.42, 8),
  ]

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        LinearGradient(
          stops: [
            .init(color: Palette.plate.color, location: 0),
            .init(color: Palette.ink.color, location: 0.3),
            .init(color: Palette.ink.color, location: 0.72),
            .init(color: Palette.plate.color, location: 1),
          ],
          startPoint: .top, endPoint: .bottom)
        ForEach(Self.sparkles.indices, id: \.self) { index in
          let sparkle = Self.sparkles[index]
          Sparkle()
            .fill(Palette.gold.color.opacity(0.7))
            .frame(width: sparkle.size, height: sparkle.size)
            .position(
              x: geometry.size.width * sparkle.x, y: geometry.size.height * sparkle.y)
        }
      }
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}

/// The pool of light around the two lamps, which moves with them as the wall scrolls.
struct ShelfLampGlow: View {
  static let side: CGFloat = 840

  var body: some View {
    RadialGradient(
      colors: [
        Palette.light.color.opacity(0.42), Palette.woodLit.color.opacity(0.2),
        Palette.clayDeep.color.opacity(0.12), .clear,
      ],
      center: .center, startRadius: 0, endRadius: Self.side / 2
    )
    .frame(width: Self.side, height: Self.side)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// One plank, lit along its top edge, with its shadow on the wall below.
struct ShelfPlank: View {
  static let height: CGFloat = 13

  var body: some View {
    VStack(spacing: 0) {
      Rectangle().fill(Palette.woodLit.color).frame(height: 3)
      LinearGradient(
        colors: [Palette.wood.color, Palette.woodShade.color], startPoint: .top, endPoint: .bottom
      )
      .frame(height: Self.height - 3)
    }
    .clipShape(.rect(cornerRadius: 2))
    .background(alignment: .top) {
      LinearGradient(
        colors: [Palette.plate.color.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom
      )
      .frame(height: 26)
      .offset(y: Self.height)
    }
    .accessibilityHidden(true)
  }
}

private struct LampShade: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let inset = rect.width * 0.3
    path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY),
      control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.12))
    path.closeSubpath()
    return path
  }
}

/// A lamp hanging on its cord, the bulb showing under the shade.
struct ShelfLamp: View {
  let cord: CGFloat

  var body: some View {
    VStack(spacing: 0) {
      Rectangle().fill(Palette.woodDeep.color).frame(width: 1.5, height: cord)
      ZStack(alignment: .top) {
        Circle()
          .fill(Palette.lightWarm.color)
          .frame(width: 15, height: 15)
          .shadow(color: Palette.light.color, radius: 12)
          .shadow(color: Palette.light.color.opacity(0.7), radius: 26)
          .offset(y: 15)
        LampShade()
          .fill(
            LinearGradient(
              colors: [Palette.clay.color, Palette.clayLit.color], startPoint: .top,
              endPoint: .bottom)
          )
          .frame(width: 42, height: 22)
      }
      .frame(height: 30, alignment: .top)
    }
  }
}

/// A line of small bulbs swagged across the wall, with the two lamps hanging from it.
struct ShelfCanopy: View {
  static let height: CGFloat = 104

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let line = Self.line(width: width)
      ZStack(alignment: .topLeading) {
        line.stroke(Palette.woodLit.color.opacity(0.7), lineWidth: 1)
        ForEach(Array(stride(from: 0.06, to: 1, by: 0.11)), id: \.self) { place in
          Circle()
            .fill(Palette.lightWarm.color)
            .frame(width: 4, height: 4)
            .shadow(color: Palette.light.color, radius: 5)
            .position(Self.point(on: width, at: place))
        }
        lamp(at: 0.68, cord: 26, width: width)
        lamp(at: 0.84, cord: 36, width: width)
      }
    }
    .frame(height: Self.height)
    .accessibilityHidden(true)
  }

  private func lamp(at place: CGFloat, cord: CGFloat, width: CGFloat) -> some View {
    let top = Self.point(on: width, at: place)
    return ShelfLamp(cord: cord)
      .fixedSize()
      .position(x: top.x, y: top.y + (cord + 30) / 2)
  }

  private static func point(on width: CGFloat, at place: CGFloat) -> CGPoint {
    let sag = 4 * place * (1 - place)
    return CGPoint(x: width * place, y: 2 + sag * 22)
  }

  private static func line(width: CGFloat) -> Path {
    var path = Path()
    path.move(to: point(on: width, at: 0))
    for step in 1...40 {
      path.addLine(to: point(on: width, at: CGFloat(step) / 40))
    }
    return path
  }
}

private struct KeyShape: Shape {
  func path(in rect: CGRect) -> Path {
    let bow = rect.width * 0.5
    let stem = rect.width * 0.2
    var path = Path()
    path.addEllipse(
      in: CGRect(x: rect.midX - bow, y: rect.minY, width: bow * 2, height: bow * 2))
    path.addRect(
      CGRect(
        x: rect.midX - stem / 2, y: rect.minY + bow * 1.8, width: stem,
        height: rect.height - bow * 1.8))
    let tooth = rect.height * 0.1
    for place in [0.0, 1.7] {
      path.addRect(
        CGRect(
          x: rect.midX, y: rect.maxY - tooth * (1 + CGFloat(place)), width: rect.width * 0.46,
          height: tooth * 0.8))
    }
    return path
  }
}

/// Two keys on a ring, hanging from a hook under a shelf.
struct ShelfKeys: View {
  private func key(_ colors: [Color], angle: Double) -> some View {
    ZStack(alignment: .top) {
      KeyShape()
        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
      Circle().fill(Palette.ink.color).frame(width: 7, height: 7).offset(y: 3.5)
    }
    .frame(width: 18, height: 48)
    .rotationEffect(.degrees(angle), anchor: .top)
    .offset(y: 13)
  }

  var body: some View {
    ZStack(alignment: .top) {
      key([Palette.woodLit.color, Palette.wood.color], angle: 16)
      key([Palette.light.color, Palette.gold.color], angle: -8)
      Circle()
        .strokeBorder(Palette.gold.color, lineWidth: 2)
        .frame(width: 17, height: 17)
        .offset(y: 3)
      Capsule().fill(Palette.woodDeep.color).frame(width: 4, height: 9)
    }
    .frame(width: 44, height: 74, alignment: .top)
    .accessibilityHidden(true)
  }
}

/// A cup on the saucer, with its handle on one side.
private struct ShelfCup: View {
  let colors: [Color]
  let handleOnLeft: Bool

  var body: some View {
    ZStack(alignment: handleOnLeft ? .leading : .trailing) {
      Circle()
        .strokeBorder(colors[1], lineWidth: 3.5)
        .frame(width: 19, height: 19)
        .offset(x: handleOnLeft ? -9 : 9, y: -2)
      UnevenRoundedRectangle(
        topLeadingRadius: 2, bottomLeadingRadius: 15, bottomTrailingRadius: 15,
        topTrailingRadius: 2
      )
      .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
      .overlay(alignment: .top) {
        Capsule().fill(Palette.paper.color.opacity(0.25)).frame(height: 3).padding(.horizontal, 2)
      }
      .frame(width: 42, height: 36)
    }
  }
}

/// Two strands of steam that cross and close into a heart.
private struct CrossedSteam: Shape {
  /// One strand rises from its cup, crosses the middle and curls over the far lobe into the dip.
  var sway: CGFloat

  var animatableData: CGFloat {
    get { sway }
    set { sway = newValue }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()
    for side in [-1.0, 1.0] as [CGFloat] {
      let x = { (place: CGFloat) in rect.midX + side * place * rect.width / 2 }
      let y = { (place: CGFloat) in rect.minY + place * rect.height }
      path.move(to: CGPoint(x: x(0.46), y: y(1)))
      path.addCurve(
        to: CGPoint(x: rect.midX, y: y(0.6)),
        control1: CGPoint(x: x(0.42) + sway * 3, y: y(0.84)),
        control2: CGPoint(x: x(0.18), y: y(0.72)))
      path.addCurve(
        to: CGPoint(x: x(-0.86), y: y(0.2)),
        control1: CGPoint(x: x(-0.3), y: y(0.46)),
        control2: CGPoint(x: x(-0.86), y: y(0.38)))
      path.addCurve(
        to: CGPoint(x: rect.midX, y: y(0.17)),
        control1: CGPoint(x: x(-0.86), y: y(-0.04)),
        control2: CGPoint(x: x(-0.16), y: y(-0.06)))
    }
    return path
  }
}

/// Two cups side by side on a tray, their steam crossing into a heart.
struct ShelfCups: View {
  static let size = CGSize(width: 118, height: 150)

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var drift = false

  var body: some View {
    VStack(spacing: 0) {
      CrossedSteam(sway: drift ? 1 : -1)
        .stroke(
          LinearGradient(
            colors: [Palette.paper.color, Palette.paperTurned.color.opacity(0.75)],
            startPoint: .top, endPoint: .bottom),
          style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
        .frame(width: 84, height: 104)
        .shadow(color: Palette.light.color.opacity(0.4), radius: 6)
      HStack(alignment: .bottom, spacing: 4) {
        ShelfCup(colors: [Palette.clayLit.color, Palette.clay.color], handleOnLeft: true)
        ShelfCup(colors: [Palette.greenLit.color, Palette.green.color], handleOnLeft: false)
      }
      .scaleEffect(0.86, anchor: .bottom)
      Capsule()
        .fill(
          LinearGradient(
            colors: [Palette.paper.color, Palette.paperTurned.color], startPoint: .top,
            endPoint: .bottom)
        )
        .frame(width: 106, height: 6)
    }
    .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom)
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { drift = true }
    }
    .accessibilityHidden(true)
  }
}

/// A numbered place for a day of the streak still to come.
struct ShelfSlot: View {
  let day: Int
  let width: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: Radius.scenePlate)
      .strokeBorder(
        Palette.paperTurned.color.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
      )
      .overlay {
        Text(verbatim: "\(day)")
          .billetType(.numeral)
          .foregroundStyle(Palette.paperTurned.color.opacity(0.85))
          .minimumScaleFactor(0.5)
          .lineLimit(1)
          .padding(Spacing.hair)
      }
      .frame(width: width, height: width * ShelfNoteMetrics.tallRatio)
      .accessibilityElement()
      .accessibilityLabel("Day \(day), still to come")
  }
}

enum ShelfNoteMetrics {
  static let tallRatio: CGFloat = 1.24
  static let shortRatio: CGFloat = 1.06
}
