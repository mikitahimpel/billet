import DesignSystem
import SwiftUI

/// The couple's notes from the backend, newest first, with the
/// streak above and a way to try again when loading fails.
public struct HistoryView: View {
  private let model: HistoryModel
  private let streak: Int?

  @Environment(\.scenePhase) private var scenePhase

  public init(model: HistoryModel, streak: Int? = nil) {
    self.model = model
    self.streak = streak
  }

  public var body: some View {
    VStack(spacing: 0) {
      banner
      NotesView(notes: model.records, loadFailed: false)
    }
    .task(id: scenePhase) {
      if scenePhase == .active { model.refresh() }
    }
  }

  @ViewBuilder private var banner: some View {
    VStack(spacing: Spacing.small) {
      StreakBadge(days: streak)
      if let failure = model.failure {
        Text(failure.message)
          .billetType(.body)
          .foregroundStyle(Palette.paper.color)
          .multilineTextAlignment(.center)
          .accessibilityIdentifier("historyError")
        BilletButton("Try again", rank: .secondary) { model.refresh() }
      } else if model.hiddenCount > 0 {
        Text(
          model.hiddenCount == 1
            ? "1 photo note isn't shown yet." : "\(model.hiddenCount) photo notes aren't shown yet."
        )
        .billetType(.body)
        .foregroundStyle(Palette.muted.color)
      }
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.top, Spacing.small)
  }
}

extension HistoryFailure {
  /// What the screen tells the user.
  var message: String {
    switch self {
    case .signedOut: "You've been signed out. Open the app again to sign in."
    case .notPaired: "Pair with your partner to see your notes."
    case .unavailable: "Notes can't be loaded right now."
    }
  }
}
