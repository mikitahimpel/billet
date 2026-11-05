import DesignSystem
import FeatureInbox
import SwiftUI
import Wire

/// The way into today's drawing, small enough to sit over the room. It goes once today is drawn.
struct DailyDrawingCard: View {
  let prompt: DailyPromptText
  /// The partner has drawn today, so theirs waits behind this one.
  let partnerDrew: Bool
  let onDraw: () -> Void

  var body: some View {
    Button(action: onDraw) {
      HStack(spacing: Spacing.small) {
        Image(systemName: "paintbrush.pointed.fill")
          .foregroundStyle(Palette.gold.color)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 0) {
          Text(partnerDrew ? "Today · theirs is waiting" : "Today")
            .billetType(.caption)
            .foregroundStyle(Palette.muted.color)
          Text(prompt.text)
            .billetType(.label)
            .foregroundStyle(Palette.paper.color)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.small)
      .frame(minHeight: Target.minimum)
      .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .floatingGlass()
    .accessibilityLabel(Text("Today's drawing: \(prompt.text)"))
    .accessibilityHint(Text("Opens the canvas"))
    .accessibilityIdentifier("dailyCard")
  }
}

/// Both drawings of the day, carried in by the cat once both are drawn: the two sheets come up
/// one after the other and settle side by side.
struct DailyReveal: View {
  let entry: DailyEntry
  let catName: String?
  let onClose: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var mineIn = false
  @State private var theirsIn = false

  var body: some View {
    ZStack {
      Color.black.opacity(0.55)
        .ignoresSafeArea()
        .onTapGesture(perform: onClose)
      VStack(spacing: Spacing.large) {
        VStack(spacing: Spacing.hair) {
          Text("\(catName ?? "The cat") brought you both")
            .billetType(.caption)
            .foregroundStyle(Palette.muted.color)
          Text(entry.prompt.text)
            .billetType(.heading)
            .foregroundStyle(Palette.paper.color)
            .multilineTextAlignment(.center)
        }
        HStack(spacing: Spacing.medium) {
          sheet("You", entry.mine, tilt: -4, shown: mineIn)
          sheet("Them", entry.theirs, tilt: 4, shown: theirsIn)
        }
        Button("Lovely", action: onClose)
          .billetType(.action)
          .foregroundStyle(Palette.paper.color)
          .padding(.horizontal, Spacing.large)
          .frame(minHeight: Target.minimum)
          .floatingGlass()
          .accessibilityIdentifier("dailyRevealClose")
      }
      .padding(Spacing.large)
    }
    .sensoryFeedback(.success, trigger: theirsIn)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dailyReveal")
    .task {
      let step = reduceMotion ? Duration.zero : .milliseconds(450)
      withAnimation(reduceMotion ? nil : Motion.spring) { mineIn = true }
      try? await Task.sleep(for: step)
      withAnimation(reduceMotion ? nil : Motion.spring) { theirsIn = true }
    }
  }

  private func sheet(_ title: String, _ strokes: [Stroke]?, tilt: Double, shown: Bool) -> some View
  {
    VStack(spacing: Spacing.hair) {
      DailyPaper(strokes: strokes, blank: "", side: 480)
      Text(title)
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
    }
    .frame(maxWidth: 170)
    .rotationEffect(.degrees(shown ? tilt : 0))
    .offset(y: shown ? 0 : 420)
    .opacity(shown ? 1 : 0)
  }
}
