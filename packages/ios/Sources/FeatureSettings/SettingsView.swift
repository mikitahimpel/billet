import DesignSystem
import Foundation
import Pet
import PetScene
import SwiftUI
import UserNotifications
import WidgetBridge

#if canImport(UIKit)
  import UIKit
#endif

/// Partner and pair status, the pet scene, notifications, links, app version, and log out.
public struct SettingsView: View {
  private static let privacyPolicy = URL(
    string: "https://github.com/mikitahimpel/billet/blob/main/docs/privacy.md")
  private static let feedback = URL(string: "mailto:gimpelllll@gmail.com?subject=billet%20feedback")

  private let code: String?
  private let labs: WidgetFeaturesModel?
  private let partnerStatus: String
  private let catName: String?
  private let scenes: [any PetScene]
  @Binding private var selectedSceneID: String?
  private let widgetFeatures: WidgetFeaturesModel?
  private let isFakePartner: Bool
  private let onLogOut: () async -> String?
  /// Plays the first launch again without touching the pair, or `nil` where it cannot.
  private let onReplayOnboarding: (() -> Void)?

  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @State private var notifications: String?
  @State private var confirmingLogOut = false
  @State private var loggingOut = false
  @State private var logOutError: String?

  /// - Parameter onLogOut: Logs out and returns a message to show if that failed.
  public init(
    code: String?,
    labs: WidgetFeaturesModel? = nil,
    partnerStatus: String,
    catName: String? = nil,
    scenes: [any PetScene],
    selectedSceneID: Binding<String?>,
    widgetFeatures: WidgetFeaturesModel? = nil,
    isFakePartner: Bool = false,
    onReplayOnboarding: (() -> Void)? = nil,
    onLogOut: @escaping () async -> String?
  ) {
    self.isFakePartner = isFakePartner
    self.onReplayOnboarding = onReplayOnboarding
    self.code = code
    self.labs = labs
    self.partnerStatus = partnerStatus
    self.catName = catName
    self.scenes = scenes
    _selectedSceneID = selectedSceneID
    self.widgetFeatures = widgetFeatures
    self.onLogOut = onLogOut
  }

