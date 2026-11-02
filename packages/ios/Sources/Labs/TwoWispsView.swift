import DesignSystem
import SwiftUI

/// Two curls of chimney smoke, one from each side, drawn up to `progress` of their way to a heart
/// between them. At 1 they have crossed and the heart lights.
struct WispsDrawing: View {
  let progress: Double

  var body: some View {
    Canvas { context, size in
      let (w, h) = (size.width, size.height)
      let heart = CGPoint(x: w / 2, y: h * 0.2)
      for side in [-1.0, 1.0] {
        var path = Path()
        let start = CGPoint(x: w / 2 + side * w * 0.42, y: h * 0.95)
        path.move(to: start)
        path.addCurve(
          to: heart,
          control1: CGPoint(x: w / 2 + side * w * 0.5, y: h * 0.55),
          control2: CGPoint(x: w / 2 - side * w * 0.12, y: h * 0.62))
        context.stroke(
          path.trimmedPath(from: 0, to: progress),
          with: .color(Palette.paperTurned.color.opacity(0.7)),
          style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 6]))
      }
    }
  }
}

/// Hold Mochi at the same moment as your partner and the two wisps meet. The hold is a button you
/// keep pressed; it lights up while the partner is holding too.
public struct TwoWispsSection: View {
  private let hold: TogetherHold
  private let catName: String?
  private let onHold: (Bool) -> Void

  @State private var pressing = false

  public init(hold: TogetherHold, catName: String?, onHold: @escaping (Bool) -> Void) {
    self.hold = hold
    self.catName = catName
    self.onHold = onHold
  }

  public var body: some View {
    TimelineView(
      .animation(minimumInterval: 1 / 30, paused: !hold.iAmHolding && !hold.partnerIsHolding)
    ) { context in
      let progress = hold.progress(at: context.date)
      VStack(spacing: Spacing.small) {
        ZStack {
          WispsDrawing(progress: progress)
          Image(systemName: "heart.fill")
            .font(.system(size: 26))
            .foregroundStyle(Palette.light.color)
            .shadow(color: Palette.light.color.opacity(0.8), radius: progress >= 1 ? 12 : 0)
            .opacity(progress >= 1 ? 1 : 0.25)
            .offset(y: -24)
        }
        .frame(height: 70)
        .accessibilityHidden(true)
        Text(prompt(progress: progress))
          .billetType(.label)
          .foregroundStyle(Palette.paper.color)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        holdButton
      }
      .sensoryFeedback(.success, trigger: progress >= 1) { _, together in together }
    }
    .padding(Spacing.medium)
    .frame(maxWidth: .infinity)
    .card()
    .accessibilityIdentifier("twoWisps")
  }

  private func prompt(progress: Double) -> String {
    let cat = catName ?? "the cat"
    if progress >= 1 { return "Your wisps met." }
    if hold.partnerIsHolding { return "Your partner is holding \(cat). Hold too." }
    return "Hold \(cat) when your partner does, and the wisps meet."
  }

  private var holdButton: some View {
    ButtonLabel(
      pressing ? "Holding…" : "Hold \(catName ?? "the cat")", rank: .secondary,
      systemImage: "hand.tap"
    )
    .billetButton(.secondary)
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in
          guard !pressing else { return }
          pressing = true
          onHold(true)
        }
        .onEnded { _ in
          pressing = false
          onHold(false)
        }
    )
    .accessibilityAddTraits(.isButton)
  }
}
