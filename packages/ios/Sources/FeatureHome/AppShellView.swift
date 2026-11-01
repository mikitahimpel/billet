import DesignSystem
import FeatureInbox
import FeatureSettings
import PetScene
import SwiftUI

/// The three tabs of a paired device. Drawing is opened from Home and is not a tab.
///
/// Every tab stays alive behind the shared bar, so a delivery keeps playing on Home while Notes or
/// Settings is in front.
struct AppShellView: View {
  private enum Destination: Hashable {
    case home
    case notes
    case settings
  }

  private static let tabs = [
    EveningTab(id: Destination.home, title: "Home", systemImage: "house.fill"),
    EveningTab(id: Destination.notes, title: "Notes", systemImage: "note.text"),
    EveningTab(id: Destination.settings, title: "Settings", systemImage: "gearshape.fill"),
  ]

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
    ZStack {
      tab(.home) {
        HomeView(
          session: session,
          scene: scenes.first { $0.id == selectedSceneID } ?? scenes.first,
          onChangeCode: onChangeCode
        )
      }
      tab(.notes) {
        NotesView(notes: session.notes, loadFailed: session.notesFailedToLoad)
      }
      tab(.settings) {
        SettingsView(
          code: session.room.code,
          partnerStatus: line.text,
          scenes: scenes,
          selectedSceneID: $selectedSceneID,
          onLogOut: onLogOut
        )
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      EveningTabBar(tabs: Self.tabs, selection: $destination)
    }
    .background { EveningBackground() }
  }

  private func tab(_ id: Destination, content: () -> some View) -> some View {
    let selected = destination == id
    return content()
      .opacity(selected ? 1 : 0)
      .allowsHitTesting(selected)
      .accessibilityHidden(!selected)
  }
}
