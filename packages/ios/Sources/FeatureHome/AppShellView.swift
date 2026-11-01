import DesignSystem
import FeatureInbox
import FeatureSettings
import PetScene
import SwiftUI

/// The three tabs of a paired device. Drawing is opened from Home and is not a tab.
///
/// A native `TabView`, so iOS 26 gives it Liquid Glass and content runs on under it.
struct AppShellView: View {
  private enum Destination: Hashable {
    case home
    case notes
    case settings
  }

  let session: PairSession
  let scenes: [any PetScene]
  @Binding var selectedSceneID: String?
  let onChangeCode: () -> Void
  let onLogOut: () async -> String?

  @State private var destination = Destination.home

  private var line: ConnectionLine {
    ConnectionLine(status: session.status, hasConnected: session.hasConnected)
  }

  var body: some View {
    TabView(selection: $destination) {
      Tab("Home", systemImage: "house", value: .home) {
        HomeView(
          session: session,
          scene: scenes.first { $0.id == selectedSceneID } ?? scenes.first,
          onChangeCode: onChangeCode
        )
        .tabEntrance(destination == .home)
      }
      Tab("Notes", systemImage: "note.text", value: .notes) {
        NotesView(notes: session.notes, loadFailed: session.notesFailedToLoad)
          .tabEntrance(destination == .notes)
      }
      Tab("Settings", systemImage: "gearshape", value: .settings) {
        SettingsView(
          code: session.room.code,
          partnerStatus: line.text,
          catName: session.play.catName,
          scenes: scenes,
          selectedSceneID: $selectedSceneID,
          onLogOut: onLogOut
        )
        .tabEntrance(destination == .settings)
      }
    }
    .tint(Palette.gold.color)
    .sensoryFeedback(.selection, trigger: destination)
    .modifier(WarmTabBarFallback())
  }
}

extension View {
  /// Lets a tab's content rise softly into place when the tab is chosen. Only the position moves:
  /// fading it here shows a hidden tab through the one in front during the pairing transition.
  fileprivate func tabEntrance(_ isSelected: Bool) -> some View {
    modifier(TabEntrance(isSelected: isSelected))
  }
}

private struct TabEntrance: ViewModifier {
  let isSelected: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .offset(y: isSelected || reduceMotion ? 0 : Spacing.small)
      .calmAnimation(value: isSelected)
  }
}

/// iOS 18 has no glass, so the bar gets the warm panel colour instead.
private struct WarmTabBarFallback: ViewModifier {
  func body(content: Content) -> some View {
    #if os(iOS)
      if #available(iOS 26, *) {
        content
      } else {
        content
          .toolbarBackground(Palette.raised.color, for: .tabBar)
          .toolbarBackground(.visible, for: .tabBar)
      }
    #else
      content
    #endif
  }
}
