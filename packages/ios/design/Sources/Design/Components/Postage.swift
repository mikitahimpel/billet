import SwiftUI

/// The postage stamps a note can carry, as art: a glyph on a coloured field inside a perforated
/// white edge. The ids match the contracts' `NoteStamp`.
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

/// The wax seals a note can be closed with: a colour of wax and the emblem pressed into it. The
/// ids match the contracts' `NoteSeal`.
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

/// A postage stamp `width` points wide, a little taller than wide. It is art on paper, so it looks
/// the same in light and dark.
public struct PostageStamp: View {
  let art: StampArt
  let width: CGFloat

  public init(_ art: StampArt, width: CGFloat) {
    self.art = art
    self.width = width
  }

  public var body: some View {
    let inset = width * 0.11
    ZStack {
      Perforated(holes: 6)
        .fill(Color(hex: 0xFFFBF3))
      Rectangle()
        .fill(art.field)
        .padding(inset)
      Image(systemName: art.symbol)
        .resizable()
        .scaledToFit()
        .foregroundStyle(Color(hex: 0xFFFBF3).opacity(0.92))
        .padding(width * 0.3)
    }
    .frame(width: width, height: width * 1.2)
    .compositingGroup()
    .shadow(color: .black.opacity(0.18), radius: width * 0.03, y: width * 0.02)
    .accessibilityElement()
    .accessibilityLabel("\(art.name) stamp")
  }
}

/// A wax seal `size` points across: an uneven disc of wax with a pressed ring and emblem.
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
  /// Puts a note's stamp in its top trailing corner and its seal low on its leading side, both
  /// inside the note's frame and sized to its `width`. Either may be `nil`.
  public func postage(stamp: StampArt?, seal: SealArt?, width: CGFloat) -> some View {
    overlay(alignment: .topTrailing) {
      if let stamp {
        PostageStamp(stamp, width: width * 0.16)
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

/// A rectangle with half-round bites along every edge, `holes` along the shorter side.
struct Perforated: Shape {
  let holes: Int

  func path(in rect: CGRect) -> Path {
    let step = min(rect.width, rect.height) / CGFloat(holes)
    let radius = step * 0.28
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

/// A disc whose edge wobbles a little, as poured wax does.
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
        ForEach(StampArt.allCases, id: \.self) { PostageStamp($0, width: 48) }
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
