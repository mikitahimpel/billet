import DesignSystem
import Pet
import PetScene
import SwiftUI

/// "Tap the bowl to feed", over the bowl with a soft ring round it, the first time the cat is
/// hungry and until the bowl is first filled.
struct BowlHint: View {
  let screen: GenzRoomScreen
  let shows: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulsing = false

  var body: some View {
    ZStack {
      if shows, let bowl = screen.bowl {
        Circle()
          .strokeBorder(Palette.gold.color.opacity(0.9), lineWidth: 2)
          .frame(width: Self.ring, height: Self.ring)
          .scaleEffect(pulsing && !reduceMotion ? 1.15 : 1)
          .opacity(pulsing && !reduceMotion ? 0.5 : 1)
          .position(bowl)
        Label(Self.text, systemImage: "hand.tap.fill")
          .billetType(.label)
          .foregroundStyle(Palette.paper.color)
          .padding(.horizontal, Spacing.medium)
          .padding(.vertical, Spacing.small)
          .floatingGlass()
          .fixedSize()
          .position(x: bowl.x, y: bowl.y - Self.ring / 2 - Spacing.large)
          .accessibilityIdentifier("bowlHint")
      }
    }
    .allowsHitTesting(false)
    .transition(.opacity)
    .calmAnimation(value: shows)
    .onAppear {
      withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulsing = true }
    }
  }

  static let text = "Tap the bowl to feed"
  /// About a finger's reach across, the area a tap fills the bowl from.
  static let ring: CGFloat = 64

  /// Whether the cat wants food now, as its brain feels it, else as its needs say.
  static func wantsFood(_ play: PetPlayState) -> Bool {
    if let feeling = play.brain?.feeling { return feeling == .hungry || feeling == .hangry }
    return (play.lifeNeeds?.full ?? 1) < LifeConfig.standard.lowBelow
  }
}
