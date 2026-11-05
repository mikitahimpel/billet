import DesignSystem
import Foundation
import StoreKit
import SwiftUI
import UserNotifications

#if canImport(UIKit)
  import UIKit
#endif

/// Two small overlapping portraits, me in front and my partner behind: the way into "Us" from the
/// top-left of Home. Warm paper on the evening scene, no chrome, so it sits in the room rather than
/// over it.
public struct PairAvatars: View {
  private let me: String
  private let partner: String?
  private let size: CGFloat

  /// - Parameters:
  ///   - me: A letter or emoji for me.
  ///   - partner: The same for my partner; `nil` while unpaired, shown as an empty seat.
  /// The two halves until there are pictures: the sun for me, the moon for my partner.
  public static let me = "☀︎"
  public static let partner = "☾"

  public init(me: String = Self.me, partner: String? = Self.partner, size: CGFloat = 30) {
    self.me = me
    self.partner = partner
    self.size = size
  }

  public var body: some View {
    ZStack(alignment: .leading) {
      portrait(partner ?? "", filled: partner != nil)
        .offset(x: size * 0.62)
      portrait(me, filled: true)
    }
    .frame(width: size * 1.62, height: size, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Us")
    .accessibilityIdentifier("pairAvatars")
  }

  private func portrait(_ text: String, filled: Bool) -> some View {
    Circle()
      .fill(filled ? Palette.paperTurned.color : Palette.paper.color.opacity(0.18))
      .overlay(
        Text(text)
          .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
          .foregroundStyle(Palette.ink.color)
      )
      .overlay(Circle().stroke(Palette.pageDeep.color.opacity(0.55), lineWidth: 1.5))
      .frame(width: size, height: size)
      .shadow(color: Palette.pageDeep.color.opacity(0.35), radius: 3, y: 1)
  }
}

/// The top of "Us": the two of us, the cat's name, how long we have been together and the streak.
public struct UsHeader: View {
  private let me: String
  private let partner: String?
  private let catName: String?
  private let daysTogether: Int?
  private let streak: Int

  public init(me: String, partner: String?, catName: String?, daysTogether: Int?, streak: Int) {
    self.me = me
    self.partner = partner
    self.catName = catName
    self.daysTogether = daysTogether
    self.streak = streak
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      PairAvatars(me: me, partner: partner, size: 44)
      Text(catName ?? "Your cat")
        .billetType(.heading)
        .foregroundStyle(Palette.paper.color)
      HStack(spacing: Spacing.medium) {
        if let daysTogether {
          Text(Self.together(daysTogether))
        }
        Label("\(streak)", systemImage: "flame.fill")
          .foregroundStyle(streak > 0 ? Palette.light.color : Palette.muted.color)
          .accessibilityLabel(Self.streakLabel(streak))
      }
      .billetType(.body)
      .foregroundStyle(Palette.muted.color)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("usHeader")
  }

  static func together(_ days: Int) -> String {
    days == 1 ? "1 day together" : "\(days) days together"
  }

  static func streakLabel(_ streak: Int) -> String {
    streak == 1 ? "1 day streak" : "\(streak) day streak"
  }
}

/// Where the cat's character card goes: its temperament and habits, from the cat's brain. Until a
/// card is passed in, a quiet line holds the place.
public struct CatCharacterSection<Card: View>: View {
  private let catName: String?
  private let card: Card?

  public init(catName: String?, card: Card?) {
    self.catName = catName
    self.card = card
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      SettingsHeading("Character")
      if let card {
        card
      } else {
        SettingsGroup {
          SettingsRow(catName ?? "Your cat", value: "Still getting to know you")
        }
      }
    }
    .accessibilityIdentifier("catCharacter")
  }
}

extension CatCharacterSection where Card == EmptyView {
  /// The place held, before the cat's brain can describe it.
  public init(catName: String?) {
    self.init(catName: catName, card: nil)
  }
}

/// Whether the account is safe beyond this phone: always in iCloud, and with Sign in with Apple
/// on any phone. `linkControls` is the Sign in with Apple block, shown while it isn't linked.
public struct AccountSavedSection<LinkControls: View>: View {
  private let linked: Bool
  private let linkControls: LinkControls

  public init(linked: Bool, @ViewBuilder linkControls: () -> LinkControls) {
    self.linked = linked
    self.linkControls = linkControls()
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      SettingsHeading("Account")
      SettingsGroup {
        SettingsRow("Saved in iCloud", value: "✓")
        if linked {
          ListDivider()
          SettingsRow("Sign in with Apple", value: "✓")
        }
      }
      if !linked {
        Text("Sign in with Apple too, so a phone without this iCloud account finds your cat.")
          .billetType(.caption)
          .foregroundStyle(Palette.muted.color)
          .padding(.horizontal, Spacing.medium)
        linkControls
      }
    }
    .accessibilityIdentifier("accountSaved")
  }
}

/// Whether notes can reach this phone, and the way to the system's switches.
public struct NotificationsSection: View {
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @State private var status: String?

  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      SettingsHeading("Notifications")
      SettingsGroup {
        SettingsRow("Status", value: status ?? "Checking…")
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
    .task(id: scenePhase) { status = await Self.status() }
  }

  private static func status() async -> String {
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

/// The privacy policy, feedback and the version.
public struct AboutSection: View {
  private static let privacyPolicy = URL(
    string: "https://github.com/mikitahimpel/billet/blob/main/docs/privacy.md")
  private static let feedback = URL(string: "mailto:gimpelllll@gmail.com?subject=billet%20feedback")

  @Environment(\.openURL) private var openURL

  public init() {}

  public var body: some View {
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
      Text(Self.version)
        .billetType(.label)
        .foregroundStyle(Palette.muted.color)
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.small)
    }
  }

  private static var version: String {
    let info = Bundle.main.infoDictionary
    let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "Version \(marketing) (build \(build))"
  }
}

/// Where this build came from: Labs show in builds for testing, a debug build or TestFlight, and
/// are hidden only where StoreKit confirms the App Store.
public enum BuildChannel {
  public static func isForTesting() async -> Bool {
    #if DEBUG
      return true
    #else
      return isForTesting(environment: await environment())
    #endif
  }

  /// Only a confirmed App Store build is not for testing. TestFlight reports `.sandbox`, Xcode
  /// `.xcode`, and `nil` (StoreKit failed or did not answer) counts as testing, so a TestFlight
  /// build never loses Labs to a StoreKit hiccup.
  static func isForTesting(environment: AppStore.Environment?) -> Bool {
    environment != .production
  }

  /// The environment `AppTransaction` reports, or `nil` if it fails or takes over three seconds.
  private static func environment() async -> AppStore.Environment? {
    await withTaskGroup(of: AppStore.Environment?.self) { group in
      group.addTask {
        switch try? await AppTransaction.shared {
        case .verified(let app), .unverified(let app, _): app.environment
        case nil: nil
        }
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(3))
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }
}
