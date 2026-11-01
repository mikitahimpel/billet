import Delivery
import DesignSystem
import FeatureInbox
import FeatureSettings
import Pet
import PetScene
import SwiftUI
import WidgetBridge

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
  let widgetFeatures: WidgetFeaturesModel
  let publisher: WidgetPublisher
  let onChangeCode: () -> Void
  let onLogOut: () async -> String?

  @Environment(\.scenePhase) private var scenePhase
  @State private var destination = Destination.home

  /// Everything the widgets show that can change while the app is open.
  private struct PublishKey: Hashable {
    let ledger: TreatLedger
    let catName: String?
    let status: NoteDelivery.Status
    let latestNote: UUID?
    let noteCount: Int
    let active: Bool
  }

  /// When the app may be able to carry out what widgets queued: it is open, or the room changed.
  private struct DrainKey: Hashable {
    let active: Bool
    let status: NoteDelivery.Status
  }

  private var publishKey: PublishKey {
    PublishKey(
      ledger: session.play.ledger, catName: session.play.catName, status: session.status,
      latestNote: session.notes.first?.id,
      noteCount: session.notes.count, active: scenePhase == .active)
  }

  private var line: ConnectionLine {
    ConnectionLine(status: session.status, hasConnected: session.hasConnected)
  }

  var body: some View {
    TabView(selection: $destination) {
      Tab("Home", systemImage: "house", value: .home) {
        HomeView(
          session: session,
          scene: scenes.first { $0.id == selectedSceneID } ?? scenes.first,
          onChangeCode: onChangeCode,
          onOpenNotes: { destination = .notes }
        )
        .tabEntrance(destination == .home)
      }
      Tab("Notes", systemImage: "note.text", value: .notes) {
        NotesView(
          notes: session.notes, loadFailed: session.notesFailedToLoad,
          reactions: session.play.reactions,
          onReact: { session.react(to: $0, $1) }
        )
        .tabEntrance(destination == .notes)
      }
      Tab("Settings", systemImage: "gearshape", value: .settings) {
        SettingsView(
          code: session.room.code,
          partnerStatus: line.text,
          catName: session.play.catName,
          scenes: scenes,
          selectedSceneID: $selectedSceneID,
          widgetFeatures: widgetFeatures,
          onLogOut: onLogOut
        )
        .tabEntrance(destination == .settings)
      }
    }
    .tint(Palette.gold.color)
    .sensoryFeedback(.selection, trigger: destination)
    .task(id: DrainKey(active: scenePhase == .active, status: session.status)) {
      guard scenePhase == .active, let queue = ActionQueue.appGroup() else { return }
      if session.drain(queue) { destination = .home }
    }
    .task(id: publishKey) {
      while !Task.isCancelled {
        publisher.publish(
          play: session.play, notes: session.notes,
          partnerHere: scenePhase == .active && session.status == .partnerHere)
        try? await Task.sleep(for: WidgetPublisher.refresh)
      }
    }
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
