import Delivery
import DesignSystem
import FeatureInbox
import FeatureSettings
import Labs
import Pet
import PetScene
import SwiftUI
import WidgetBridge

/// The tabs of a paired device: Home, the Shop when its 3D scene is on, Notes and Settings.
/// Drawing is opened from Home or the Notes desk and is not a tab.
///
/// A native `TabView`, so iOS 26 gives it Liquid Glass and content runs on under it.
struct AppShellView: View {
  private enum Destination: Hashable {
    case home
    case shop
    case notes
    case settings
  }

  let session: PairSession
  let scenes: [any PetScene]
  @Binding var selectedSceneID: String?
  let widgetFeatures: WidgetFeaturesModel
  let publisher: WidgetPublisher
  let labs: WidgetFeaturesModel
  let onChangeCode: () -> Void
  let onLogOut: () async -> String?

  /// Fixed when preparing starts, so that picking a scene never takes its preparation down early.
  @State private var preparingScenes: [any PetScene] = []

  /// Long enough for launch to have settled, so that preparing scenes cannot delay it.
  private static let prepareDelay = Duration.seconds(1)
  /// Above zero, because SwiftUI stops drawing a view that is fully transparent.
  private static let hiddenOpacity = 0.01

  private var selectedScene: (any PetScene)? {
    scenes.first { $0.id == selectedSceneID } ?? scenes.first
  }

  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var typeSize
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

  private var streak: Int {
    let calendar = Calendar.current
    return session.streak(today: TreatDay.key(for: .now, calendar: calendar), calendar: calendar)
  }

  /// The scene the Shop tab shows, when the shop scene is on and the chosen scene has one.
  private var shopScene: (any PetScene)? {
    guard labs.isOn(LabExperiment.shopScene), let scene = selectedScene, scene.hasShop else {
      return nil
    }
    return scene
  }

  /// The scene Notes shows as a desk, when the desk is on and the chosen scene has one. At
  /// accessibility text sizes Notes stays the list.
  private var deskScene: (any PetScene)? {
    guard labs.isOn(LabExperiment.notesDesk), !typeSize.isAccessibilitySize,
      let scene = selectedScene,
      scene.makeDeskScene(state: DeskSceneState(notes: []), onEvent: { _ in }) != nil
    else { return nil }
    return scene
  }

  private var detailDrawing: ((NoteRecord) -> AnyView)? {
    labs.isOn(LabExperiment.drawnReplay)
      ? { AnyView(ReplayDrawing(strokes: $0.strokes)) } : nil
  }

  private var detailActions: ((NoteRecord) -> AnyView)? {
    let frames = labs.isOn(LabExperiment.framedNotes)
    let wallpaper = labs.isOn(LabExperiment.wallpaperShortcut)
    guard frames || wallpaper else { return nil }
    return { note in
      AnyView(
        VStack(spacing: Spacing.small) {
          if frames { FrameNoteButton(note: note, framed: session.frames) }
          if wallpaper { WallpaperShareButton(note: note) }
        })
    }
  }

  var body: some View {
    TabView(selection: $destination) {
      Tab("Home", systemImage: "house", value: .home) {
        HomeView(
          session: session,
          widgetFeatures: widgetFeatures,
          scene: selectedScene,
          onChangeCode: onChangeCode,
          onOpenNotes: { destination = .notes }
        )
        .tabEntrance(destination == .home)
        .environment(\.petSceneOnScreen, destination == .home)
      }
      if let shopScene {
        Tab("Shop", systemImage: "bag", value: .shop) {
          ShopTab(
            shop: session.shop, renovator: session.renovator, scene: shopScene,
            keeper: labs.shopkeeper, onShowRoom: { destination = .home }
          )
          .tabEntrance(destination == .shop)
          .environment(\.petSceneOnScreen, destination == .shop)
        }
      }
      Tab("Notes", systemImage: "note.text", value: .notes) {
        Group {
          if let deskScene {
            DeskTab(
              session: session, scene: deskScene, widgetFeatures: widgetFeatures,
              detailDrawing: detailDrawing, detailActions: detailActions,
              list: { AnyView(notesList) })
          } else {
            notesList
          }
        }
        .tabEntrance(destination == .notes)
        .environment(\.petSceneOnScreen, destination == .notes)
      }
      Tab("Settings", systemImage: "gearshape", value: .settings) {
        SettingsView(
          code: session.isFakePartner ? nil : session.room.code,
          labs: labs,
          partnerStatus: line.text,
          catName: session.play.catName,
          scenes: scenes,
          selectedSceneID: $selectedSceneID,
          widgetFeatures: widgetFeatures,
          isFakePartner: session.isFakePartner,
          onLogOut: onLogOut
        )
        .tabEntrance(destination == .settings)
      }
    }
    .background {
      // Behind the tabs, so that switching tabs never hides a scene that is preparing.
      ForEach(preparingScenes, id: \.id) { scene in
        scene.makePreparationView()
      }
      .frame(width: 1, height: 1)
      .opacity(Self.hiddenOpacity)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
    .task {
      try? await Task.sleep(for: Self.prepareDelay)
      preparingScenes = scenes.filter { $0.id != selectedScene?.id }
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

extension AppShellView {
  /// Every note in a list, the way Notes has always shown them.
  fileprivate var notesList: some View {
    NotesView(
      notes: session.notes, loadFailed: session.notesFailedToLoad,
      reactions: session.play.reactions,
      onReact: { session.react(to: $0, $1) },
      detailDrawing: detailDrawing,
      detailActions: detailActions,
      board: labs.isOn(LabExperiment.shelfBoard)
        ? { board in
          AnyView(
            ShelfBoardView(
              notes: board.notes, reactions: board.reactions, streak: streak,
              detail: board.detail, onClose: board.close))
        } : nil
    )
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
