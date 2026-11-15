import SwiftUI

/// A chunky bar that fills from the leading edge to `value` (0…1): a level's progress, a trait.
/// One shape on a track; it moves only when `value` changes.
public struct MeterBar: View {
  let value: Double
  let tint: Color
  @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = Space.m

  public init(value: Double, tint: Color = .honey) {
    self.value = value
    self.tint = tint
  }

  public var body: some View {
    Capsule()
      .fill(tint.opacity(Gauge.trackOpacity))
      .overlay { MeterFill(value: Gauge.clamp(value)).fill(Gauge.face(tint)) }
      .frame(height: height)
      .animation(Motion.spring(), value: value)
      .accessibilityHidden(true)
  }
}

/// The filled end of a `MeterBar`: never shorter than it is tall, so a low value is still a dot.
private struct MeterFill: Shape {
  var value: Double

  var animatableData: Double {
    get { value }
    set { value = newValue }
  }

  func path(in rect: CGRect) -> Path {
    guard value > 0 else { return Path() }
    let width = max(rect.height, rect.width * value)
    return Path(
      roundedRect: CGRect(
        x: rect.minX, y: rect.minY, width: min(width, rect.width), height: rect.height),
      cornerRadius: rect.height / 2)
  }
}

enum Gauge {
  static let trackOpacity = 0.22

  static func clamp(_ value: Double) -> Double {
    value.isFinite ? min(max(value, 0), 1) : 0
  }

  /// Lit from above, like a clay `RowIcon`.
  static func face(_ tint: Color) -> LinearGradient {
    LinearGradient(
      colors: [tint.mix(with: Ink.paper, by: 0.3), tint], startPoint: .top, endPoint: .bottom)
  }

  /// A glyph in `tint` that reads on a card in either scheme, as a well `RowIcon`'s does.
  static func glyph(_ tint: Color, in scheme: ColorScheme) -> Color {
    scheme == .dark ? tint.mix(with: .white, by: 0.15) : tint.mix(with: Ink.heroInk, by: 0.45)
  }
}

/// An arc of a circle from `start`, `sweep` of a turn long at `fill` = 1.
private struct RingArc: Shape {
  let start: Angle
  let sweep: Angle
  var fill: Double

  var animatableData: Double {
    get { fill }
    set { fill = newValue }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard fill > 0 else { return path }
    path.addArc(
      center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
      startAngle: start, endAngle: start + sweep * fill, clockwise: false)
    return path
  }
}

/// A ring of equal segments, each filled along its own arc to its value (0…1): several levels read
/// at once round an avatar. The first segment is the upper leading quarter and the rest follow
/// clockwise. Over glass or art, so the track is `Ink.glassRim` and nothing is blurred.
public struct SegmentedRing: View {
  public struct Segment: Hashable, Sendable {
    let value: Double
    let tint: Color

    public init(value: Double, tint: Color) {
      self.value = value
      self.tint = tint
    }
  }

  let segments: [Segment]
  let lineWidth: CGFloat
  @Environment(\.colorScheme) private var colorScheme

  public init(_ segments: [Segment], lineWidth: CGFloat = 4) {
    self.segments = segments
    self.lineWidth = lineWidth
  }

  /// The clear stretch between two segments, round caps included, as a share of one segment.
  static let gap = 0.2

  public var body: some View {
    let count = max(segments.count, 1)
    let span = 360.0 / Double(count)
    let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
    ZStack {
      ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
        let start = Angle.degrees(180 + span * (Double(index) + Self.gap / 2))
        let sweep = Angle.degrees(span * (1 - Self.gap))
        RingArc(start: start, sweep: sweep, fill: 1).stroke(Ink.glassRim, style: style)
        // The light glass under it is cream: a pastel arc needs deepening to stand off it.
        RingArc(start: start, sweep: sweep, fill: Gauge.clamp(segment.value))
          .stroke(
            colorScheme == .dark ? segment.tint : segment.tint.mix(with: Ink.heroInk, by: 0.25),
            style: style)
      }
    }
    .padding(lineWidth / 2)
    .animation(Motion.spring(), value: segments)
    .accessibilityHidden(true)
  }
}

/// A level read at a glance on a tile of its own: a ring that fills to `value` round a glyph, the
/// percentage, a name over the state in a word or two, a hint of what comes next, and at the foot
/// either the action a tap on the tile runs or a note when nothing can be done. Tiles go in an
/// `ItemGrid`. `raised` is for the one level that wants something now: its state takes the accent
/// and its action turns solid, so it reads first.
public struct GaugeTile: View {
  public enum Emphasis: Hashable, Sendable {
    case quiet
    case raised
  }

