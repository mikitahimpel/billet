import DesignSystem
import FeatureInbox
import FeatureSettings
import SwiftUI

/// The three tabs of a paired device. Drawing is opened from Home and is not a tab.
struct AppShellView: View {
  let session: PairSession
  let onChangeCode: () -> Void
  let onLogOut: () async -> String?

  private var line: ConnectionLine {
    ConnectionLine(status: session.status, hasConnected: session.hasConnected)
  }

  var body: some View {
    TabView {
      Tab("Home", systemImage: "house") {
        HomeView(session: session, onChangeCode: onChangeCode)
          .tabBarStyled()
      }
      Tab("Notes", systemImage: "tray") {
        NotesView(notes: session.notes, loadFailed: session.notesFailedToLoad)
          .tabBarStyled()
      }
      Tab("Settings", systemImage: "gearshape") {
        SettingsView(
          code: session.room.code, partnerStatus: line.text, onLogOut: onLogOut
        )
        .tabBarStyled()
      }
    }
    .tint(Palette.paper.color)
  }
}

extension View {
  fileprivate func tabBarStyled() -> some View {
    #if os(iOS)
      toolbarBackground(Palette.raised.color, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    #else
      self
    #endif
  }
}
