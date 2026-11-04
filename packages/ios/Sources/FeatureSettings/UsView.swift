import DesignSystem
import Foundation
import Pet
import PetScene
import SwiftUI
import WidgetBridge

/// "Us", opened from the two avatars on Home: the two of us and the cat, its character, where the
/// account is saved, notifications, the app icon and widgets, the pair, and about. Labs come last, and only in
/// builds for testing.
public struct UsView<Account: View>: View {
  private let code: String?
  private let labs: WidgetFeaturesModel?
  private let partnerStatus: String
  private let catName: String?
  /// A few habits the cat has learned, in plain words.
  private let habits: [String]
  private let streak: Int
  private let daysTogether: Int?
  private let scenes: [any PetScene]
  private let widgetFeatures: WidgetFeaturesModel?
  private let isFakePartner: Bool
  private let onRenameCat: ((String) -> Void)?
  private let onUnpair: () async -> String?
  /// Plays the first launch again without touching the pair, or `nil` where it cannot.
  private let onReplayOnboarding: (() -> Void)?
  private let account: Account

  @State private var showsLabs = false
  @State private var labsOpen = false
  @State private var confirmingUnpair = false
  @State private var unpairing = false
  @State private var unpairError: String?
  @State private var renaming = false
  @State private var newName = ""

  /// - Parameters:
  ///   - account: Where the account is saved; empty where there is no account, as in the demo.
  ///   - onUnpair: Unpairs and returns a message to show if that failed.
  public init(
    code: String?,
    labs: WidgetFeaturesModel? = nil,
    partnerStatus: String,
    catName: String? = nil,
    habits: [String] = [],
    streak: Int = 0,
    daysTogether: Int? = nil,
    scenes: [any PetScene],
    widgetFeatures: WidgetFeaturesModel? = nil,
    isFakePartner: Bool = false,
    onRenameCat: ((String) -> Void)? = nil,
    onReplayOnboarding: (() -> Void)? = nil,
    onUnpair: @escaping () async -> String?,
    @ViewBuilder account: () -> Account
  ) {
    self.isFakePartner = isFakePartner
    self.onReplayOnboarding = onReplayOnboarding
    self.code = code
    self.labs = labs
    self.partnerStatus = partnerStatus
    self.catName = catName
    self.habits = habits
    self.streak = streak
    self.daysTogether = daysTogether
    self.scenes = scenes
    self.widgetFeatures = widgetFeatures
    self.onRenameCat = onRenameCat
    self.onUnpair = onUnpair
    self.account = account()
  }

  /// Labs is pushed inside the sheet rather than stacked as a second sheet on top of it.
  public var body: some View {
    NavigationStack {
      us
        .hidesNavigationBar()
        .showsSheetGround()
        .navigationDestination(isPresented: $labsOpen) {
          if let labs {
            ScreenScaffold("Labs", closes: false) { labContent(labs) }
              .showsSheetGround()
          }
        }
    }
    .tint(Palette.paper.color)
  }

