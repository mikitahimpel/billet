import DesignSystem
import PetScene
import SwiftUI

/// The app under the service's status: as it is with a notice above it, under the maintenance
/// screen, or behind "Update billet".
///
/// The app stays mounted under both screens, so nothing it holds is lost: an open drawing, the
/// notes, the room's connection and what waits to be sent. During maintenance the user can lift
/// the screen to read their notes, and it comes back by itself when they are done.
struct ServiceStatusLayer<Content: View>: View {
  let model: ServiceStatusModel
  let updateLink: UpdateLink
  /// The cat asleep in its room, behind the maintenance screen. `nil` shows the evening alone.
  /// Built only while the screen shows.
  let room: @MainActor () -> AnyView?
  @ViewBuilder let content: Content

  /// The user lifted the maintenance screen to read what they have.
  @State private var reading = false

  var body: some View {
    let screen = model.screen
    let covered = covers(screen)
    ZStack(alignment: .top) {
      content
        .environment(\.petSceneOnScreen, !covered)
        .allowsHitTesting(!covered)
        .accessibilityHidden(covered)
      switch screen {
      case .updateRequired:
        UpdateRequiredView(link: updateLink)
          .transition(.opacity)
      case .maintenance(let maintenance) where reading:
        MaintenanceReadingBar(
          message: model.maintenanceMessage(maintenance), onBack: { reading = false }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
      case .maintenance(let maintenance):
        MaintenanceView(
          message: model.maintenanceMessage(maintenance), until: maintenance.untilDate,
          room: room(), onRead: { reading = true }
        )
        .transition(.opacity)
      case .normal:
        if let text = model.noticeText {
          NoticeBanner(text: text, onDismiss: { model.dismissNotice() })
            .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
    }
    .calmAnimation(value: screen)
    .calmAnimation(value: reading)
    .onChange(of: model.maintenanceEnds) { reading = false }
  }

  private func covers(_ screen: ServiceScreen) -> Bool {
    switch screen {
    case .updateRequired: true
    case .maintenance: !reading
    case .normal: false
    }
  }
}