  let title: String
  let state: String
  let hint: String
  let value: Double
  let symbol: String
  let tint: Color
  let emphasis: Emphasis
  let foot: String
  let spoken: String?
  let perform: (() -> Void)?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.colorScheme) private var colorScheme
  @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 46
  @ScaledMetric(relativeTo: .title3) private var line: CGFloat = 6

  /// - Parameters:
  ///   - spoken: Read by VoiceOver after the state, in place of `hint`.
  ///   - action: The words on the pill at the foot; the whole tile is the button.
  public init(
    _ title: String, state: String, hint: String, value: Double, symbol: String,
    tint: Color = .honey, emphasis: Emphasis = .quiet, spoken: String? = nil, action: String,
    perform: @escaping () -> Void
  ) {
    self.title = title
    self.state = state
    self.hint = hint
    self.value = value
    self.symbol = symbol
    self.tint = tint
    self.emphasis = emphasis
    self.foot = action
    self.spoken = spoken
    self.perform = perform
  }

  /// A level nothing can be done about: `note` says why, at the foot.
  public init(
    _ title: String, state: String, hint: String, value: Double, symbol: String,
    tint: Color = .honey, emphasis: Emphasis = .quiet, spoken: String? = nil, note: String
  ) {
    self.title = title
    self.state = state
    self.hint = hint
    self.value = value
    self.symbol = symbol
    self.tint = tint
    self.emphasis = emphasis
    self.foot = note
    self.spoken = spoken
    self.perform = nil
  }

  private var percent: Int { Int((Gauge.clamp(value) * 100).rounded()) }

  public var body: some View {
    if let perform {
      Button(action: perform) { tile }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(title)
        .accessibilityValue("\(state), \(percent) percent, \(spoken ?? hint)")
        .accessibilityHint(foot)
    } else {
      tile
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(state), \(percent) percent, \(spoken ?? hint), \(foot)")
    }
  }

  /// At accessibility sizes the ring sits beside the words and the tile takes the full width.
  private var tile: some View {
    VStack(alignment: .leading, spacing: Space.s) {
      if dynamicTypeSize.isAccessibilitySize {
        ring
        words
      } else {
        HStack(alignment: .top) {
          ring
          Spacer(minLength: Space.s)
          Text("\(percent)%")
            .font(.ourioCallout.monospacedDigit())
            .foregroundStyle(Ink.textSecondary)
            .contentTransition(.numericText())
        }
        words
      }
      Spacer(minLength: 0)
      footer
    }
    .padding(CardMetrics.padding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .cardSurface()
    .contentShape(.rect(cornerRadius: Radius.card))
    .animation(Motion.fade(), value: emphasis)
  }

  private var ring: some View {
    ZStack {
      Circle().stroke(tint.opacity(Gauge.trackOpacity), lineWidth: line)
      RingArc(start: .degrees(-90), sweep: .degrees(360), fill: Gauge.clamp(value))
        // The raised level's arc is the tint at full strength, so the lowest ring is not the palest.
        .stroke(
          emphasis == .raised ? AnyShapeStyle(tint) : AnyShapeStyle(Gauge.face(tint)),
          style: StrokeStyle(lineWidth: line, lineCap: .round))
      Image(systemName: symbol)
        .font(.system(size: side * 0.36, weight: .semibold))
        .foregroundStyle(Gauge.glyph(tint, in: colorScheme))
    }
    .padding(line / 2)
    .frame(width: side, height: side)
    .animation(Motion.spring(), value: value)
  }

  private var words: some View {
    VStack(alignment: .leading, spacing: Space.xxs) {
      Text(title)
        .font(.ourioCaption)
        .foregroundStyle(Ink.textSecondary)
      Text(state)
        .font(.ourioHeadline)
        .foregroundStyle(emphasis == .raised ? Ink.accentText : Ink.text)
        .contentTransition(.opacity)
      Text(hint)
        .font(.ourioCaption)
        .foregroundStyle(Ink.textSecondary)
        .contentTransition(.opacity)
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder private var footer: some View {
    if perform == nil {
      Text(foot)
        .font(.ourioCaption)
        .foregroundStyle(Ink.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: Size.pill, alignment: .leading)
    } else {
      switch emphasis {
      case .quiet:
        pill
          .foregroundStyle(Ink.accentText)
          .background(Ink.surfaceRaised, in: .capsule)
          .overlay { Capsule().strokeBorder(Ink.accentText.opacity(0.45), lineWidth: 1) }
      case .raised:
        pill
          .foregroundStyle(Ink.heroInk)
          .background(.honeyFace, in: .capsule)
      }
    }
  }

  /// Drawn like `PillButtonStyle`, but only a label: the whole tile is the button.
  private var pill: some View {
    Text(foot)
      .font(.ourioCallout.weight(.semibold))
      .lineLimit(1)
      .padding(.horizontal, Space.m)
      .frame(maxWidth: .infinity, minHeight: Size.pill)
  }
}

#Preview("Gauges") {
  BothSchemes {
    VStack(alignment: .leading, spacing: Space.l) {
      HStack(spacing: Space.l) {
        Circle().fill(Ink.surfaceRaised)
          .frame(width: 64, height: 64)
          .overlay {
            SegmentedRing([
              .init(value: 0.3, tint: .honey), .init(value: 0.9, tint: .lilac),
              .init(value: 0.6, tint: .blushPink), .init(value: 0.75, tint: .sage),
            ])
          }
        VStack(alignment: .leading, spacing: Space.s) {
          MeterBar(value: 0.4)
          MeterBar(value: 0.02, tint: .lilac)
          MeterBar(value: 1, tint: .sage)
        }
      }
      ItemGrid {
        GaugeTile(
          "Full", state: "Hungry", hint: "Would love a meal", value: 0.3,
          symbol: "fork.knife", emphasis: .raised, action: "Feed"
        ) {}
        GaugeTile(
          "Rested", state: "Wide awake", hint: "Fine for today", value: 0.9,
          symbol: "moon.zzz.fill", tint: .lilac, note: "Only sleep fills it")
        GaugeTile(
          "Playful", state: "Curious", hint: "Bored in about 4 h", value: 0.6,
          symbol: "tennisball.fill", tint: .sage, action: "Play"
        ) {}
        GaugeTile(
          "Loved", state: "Adored", hint: "Lonely in about 9 h", value: 0.75,
          symbol: "heart.fill", tint: .blushPink, action: "Pet"
        ) {}
      }
    }
    .padding(Space.gutter)
  }
}
