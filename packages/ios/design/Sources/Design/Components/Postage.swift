import SwiftUI

/// The ids match the contracts' `NoteStamp`.
public enum StampArt: String, CaseIterable, Sendable {
  case heart, moon, bloom, paw, sun

  public var name: String {
    switch self {
    case .heart: "Heart"
    case .moon: "Moon"
    case .bloom: "Bloom"
    case .paw: "Paw"
    case .sun: "Sun"
    }
  }

  var symbol: String {
    switch self {
    case .heart: "heart.fill"
    case .moon: "moon.stars.fill"
    case .bloom: "camera.macro"
    case .paw: "pawprint.fill"
    case .sun: "sun.max.fill"
    }
  }

  var field: Color {
    switch self {
    case .heart: Color(hex: 0xE4707F)
    case .moon: Color(hex: 0x3F4C7A)
    case .bloom: Color(hex: 0x7FA36B)
    case .paw: Color(hex: 0xE59A4C)
    case .sun: Color(hex: 0x6FA8CF)
    }
  }
}

/// The ids match the contracts' `NoteSeal`.
public enum SealArt: String, CaseIterable, Sendable {
  case rose, night, meadow, honey, plum

  public var name: String {
    switch self {
    case .rose: "Rose"
    case .night: "Night"
    case .meadow: "Meadow"
    case .honey: "Honey"
    case .plum: "Plum"
    }
  }

  var emblem: String {
    switch self {
    case .rose: "heart.fill"
    case .night: "moon.fill"
    case .meadow: "leaf.fill"
    case .honey: "sparkle"
    case .plum: "pawprint.fill"
    }
  }

  var wax: Color {
    switch self {
    case .rose: Color(hex: 0xB3343F)
    case .night: Color(hex: 0x2E3A66)
    case .meadow: Color(hex: 0x4E7A45)
    case .honey: Color(hex: 0xC98A2B)
    case .plum: Color(hex: 0x6E3F7F)
    }
  }
}

extension StampArt {
  /// The line printed along the stamp's foot.
  var caption: String {
    switch self {
    case .heart: "With love"
    case .moon: "Goodnight"
    case .bloom: "In bloom"
    case .paw: "Purr post"
    case .sun: "Sunny days"
    }
  }

  /// Each stamp leans its own way, so a row of them looks pinned by hand.
  public var tilt: Angle {
    switch self {
    case .heart: .degrees(-2)
    case .moon: .degrees(1.5)
    case .bloom: .degrees(-1)
    case .paw: .degrees(2)
    case .sun: .degrees(-1.5)
    }
  }
}

/// A stamp's width in points: `small` in a control, `regular` in a row, `large` on its own.
public enum StampSize: Sendable {
  case small, regular, large

  public var width: CGFloat {
    switch self {
    case .small: 22
    case .regular: 32
    case .large: 56
    }
  }
}

/// Art on paper, so it looks the same in light and dark: a perforated paper border with a faint
/// grain, an engraved double frame, a clay motif with its own depth and a caption. `rare` adds a
/// foil sheen; `postmark` cancels it with that day's ring and wavy lines across a corner. Drawn
/// once into one layer; nothing in it moves.
public struct PostageStamp: View {
  let art: StampArt
  let width: CGFloat
  let rare: Bool
  let postmark: Date?
  let pinned: Bool

  public init(
    _ art: StampArt, width: CGFloat, rare: Bool = false, postmark: Date? = nil,
    pinned: Bool = false
  ) {
    self.art = art
    self.width = width
    self.rare = rare
    self.postmark = postmark
    self.pinned = pinned
  }

  public init(
    _ art: StampArt, size: StampSize = .regular, rare: Bool = false, postmark: Date? = nil,
    pinned: Bool = false
  ) {
    self.init(art, width: size.width, rare: rare, postmark: postmark, pinned: pinned)
  }

  /// Below this width the caption, denomination and postmark date would not read, so they go.
  static let lettered: CGFloat = 44
  /// Warm paper, a step below white so the motif, not the margin, leads.
  static let paper = Color(hex: 0xEFE3CC)
  static let postmarkInk = Color(hex: 0x3B2F2A)
  static let foilLine = Color(hex: 0xD9B866)
  /// The perforation's pitch: one tooth per this many points along an edge.
  static let pitch: CGFloat = 3.2

