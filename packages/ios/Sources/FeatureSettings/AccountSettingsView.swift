import DesignSystem
import SwiftUI

/// Settings of a signed-in account: the delivery check, unpair and sign out. `onFinished` is called
/// with what finished so the app can move to the screen that follows.
public struct AccountSettingsView: View {
  private let model: AccountModel
  private let onFinished: (AccountAction) -> Void

  public init(model: AccountModel, onFinished: @escaping (AccountAction) -> Void) {
    self.model = model
    self.onFinished = onFinished
  }

  public var body: some View {
    ScreenScaffold("Settings") {
      VStack(alignment: .leading, spacing: Spacing.large) {
        healthSection
        accountSection
        failure
      }
    }
    .task { await model.checkHealth() }
    .onChange(of: model.state) { _, state in
      if case .done(let action) = state { onFinished(action) }
    }
    .confirmationDialog(
      confirmation?.title ?? "", isPresented: confirming, titleVisibility: .visible
    ) {
      if let confirmation {
        Button(confirmation.button, role: .destructive) { model.confirm() }
      }
      Button("Cancel", role: .cancel) { model.cancel() }
    } message: {
      Text(confirmation?.message ?? "")
    }
  }

  private var healthSection: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      SettingsHeading("Delivery")
      SettingsGroup {
        if let report = model.report {
          ForEach(Array(report.lines.enumerated()), id: \.offset) { index, line in
            if index > 0 { ListDivider() }
            SettingsRow(line.title, value: line.ok ? line.detail : "⚠︎ \(line.detail)")
          }
        } else {
          SettingsRow("Status", value: "Checking…")
        }
        ListDivider()
        SettingsLink("Check again") { Task { await model.checkHealth() } }
      }
      .accessibilityIdentifier("deliveryHealth")
    }
  }

  private var accountSection: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      SettingsHeading("Account")
      SettingsGroup {
        SettingsLink("Unpair") { model.request(.unpair) }
        ListDivider()
        SettingsLink("Sign out") { model.request(.signOut) }
      }
    }
  }

  @ViewBuilder private var failure: some View {
    if case .failed(let action, let failure, _) = model.state {
      Text(Self.message(for: failure, action: action))
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityIdentifier("accountError")
    }
  }

  private struct Confirmation {
    var title: String
    var message: String
    var button: String
  }

  private var confirmation: Confirmation? {
    guard case .confirming(let action, _) = model.state else { return nil }
    return Self.confirmation(for: action)
  }

  private var confirming: Binding<Bool> {
    Binding(
      get: { confirmation != nil },
      set: { presented in
        if !presented, case .confirming = model.state { model.cancel() }
      })
  }

  private static func confirmation(for action: AccountAction) -> Confirmation {
    switch action {
    case .unpair:
      Confirmation(
        title: "Unpair from your partner?",
        message: "You'll stop sending and receiving notes until you pair again.",
        button: "Unpair")
    case .signOut:
      Confirmation(
        title: "Sign out?",
        message: "This phone forgets your account. Sign in again to carry on.",
        button: "Sign out")
    }
  }

  static func message(for failure: AccountFailure, action: AccountAction) -> String {
    switch (failure, action) {
    case (.unavailable, _): "Billet can't be reached right now. Try again in a moment."
    case (.storage, .unpair): "You're unpaired, but this phone couldn't save that. Try again."
    case (.storage, .signOut): "This phone couldn't forget your account. Try again."
    }
  }
}
