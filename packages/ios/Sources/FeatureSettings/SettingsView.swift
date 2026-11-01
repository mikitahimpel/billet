import DesignSystem
import Foundation
import PetScene
import SwiftUI
import UserNotifications

#if canImport(UIKit)
  import UIKit
#endif

/// Partner and pair status, the pet scene, notifications, links, app version, and log out.
public struct SettingsView: View {
  private static let privacyPolicy = URL(
    string: "https://github.com/mikitahimpel/billet/blob/main/docs/privacy.md")
  private static let feedback = URL(string: "mailto:gimpelllll@gmail.com?subject=billet%20feedback")

  private let code: String
  private let partnerStatus: String
  private let scenes: [any PetScene]
  @Binding private var selectedSceneID: String?
  private let onLogOut: () async -> String?

  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @State private var notifications: String?
  @State private var confirmingLogOut = false
  @State private var loggingOut = false
  @State private var logOutError: String?

  /// - Parameter onLogOut: Logs out and returns a message to show if that failed.
  public init(
    code: String,
    partnerStatus: String,
    scenes: [any PetScene],
    selectedSceneID: Binding<String?>,
    onLogOut: @escaping () async -> String?
  ) {
    self.code = code
    self.partnerStatus = partnerStatus
    self.scenes = scenes
    _selectedSceneID = selectedSceneID
    self.onLogOut = onLogOut
  }

  public var body: some View {
    ZStack {
      EveningBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.large) {
          Text("Settings").screenTitle()
          pair
          if scenes.count > 1 {
            sceneSection
          }
          notificationSection
          links
          logOut
          version
        }
        .padding(Spacing.medium)
      }
    }
    .task(id: scenePhase) { notifications = await Self.notificationStatus() }
    .eveningDialog(isPresented: $confirmingLogOut) {
      EveningDialog(
        title: "Log out of billet?",
        message: "This forgets the pair code and deletes the notes on this device. You and your "
          + "partner will need a new code to pair again."
      ) {
        Button("Log out") {
          confirmingLogOut = false
          performLogOut()
        }
        .buttonStyle(DestructiveButtonStyle())
        Button("Cancel") { confirmingLogOut = false }
          .buttonStyle(SecondaryButtonStyle())
      }
    }
  }

  private var pair: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      SettingsHeading("Pair")
      SettingsGroup {
        SettingsRow("Partner", value: partnerStatus)
      }
      PairCodeCard(code: code)
    }
  }

  private var sceneSection: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      SettingsHeading("Scene")
      PetScenePicker(scenes: scenes, selectedSceneID: $selectedSceneID)
    }
  }

  private var notificationSection: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      SettingsHeading("Notifications")
      SettingsGroup {
        SettingsRow("Status", value: notifications ?? "Checking…")
        SettingsSeparator()
        SettingsLink("Open iOS Settings") {
          #if canImport(UIKit)
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
              openURL(url)
            }
          #endif
        }
      }
    }
  }

  private var links: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      SettingsHeading("About")
      SettingsGroup {
        SettingsLink("Privacy Policy") {
          if let url = Self.privacyPolicy { openURL(url) }
        }
        SettingsSeparator()
        SettingsLink("Send feedback") {
          if let url = Self.feedback { openURL(url) }
        }
      }
    }
  }

  private var logOut: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Button(loggingOut ? "Logging out…" : "Log out") {
        confirmingLogOut = true
      }
      .buttonStyle(SecondaryButtonStyle())
      .disabled(loggingOut)
      if let logOutError {
        Text(logOutError)
          .billetType(.label)
          .foregroundStyle(Palette.paper.color)
      }
    }
  }

  private var version: some View {
    let info = Bundle.main.infoDictionary
    let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return Text("Version \(marketing) (build \(build))")
      .billetType(.label)
      .foregroundStyle(Palette.muted.color)
      .frame(maxWidth: .infinity)
  }

  private func performLogOut() {
    loggingOut = true
    logOutError = nil
    Task {
      logOutError = await onLogOut()
      loggingOut = false
    }
  }

  private static func notificationStatus() async -> String {
    switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
    case .authorized: "On"
    case .provisional: "Quiet"
    case .ephemeral: "On for now"
    case .denied: "Off"
    case .notDetermined: "Not set up"
    @unknown default: "Unknown"
    }
  }
}

/// Rows sharing one lit panel.
private struct SettingsGroup<Rows: View>: View {
  private let rows: Rows

  init(@ViewBuilder rows: () -> Rows) {
    self.rows = rows()
  }

  var body: some View {
    VStack(spacing: 0) { rows }
      .frame(maxWidth: .infinity)
      .litPanel(cornerRadius: Radius.control)
  }
}

private struct SettingsSeparator: View {
  var body: some View {
    Palette.paper.color.opacity(0.1)
      .frame(height: 1)
      .padding(.horizontal, Spacing.medium)
  }
}

private struct SettingsHeading: View {
  private let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .billetType(.label)
      .foregroundStyle(Palette.muted.color)
      .accessibilityAddTraits(.isHeader)
  }
}

/// A label and its value, which stack when large text no longer fits one line.
private struct SettingsRow: View {
  private let title: String
  private let value: String

  init(_ title: String, value: String) {
    self.title = title
    self.value = value
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack {
        titleText
        Spacer(minLength: Spacing.medium)
        valueText
      }
      VStack(alignment: .leading, spacing: Spacing.hair) {
        titleText
        valueText
      }
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.vertical, Spacing.small)
    .frame(maxWidth: .infinity, minHeight: Target.minimum, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private var titleText: some View {
    Text(title).billetType(.body).foregroundStyle(Palette.paper.color)
  }

  private var valueText: some View {
    Text(value).billetType(.body).foregroundStyle(Palette.muted.color)
  }
}

private struct SettingsLink: View {
  private let title: String
  private let action: () -> Void

  init(_ title: String, action: @escaping () -> Void) {
    self.title = title
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack {
        Text(title).billetType(.body)
        Spacer(minLength: Spacing.medium)
        Image(systemName: "arrow.up.forward").accessibilityHidden(true)
      }
      .foregroundStyle(Palette.paper.color)
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.small)
      .frame(maxWidth: .infinity, minHeight: Target.minimum)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
  }
}
