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
    ViewThatFits(in: .horizontal) {
      HStack(spacing: Spacing.small) {
        streakPlate
        message
        Spacer(minLength: 0)
        giveButton
      }
      VStack(alignment: .leading, spacing: Spacing.small) {
        HStack(spacing: Spacing.small) {
          streakPlate
          message
        }
        giveButton
      }
    }
    .padding(Spacing.small)
    .frame(maxWidth: .infinity, alignment: .leading)
    .litPanel(cornerRadius: Radius.control)
  }

  private var streakPlate: some View {
    Text(verbatim: "\(streak)")
      .billetType(.numeral)
      .foregroundStyle(Palette.gold.color)
      .padding(.horizontal, Spacing.small)
      .frame(minWidth: Target.minimum, minHeight: Target.minimum)
      .background(Palette.plate.color, in: .rect(cornerRadius: Radius.plate))
      .accessibilityHidden(true)
  }

  private var message: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(streakText)
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
      Text(statusText)
        .billetType(.caption)
        .foregroundStyle(Palette.paperTurned.color)
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var giveButton: some View {
    switch status {
    case .neither, .waitingOnMe:
      Button("Give a treat", action: onGive)
        .buttonStyle(InlineButtonStyle())
    case .waitingOnPartner, .fed:
      EmptyView()
    }
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
    case 0: "Treats together start a streak"
    case 1: "1 day together"
    default: "\(streak) days together"
    }
  }
}

/// A treat that drops onto the cat once both partners have given theirs.
public struct TreatDrop: View {
  private let trigger: Bool
  @State private var fallen = false

  public init(trigger: Bool) {
    self.trigger = trigger
  }

  public var body: some View {
    Image(systemName: "fish.fill")
      .font(.system(size: 30))
      .foregroundStyle(Palette.gold.color)
      .lampGlow()
      .offset(y: fallen ? 40 : -140)
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
