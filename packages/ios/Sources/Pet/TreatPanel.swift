import DesignSystem
import SwiftUI

/// The day's treat, who has given, and the shared streak. Shows state and sends one tap upward.
/// The streak hangs on a house number, like the one by the door.
public struct TreatPanel: View {
  private let status: TreatLedger.Status
  private let streak: Int
  private let onGive: () -> Void

  public init(status: TreatLedger.Status, streak: Int, onGive: @escaping () -> Void) {
    self.status = status
    self.streak = streak
    self.onGive = onGive
  }

  public var body: some View {
    ListRow(streakText, subtitle: statusText) {
      streakPlate
    } trailing: {
      switch status {
      case .neither, .waitingOnMe:
        IconButton("fish", label: "Give a treat", action: onGive)
          .transition(.opacity)
      case .waitingOnPartner, .fed:
        RowIcon(status == .fed ? "checkmark.circle.fill" : "hourglass", color: Palette.gold)
          .frame(width: Target.minimum, height: Target.minimum)
          .transition(.opacity)
      }
    }
    .card()
    .calmAnimation(value: status)
  }

  private var streakPlate: some View {
    Text(verbatim: "\(streak)")
      .billetType(.numeral)
      .foregroundStyle(Palette.gold.color)
      .contentTransition(.numericText(value: Double(streak)))
      .calmAnimation(value: streak)
      .frame(minWidth: Target.minimum, minHeight: Target.minimum)
      .background(Palette.plate.color, in: .rect(cornerRadius: Radius.plate))
      .accessibilityHidden(true)
  }

  private var statusText: String {
    switch status {
    case .neither: "One each, every day"
    case .waitingOnMe: "Partner gave theirs. Your turn."
    case .waitingOnPartner: "Yours is in. Waiting for your partner."
    case .fed: "Both given. The cat is happy."
    }
  }

  private var streakText: String {
    switch streak {
    case 0: "Start a streak"
    case 1: "1 day together"
    default: "\(streak) days together"
    }
  }
}

/// A treat that drops onto the cat once both partners have given theirs.
public struct TreatDrop: View {
  private let trigger: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var fallen = false

  public init(trigger: Bool) {
    self.trigger = trigger
  }

  public var body: some View {
    Image(systemName: "fish.fill")
      .font(IconStyle.font)
      .scaleEffect(1.6)
      .foregroundStyle(Palette.gold.color)
      .lampGlow()
      .offset(y: reduceMotion ? 0 : (fallen ? Spacing.section : -Spacing.page * 2))
      .opacity(trigger ? (fallen ? 0 : 1) : 0)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .onChange(of: trigger) { _, now in
        guard now else {
          fallen = false
          return
        }
        withAnimation(.easeIn(duration: 1.1)) { fallen = true }
      }
  }
}
