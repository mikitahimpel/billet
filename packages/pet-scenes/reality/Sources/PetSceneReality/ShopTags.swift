import Observation
import Pet
import SwiftUI

/// A price tag over the shop scene, at the front edge of an item, in the view's points.
struct ShopTag: Hashable, Identifiable {
  var id: ShopItem.ID
  var centre: CGPoint
  var price: Int
  /// Owned, and only ever owned once, so the tag shows a tick instead of a price.
  var owned: Bool
}

/// A glint passing over one item, where the item's top is, and how far through it is, 0 to 1.
struct ShopGlint: Equatable {
  var centre: CGPoint
  var size: CGFloat
  var phase: Double
}

/// What the shop draws over its scene: the price tags and the glint.
@MainActor
@Observable
final class ShopScreen {
  var tags: [ShopTag] = []
  var glint: ShopGlint?
  /// The tags step aside while an item is brought forward.
  var showsTags = true
}

/// The shop's price tags and its glint, over the scene. A tag is a small paper label with the
/// stamp price, and tapping it is the same as tapping its item.
struct ShopTagLayer: View {
  let screen: ShopScreen
  let onPick: (ShopItem.ID) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      ForEach(screen.tags) { tag in
        ShopTagChip(tag: tag)
          .position(tag.centre)
          .onTapGesture { onPick(tag.id) }
      }
      .opacity(screen.showsTags ? 1 : 0)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: screen.showsTags)
      if let glint = screen.glint {
        ShopSparkle(phase: glint.phase)
          .frame(width: glint.size, height: glint.size)
          .position(glint.centre)
          .allowsHitTesting(false)
      }
    }
    .accessibilityHidden(true)
  }
}

/// One price tag: a cream paper label with a stamp seal and the price, on a string.
private struct ShopTagChip: View {
  let tag: ShopTag

  private static let paper = Color(red: 1, green: 0.95, blue: 0.87)
  private static let ink = Color(red: 0.36, green: 0.2, blue: 0.14)
  private static let seal = Color(red: 0.86, green: 0.3, blue: 0.22)

  var body: some View {
    HStack(spacing: 2) {
      Image(systemName: tag.owned ? "checkmark" : "seal.fill")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(tag.owned ? Self.ink : Self.seal)
      if !tag.owned {
        Text(verbatim: "\(tag.price)")
          .font(.system(size: 12, weight: .heavy, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(Self.ink)
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Self.paper, in: .rect(cornerRadius: 5))
    .overlay(alignment: .leading) {
      Circle().fill(Self.ink.opacity(0.35)).frame(width: 3, height: 3).padding(.leading, 2)
    }
    .rotationEffect(.degrees(Double(tag.id.utf8.reduce(0) { $0 + Int($1) } % 7) - 3))
    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
    .frame(minWidth: 44, minHeight: 30)
    .contentShape(.rect)
  }
}

/// A four-pointed glint that flares and fades over `phase` from 0 to 1.
private struct ShopSparkle: View {
  let phase: Double

  var body: some View {
    let flare = sin(min(max(phase, 0), 1) * .pi)
    ZStack {
      Circle()
        .fill(
          RadialGradient(
            colors: [Color(red: 1, green: 0.9, blue: 0.65).opacity(0.7), .clear], center: .center,
            startRadius: 0, endRadius: 30))
      Star()
        .fill(Color(red: 1, green: 0.98, blue: 0.9))
        .padding(4)
    }
    .scaleEffect(0.4 + 0.6 * flare)
    .rotationEffect(.degrees(phase * 50))
    .opacity(flare)
    .blendMode(.screen)
  }

  private struct Star: Shape {
    func path(in rect: CGRect) -> Path {
      let centre = CGPoint(x: rect.midX, y: rect.midY)
      let long = min(rect.width, rect.height) / 2
      let short = long * 0.16
      var path = Path()
      for index in 0..<8 {
        let angle = Double(index) * .pi / 4 - .pi / 2
        let radius = index.isMultiple(of: 2) ? long : short
        let point = CGPoint(
          x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
      }
      path.closeSubpath()
      return path
    }
  }
}