  public var body: some View {
    ScreenScaffold("Settings") {
      pair
      if scenes.count > 1 {
        sceneSection
      }
      notificationSection
      if let widgetFeatures {
        widgetSection(widgetFeatures)
      }
      if let labs {
        labSection(labs)
      }
      links
      logOut
      version
    }
    .task(id: scenePhase) { notifications = await Self.notificationStatus() }
    .alert("Log out of billet?", isPresented: $confirmingLogOut) {
      Button("Log out", role: .destructive) { performLogOut() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(Self.logOutWarning(isFakePartner: isFakePartner))
    }
  }

  private var pair: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      SettingsHeading("Pair")
      SettingsGroup {
        SettingsRow("Partner", value: partnerStatus)
        ListDivider()
        SettingsRow("Cat", value: catName ?? "Not named yet")
        if let temperament = labs?.temperamentRecord?.temperament {
          ListDivider()
          SettingsRow("Character", value: "\(temperament.title). \(temperament.line)")
            .accessibilityIdentifier("settings.character")
        }
      }
      if let code {
        PairCodeCard(code: code)
      }
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
        ListDivider()
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

  /// One switch per widget and Lock Screen feature, grouped by what it does.
  private func widgetSection(_ model: WidgetFeaturesModel) -> some View {
    VStack(alignment: .leading, spacing: Spacing.medium) {
      SettingsHeading("Widgets & Lock Screen")
      ForEach(WidgetFeature.Group.allCases, id: \.self) { group in
        VStack(alignment: .leading, spacing: Spacing.small) {
          Text(group.title)
            .billetType(.caption)
            .foregroundStyle(Palette.muted.color)
            .padding(.horizontal, Spacing.medium)
          SettingsGroup {
            let features = WidgetFeature.allCases.filter { $0.group == group }
            ForEach(features, id: \.self) { feature in
              if feature != features.first { ListDivider() }
              ToggleRow(
                feature.title, subtitle: feature.detail,
                isOn: Binding(
                  get: { model.isOn(feature) }, set: { model.set(feature, on: $0) }))
            }
          }
        }
      }
    }
  }

  /// One switch per experiment, grouped by what it is for.
  private func labSection(_ model: WidgetFeaturesModel) -> some View {
    VStack(alignment: .leading, spacing: Spacing.medium) {
      SettingsHeading("Labs")
      EveningGroundPicker(model: model)
      HomeVariantPicker(model: model)
      if scenes.contains(where: { !$0.roomStyles.isEmpty }) {
        RoomStylePicker(model: model)
        WindowViewPicker(model: model)
      }
      if scenes.contains(where: { !$0.roomStyles.isEmpty }) {
        LightingPicker(model: model)
        FurniturePicker(model: model)
      }
      if let cats = scenes.first(where: { !$0.cats.isEmpty })?.cats {
        CatPicker(model: model, cats: cats)
      }
      if scenes.contains(where: { $0.hasShop }) {
        ShopkeeperPicker(model: model)
      }
      ForEach(LabExperiment.Group.allCases, id: \.self) { group in
        VStack(alignment: .leading, spacing: Spacing.small) {
          Text(group.title)
            .billetType(.caption)
            .foregroundStyle(Palette.muted.color)
            .padding(.horizontal, Spacing.medium)
          SettingsGroup {
            let experiments = LabExperiment.allCases.filter { $0.group == group }
            ForEach(experiments, id: \.self) { experiment in
              if experiment != experiments.first { ListDivider() }
              ToggleRow(
                experiment.title, subtitle: experiment.detail,
                isOn: Binding(
                  get: { model.isOn(experiment) }, set: { model.set(experiment, on: $0) }))
            }
            if group == .firstLaunch, let onReplayOnboarding {
              ListDivider()
              SettingsLink("Replay onboarding", action: onReplayOnboarding)
            }
          }
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
        ListDivider()
        SettingsLink("Send feedback") {
          if let url = Self.feedback { openURL(url) }
        }
      }
    }
  }

  private var logOut: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      BilletButton(loggingOut ? "Logging out…" : "Log out", rank: .secondary) {
        confirmingLogOut = true
      }
      .disabled(loggingOut)
      if let logOutError {
        Text(logOutError)
          .billetType(.label)
          .foregroundStyle(Palette.paper.color)
          .padding(.horizontal, Spacing.medium)
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

  static func logOutWarning(isFakePartner: Bool) -> String {
    isFakePartner
      ? "This ends the practice run and deletes its notes, the cat's name, the streak and "
        + "anything bought in it. Nothing was shared with anyone."
      : "This forgets the pair code and deletes the notes on this device. You and your partner "
        + "will need a new code to pair again."
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

/// Rows sharing one card.
struct SettingsGroup<Rows: View>: View {
  private let rows: Rows

  init(@ViewBuilder rows: () -> Rows) {
    self.rows = rows()
  }

  var body: some View {
    VStack(spacing: 0) { rows }
      .frame(maxWidth: .infinity)
      .card()
  }
}

struct SettingsHeading: View {
  private let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .billetType(.label)
      .foregroundStyle(Palette.muted.color)
      .padding(.horizontal, Spacing.medium)
      .accessibilityAddTraits(.isHeader)
  }
}

/// A label and its value.
struct SettingsRow: View {
  private let title: String
  private let value: String

  init(_ title: String, value: String) {
    self.title = title
    self.value = value
  }

  var body: some View {
    ListRow(title) {
      EmptyView()
    } trailing: {
      Text(value)
        .billetType(.body)
        .foregroundStyle(Palette.muted.color)
        .multilineTextAlignment(.trailing)
        .contentTransition(.opacity)
    }
    .accessibilityElement(children: .combine)
  }
}

struct SettingsLink: View {
  private let title: String
  private let action: () -> Void

  init(_ title: String, action: @escaping () -> Void) {
    self.title = title
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      ListRow(title) {
        EmptyView()
      } trailing: {
        RowIcon("arrow.up.forward")
      }
    }
    .buttonStyle(RowButtonStyle())
  }
}