  private var height: CGFloat { width * 1.2 }
  private var lettered: Bool { width >= Self.lettered }

  public var body: some View {
    let shape = Perforated(holes: max(7, Int((width / Self.pitch).rounded())))
    ZStack {
      shape.fill(
        LinearGradient(
          colors: [Self.paper, Self.paper.mix(with: .black, by: 0.07)], startPoint: .top,
          endPoint: .bottom
        ).shadow(.inner(color: .black.opacity(0.18), radius: 0.6)))
      PaperGrain(seed: art.rawValue.utf8.reduce(0) { $0 &* 31 &+ Int($1) })
        .clipShape(shape)
      field
        .padding(width * 0.11)
      if let postmark {
        // About three fifths of the ring on the stamp, its waves ending before the denomination.
        Postmark(date: postmark, lettered: lettered)
          .frame(width: width * 0.62, height: width * 0.62)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .offset(x: -width * 0.1, y: -width * 0.08)
          .clipShape(shape)
      }
    }
    .frame(width: width, height: height)
    .drawingGroup()
    .shadow(color: .black.opacity(0.1), radius: max(0.5, width * 0.012), y: width * 0.008)
    .shadow(color: .black.opacity(0.16), radius: width * 0.05, y: width * 0.035)
    .rotationEffect(pinned ? art.tilt : .zero)
    .accessibilityElement()
    .accessibilityLabel(rare ? "Rare \(art.name.lowercased()) stamp" : "\(art.name) stamp")
    .accessibilityValue(
      postmark.map { "Postmarked \($0.formatted(.dateTime.day().month(.wide)))" } ?? "")
  }

  /// The art's colour brought into the seals' range: a little less saturated, a little darker.
  private var ink: Color {
    art.field.mix(with: Color(hex: 0x808080), by: 0.09).mix(with: .black, by: 0.06)
  }

  private var field: some View {
    let ground = LinearGradient(
      colors: [ink.mix(with: .white, by: 0.12), ink.mix(with: .black, by: 0.14)],
      startPoint: .topLeading, endPoint: .bottomTrailing)
    let outer = max(0.5, width * 0.023)
    let engraving = Self.paper
    return ZStack {
      Rectangle()
        .fill(
          ground.shadow(
            .inner(color: .black.opacity(0.28), radius: width * 0.035, x: 0, y: width * 0.012)))
      Rectangle()
        .strokeBorder(rare ? Self.foilLine : engraving.opacity(0.55), lineWidth: outer)
        .padding(width * 0.035)
      if width >= 28 {
        Rectangle()
          .strokeBorder(engraving.opacity(0.4), lineWidth: outer * 0.66)
          .padding(width * 0.035 + outer + width * 0.047)
      }
      motif
        .padding(.top, lettered ? width * 0.08 : 0)
        .padding(.bottom, lettered ? width * 0.14 : 0)
      if lettered { lettering }
      if rare { foil }
    }
  }

  /// Debossed like the seal's emblem: a disc darker than the field, shaded at its top left, and a
  /// light glyph with a dark edge above it and a lit edge below.
  private var motif: some View {
    let disc = width * 0.78 * 0.55
    let glyph = disc * 0.6
    let edge = max(0.5, width * 0.02)
    return ZStack {
      Circle()
        .fill(
          ink.mix(with: .black, by: 0.1).shadow(
            .inner(color: .black.opacity(0.4), radius: width * 0.025, x: edge, y: edge)))
      Image(systemName: art.symbol)
        .resizable()
        .scaledToFit()
        .foregroundStyle(.white.opacity(0.35))
        .frame(width: glyph, height: glyph)
        .offset(x: edge * 0.5, y: edge * 0.5)
      Image(systemName: art.symbol)
        .resizable()
        .scaledToFit()
        .foregroundStyle(ink.mix(with: .black, by: 0.45))
        .frame(width: glyph, height: glyph)
        .offset(x: -edge, y: -edge)
      Image(systemName: art.symbol)
        .resizable()
        .scaledToFit()
        .foregroundStyle(
          LinearGradient(
            colors: [Self.paper, Self.paper.mix(with: ink, by: 0.25)], startPoint: .topLeading,
            endPoint: .bottomTrailing)
        )
        .frame(width: glyph, height: glyph)
    }
    .frame(width: disc, height: disc)
  }

