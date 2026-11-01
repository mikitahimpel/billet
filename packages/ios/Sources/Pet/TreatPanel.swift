import SwiftUI

/// The day's treat, who has given, and the shared streak. Shows state and sends one tap upward.
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
    VStack(spacing: 6) {
      Text(streakText)
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.85))
      switch status {
      case .neither, .waitingOnMe:
        Button("Give a treat", action: onGive)
          .buttonStyle(.bordered)
          .tint(.white)
        if status == .waitingOnMe {
          Text("Partner gave theirs. Your turn.").font(.footnote).foregroundStyle(.white)
        }
      case .waitingOnPartner:
        Text("Your treat is in. Waiting for your partner.").font(.footnote).foregroundStyle(.white)
      case .fed:
        Text("Both treats given. The cat is happy.").font(.footnote).foregroundStyle(.white)
      }
    }
    .multilineTextAlignment(.center)
    .accessibilityElement(children: .combine)
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
      .foregroundStyle(.orange)
      .offset(y: fallen ? 40 : -140)
      .opacity(trigger ? (fallen ? 0 : 1) : 0)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .onChange(of: trigger) { _, now in
        guard now else {
          fallen = false
          return
        }
        withAnimation(.easeIn(duration: 0.9)) { fallen = true }
      }
  }
}