  private var us: some View {
    ScreenScaffold("Us") {
      UsHeader(
        me: PairAvatars.me, partner: PairAvatars.partner, catName: catName,
        daysTogether: daysTogether, streak: streak)
      CatCharacterSection(catName: catName, card: characterCard)
      account
      NotificationsSection()
      AppIconSection()
      if let widgetFeatures {
        widgetSection(widgetFeatures)
      }
      pair
      AboutSection()
      if showsLabs, labs != nil {
        SettingsGroup {
          SettingsLink("Labs") { labsOpen = true }
            .accessibilityIdentifier("us.labs")
        }
      }
    }
    .task { showsLabs = await BuildChannel.isForTesting() }
    .alert("Unpair from your partner?", isPresented: $confirmingUnpair) {
      Button("Unpair", role: .destructive) { performUnpair() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(Self.unpairWarning(isFakePartner: isFakePartner))
    }
    .alert("Rename the cat", isPresented: $renaming) {
      TextField("Name", text: $newName)
      Button("Rename") { onRenameCat?(newName) }
      Button("Cancel", role: .cancel) {}
    }
  }

  /// What the cat's brain knows of its character, once it knows anything.
  private var characterCard: AnyView? {
    let temperament = labs?.temperamentRecord?.temperament
    guard temperament != nil || !habits.isEmpty else { return nil }
    return AnyView(
      SettingsGroup {
        if let temperament {
          SettingsRow(temperament.title, value: temperament.line)
            .accessibilityIdentifier("settings.character")
        }
        ForEach(habits, id: \.self) { habit in
          if temperament != nil || habit != habits.first { ListDivider() }
          SettingsRow(habit, value: "")
        }
      })
  }

  private var pair: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      SettingsHeading("Pair")
      SettingsGroup {
        SettingsRow("Partner", value: partnerStatus)
        if isFakePartner {
          ListDivider()
          SettingsRow("Fake partner", value: "Scripted replies, on this phone only")
            .accessibilityIdentifier("settings.fakePartner")
        }
        if onRenameCat != nil {
          ListDivider()
          SettingsLink("Rename \(catName ?? "the cat")") {
            newName = catName ?? ""
            renaming = true
          }
          .accessibilityIdentifier("us.renameCat")
        }
        ListDivider()
        SettingsLink(unpairing ? "Unpairing…" : "Unpair") { confirmingUnpair = true }
          .disabled(unpairing)
          .accessibilityIdentifier("us.unpair")
      }
      if let unpairError {
        Text(unpairError)
          .billetType(.label)
          .foregroundStyle(Palette.paper.color)
          .padding(.horizontal, Spacing.medium)
      }
      if let code {
        PairCodeCard(code: code)
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

  /// The pickers, then one switch per experiment, grouped by what it is for.
  private func labContent(_ model: WidgetFeaturesModel) -> some View {
    VStack(alignment: .leading, spacing: Spacing.medium) {
      EveningGroundPicker(model: model)
      HomeVariantPicker(model: model)
      if scenes.contains(where: \.hasRoom) {
        HomeRoomPicker(model: model)
        WindowViewPicker(model: model)
        LightingPicker(model: model)
        FurniturePicker(model: model)
      }
      if let cats = scenes.first(where: { !$0.cats.isEmpty })?.cats {
        CatPicker(model: model, cats: cats)
      }
      ForEach(LabExperiment.Group.allCases, id: \.self) { group in
        let experiments = LabExperiment.allCases.filter { $0.group == group }
        // The first launch has no switches, only a way to watch it again.
        let replay = group == .firstLaunch ? replayOnboarding : nil
        if !experiments.isEmpty || replay != nil {
          VStack(alignment: .leading, spacing: Spacing.small) {
            Text(group.title)
              .billetType(.caption)
              .foregroundStyle(Palette.muted.color)
              .padding(.horizontal, Spacing.medium)
            SettingsGroup {
              ForEach(experiments, id: \.self) { experiment in
                if experiment != experiments.first { ListDivider() }
                ToggleRow(
                  experiment.title, subtitle: experiment.detail,
                  isOn: Binding(
                    get: { model.isOn(experiment) }, set: { model.set(experiment, on: $0) }))
              }
              if let replay {
                if !experiments.isEmpty { ListDivider() }
                SettingsLink("Replay onboarding", action: replay)
              }
            }
          }
        }
      }
    }
  }

  /// Closes Labs first, so the replay is not covered by it.
  private var replayOnboarding: (() -> Void)? {
    guard let onReplayOnboarding else { return nil }
    return {
      labsOpen = false
      onReplayOnboarding()
    }
  }

  static func unpairWarning(isFakePartner: Bool) -> String {
    isFakePartner
      ? "This ends the practice run and deletes its notes, the cat's name, the streak and "
        + "anything bought in it. Nothing was shared with anyone."
      : "This forgets the pair code and deletes the notes on this device. You and your partner "
        + "will need a new code to pair again."
  }

  private func performUnpair() {
    unpairing = true
    unpairError = nil
    Task {
      unpairError = await onUnpair()
      unpairing = false
    }
  }
}

extension UsView where Account == EmptyView {
  /// "Us" with no account, as in the demo.
  public init(
    code: String?,
    labs: WidgetFeaturesModel? = nil,
    partnerStatus: String,
    catName: String? = nil,
    habits: [String] = [],
    streak: Int = 0,
    daysTogether: Int? = nil,
    scenes: [any PetScene],
    widgetFeatures: WidgetFeaturesModel? = nil,
    isFakePartner: Bool = false,
    onRenameCat: ((String) -> Void)? = nil,
    onReplayOnboarding: (() -> Void)? = nil,
    onUnpair: @escaping () async -> String?
  ) {
    self.init(
      code: code, labs: labs, partnerStatus: partnerStatus, catName: catName, habits: habits,
      streak: streak, daysTogether: daysTogether, scenes: scenes,
      widgetFeatures: widgetFeatures,
      isFakePartner: isFakePartner, onRenameCat: onRenameCat,
      onReplayOnboarding: onReplayOnboarding, onUnpair: onUnpair, account: { EmptyView() })
  }
}

extension View {
  /// Lets the sheet's ground show through the navigation stack, which is opaque by default.
  fileprivate func showsSheetGround() -> some View {
    #if os(iOS)
      containerBackground(.clear, for: .navigation)
    #else
      self
    #endif
  }

  /// The sheet's own title and grabber stand in for a navigation bar on the first screen.
  fileprivate func hidesNavigationBar() -> some View {
    #if os(iOS)
      toolbar(.hidden, for: .navigationBar)
    #else
      self
    #endif
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