  private var lettering: some View {
    VStack(spacing: 0) {
      Text("1")
        .font(.system(size: width * 0.13, weight: .heavy, design: .serif))
        .frame(maxWidth: .infinity, alignment: .trailing)
      Spacer(minLength: 0)
      Text(art.caption)
        .font(.system(size: width * 0.085, weight: .bold, design: .serif).smallCaps())
        .tracking(width * 0.085 * 0.04)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
    .foregroundStyle(Self.paper.opacity(0.9))
    .padding(.horizontal, width * 0.085)
    .padding(.vertical, width * 0.06)
    .accessibilityHidden(true)
  }

  /// A narrow band of light across the field, as foil catches it; the gold frame does the rest.
  private var foil: some View {
    LinearGradient(
      stops: [
        .init(color: .clear, location: 0.38),
        .init(color: .white.opacity(0.32), location: 0.44),
        .init(color: .clear, location: 0.5),
      ], startPoint: UnitPoint(x: 0, y: 0.15), endPoint: UnitPoint(x: 1, y: 0.75)
    )
    .blendMode(.plusLighter)
  }
}

/// The paper's fibres: a fixed scatter of faint flecks, the same for every drawing of one art.
private struct PaperGrain: View {
  let seed: Int

  var body: some View {
    Canvas { context, size in
      var state = UInt64(truncatingIfNeeded: seed) | 1
      func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(state >> 33) / CGFloat(UInt32.max >> 1)
      }
      let flecks = Int(size.width * size.height / 9)
      for _ in 0..<flecks {
        let point = CGPoint(x: next() * size.width, y: next() * size.height)
        let side = 0.4 + next() * 0.6
        context.fill(
          Path(CGRect(origin: point, size: CGSize(width: side, height: side))),
          with: .color(Color(hex: 0x6B5A3E).opacity(0.05 + next() * 0.07)))
      }
    }
  }
}

/// A cancellation: a double ring with the day inside and three waves running off to the right.
private struct Postmark: View {
  let date: Date
  let lettered: Bool

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let line = max(0.6, side * 0.035)
      ZStack(alignment: .topLeading) {
        Circle()
          .strokeBorder(PostageStamp.postmarkInk, lineWidth: line)
        Circle()
          .strokeBorder(PostageStamp.postmarkInk, lineWidth: line * 0.6)
          .padding(side * 0.1)
        if lettered {
          VStack(spacing: 0) {
            Text(date.formatted(.dateTime.day()))
              .font(.system(size: side * 0.24, weight: .bold, design: .serif))
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
              .font(.system(size: side * 0.14, weight: .bold, design: .serif))
          }
          .frame(width: side, height: side)
        }
        // Broken now and then, as rubber-stamped ink is.
        Waves()
          .stroke(
            PostageStamp.postmarkInk,
            style: StrokeStyle(lineWidth: line, lineCap: .round, dash: [line * 5, line * 0.8])
          )
          .frame(width: side * 0.5, height: side * 0.5)
          .offset(x: side * 0.9, y: side * 0.25)
      }
      .foregroundStyle(PostageStamp.postmarkInk)
    }
    .opacity(0.55)
    .rotationEffect(.degrees(-12))
    .blendMode(.multiply)
    .accessibilityHidden(true)
  }
}

private struct Waves: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      for line in 0..<3 {
        let y = rect.minY + rect.height * (0.2 + 0.3 * CGFloat(line))
        path.move(to: CGPoint(x: rect.minX, y: y))
        let steps = 24
        for step in 1...steps {
          let t = CGFloat(step) / CGFloat(steps)
          path.addLine(
            to: CGPoint(
              x: rect.minX + rect.width * t,
              y: y + sin(t * .pi * 4) * rect.height * 0.08))
        }
      }
    }
  }
}

public struct WaxSeal: View {
  let art: SealArt
  let size: CGFloat

  public init(_ art: SealArt, size: CGFloat) {
    self.art = art
    self.size = size
  }

