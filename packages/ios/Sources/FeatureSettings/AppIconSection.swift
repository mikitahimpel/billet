import DesignSystem
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// The home-screen icons billet ships. Each one is an app icon set in the app's asset catalog, with
/// a `<name>Thumb` image beside it for this picker, since an icon set can't be loaded as an image.
public enum AppIconChoice: String, CaseIterable, Sendable {
  case twoCats
  case asleep
  case loveLetter
  case nightWindow
  case heartWindow

  /// The icon set's name for `setAlternateIconName`, or `nil` for the primary icon.
  public var alternateName: String? {
    switch self {
    case .twoCats: nil
    case .asleep: "AppIconAsleep"
    case .loveLetter: "AppIconLetter"
    case .nightWindow: "AppIconNight"
    case .heartWindow: "AppIconHeartWindow"
    }
  }

  var thumbnail: String { "\(alternateName ?? "AppIcon")Thumb" }

  var title: String {
    switch self {
    case .twoCats: "Two cats"
    case .asleep: "Asleep"
    case .loveLetter: "Love letter"
    case .nightWindow: "Night window"
    case .heartWindow: "Heart window"
    }
  }

  /// The choice for the icon iOS reports as current; an unknown name falls back to the primary.
  public init(alternateName: String?) {
    self = Self.allCases.first { $0.alternateName == alternateName } ?? .twoCats
  }
}

/// Us → App icon: one row per icon with its picture and a check on the current one.
public struct AppIconSection: View {
  @State private var current = AppIconChoice.twoCats
  @State private var failed = false

  public init() {}

  public var body: some View {
    #if canImport(UIKit)
      if UIApplication.shared.supportsAlternateIcons {
        content
          .task { current = AppIconChoice(alternateName: UIApplication.shared.alternateIconName) }
      }
    #endif
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      SettingsHeading("App icon")
      SettingsGroup {
        ForEach(AppIconChoice.allCases, id: \.self) { choice in
          if choice != AppIconChoice.allCases.first { ListDivider() }
          row(choice)
        }
      }
    }
    .alert("The icon didn't change", isPresented: $failed) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("iOS didn't accept the change. Try again in a moment.")
    }
  }

  private func row(_ choice: AppIconChoice) -> some View {
    let selected = current == choice
    return Button {
      choose(choice)
    } label: {
      ListRow(choice.title) {
        Image(choice.thumbnail)
          .resizable()
          .frame(width: 44, height: 44)
          .clipShape(.rect(cornerRadius: 10, style: .continuous))
          .accessibilityHidden(true)
      } trailing: {
        if selected {
          RowIcon("checkmark", color: Palette.gold)
            .transition(.opacity)
        }
      }
    }
    .buttonStyle(RowButtonStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("app-icon-\(choice.rawValue)")
    .sensoryFeedback(.selection, trigger: selected)
  }

  private func choose(_ choice: AppIconChoice) {
    #if canImport(UIKit)
      guard choice != current else { return }
      let previous = current
      withAnimation(Motion.spring) { current = choice }
      Task {
        do {
          try await UIApplication.shared.setAlternateIconName(choice.alternateName)
        } catch {
          withAnimation(Motion.spring) { current = previous }
          failed = true
        }
      }
    #endif
  }
}
