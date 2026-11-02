import SwiftUI

/// Builds the room out of sight at low priority, so that it is ready when someone opens Nooki.
/// It never draws the room: a RealityView that shows the room while another scene is up can
/// leave the room's own view empty afterwards.
struct NookiPreload: View {
  let cache: NookiRoomCache

  var body: some View {
    Color.clear
      .task { cache.diorama().startLoading(priority: .utility) }
  }
}