  public var body: some View {
    ZStack {
      WaxBlob()
        .fill(
          RadialGradient(
            colors: [
              art.wax.mix(with: .white, by: 0.22), art.wax, art.wax.mix(with: .black, by: 0.25),
            ],
            center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: size * 0.62))
      Circle()
        .strokeBorder(art.wax.mix(with: .black, by: 0.3), lineWidth: max(1, size * 0.04))
        .padding(size * 0.17)
      Image(systemName: art.emblem)
        .resizable()
        .scaledToFit()
        .foregroundStyle(art.wax.mix(with: .black, by: 0.32))
        .shadow(color: .white.opacity(0.3), radius: 0, x: size * 0.012, y: size * 0.018)
        .padding(size * 0.33)
    }
    .frame(width: size, height: size)
    .compositingGroup()
    .shadow(color: .black.opacity(0.28), radius: size * 0.05, y: size * 0.03)
    .accessibilityElement()
    .accessibilityLabel("\(art.name) seal")
  }
}

extension View {
  /// Stamp top trailing, seal low leading, both inside the note's frame and sized to `width`. A
  /// `postmark` cancels the stamp on the day the note was sent.
  public func postage(
    stamp: StampArt?, seal: SealArt?, width: CGFloat, postmark: Date? = nil
  ) -> some View {
    overlay(alignment: .topTrailing) {
      if let stamp {
        PostageStamp(stamp, width: width * 0.16, postmark: postmark)
          .rotationEffect(.degrees(4))
          .padding(width * 0.045)
      }
    }
    .overlay(alignment: .bottomLeading) {
      if let seal {
        WaxSeal(seal, size: width * 0.19)
          .rotationEffect(.degrees(-8))
          .padding(width * 0.05)
      }
    }
  }
}

/// `holes` counts the bites along the shorter side.
struct Perforated: Shape {
  let holes: Int

  func path(in rect: CGRect) -> Path {
    let step = min(rect.width, rect.height) / CGFloat(holes)
    // Deep, round bites, so the edge reads as torn-off teeth and not as a scalloped sticker.
    let radius = step * 0.38
    var bites = Path()
    func row(from start: CGPoint, along direction: CGVector, length: CGFloat) {
      let count = max(1, Int((length / step).rounded()))
      let gap = length / CGFloat(count)
      for index in 0...count {
        let center = CGPoint(
          x: start.x + direction.dx * gap * CGFloat(index),
          y: start.y + direction.dy * gap * CGFloat(index))
        bites.addEllipse(
          in: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
      }
    }
    row(
      from: CGPoint(x: rect.minX, y: rect.minY), along: CGVector(dx: 1, dy: 0), length: rect.width)
    row(
      from: CGPoint(x: rect.minX, y: rect.maxY), along: CGVector(dx: 1, dy: 0), length: rect.width)
    row(
      from: CGPoint(x: rect.minX, y: rect.minY), along: CGVector(dx: 0, dy: 1), length: rect.height)
    row(
      from: CGPoint(x: rect.maxX, y: rect.minY), along: CGVector(dx: 0, dy: 1), length: rect.height)
    return Path(rect).subtracting(bites)
  }
}

struct WaxBlob: Shape {
  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2
    let steps = 72
    return Path { path in
      for index in 0...steps {
        let angle = Double(index) / Double(steps) * 2 * .pi
        let wobble = 1 - 0.035 * (1 + sin(angle * 7)) - 0.02 * (1 + cos(angle * 3 + 1))
        let point = CGPoint(
          x: center.x + cos(angle) * radius * wobble, y: center.y + sin(angle) * radius * wobble)
        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
      }
      path.closeSubpath()
    }
  }
}

#Preview("Postage") {
  BothSchemes {
    VStack(spacing: Space.l) {
      HStack(spacing: Space.m) {
        ForEach(StampArt.allCases, id: \.self) { PostageStamp($0, width: 48, pinned: true) }
      }
      HStack(spacing: Space.m) {
        PostageStamp(.heart, size: .small)
        PostageStamp(.moon, size: .regular, rare: true)
        PostageStamp(.sun, size: .large, postmark: Date(timeIntervalSince1970: 1_762_776_000))
      }
      HStack(spacing: Space.m) {
        ForEach(SealArt.allCases, id: \.self) { WaxSeal($0, size: 48) }
      }
      Color(hex: 0xFFE7A0)
        .frame(width: 220, height: 220)
        .overlay {
          Text("miss you already").font(.ourioTitle).foregroundStyle(Color(hex: 0x2B2B2E))
        }
        .postage(stamp: .moon, seal: .rose, width: 220)
    }
  }
}
