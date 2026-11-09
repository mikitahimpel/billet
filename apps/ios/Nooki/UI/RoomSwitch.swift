import FeatureGames
import SwiftUI
import Design
import TipKit
import Transport
import WidgetBridge
import Wire

/// Swiping the scene never switches rooms.
struct RoomSwitch: View {
    let state: HomeState
    var select: (RoomKind) -> Void

    var body: some View {
        // One room has no switch: its name would be the only choice.
        if state.rooms.variant.hasRoomChoice {
            GlassSegmented(
                state.rooms.variant.kinds.map { ($0, $0.title) },
                selection: Binding(get: { state.room }, set: select),
                identifier: "roomSwitch"
            )
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Room")
            .accessibilityValue(state.room.title)
            .accessibilityHint("Tap to visit the other room")
            .popoverTip(RoomsHint(), arrowEdge: .top)
        }
    }
}
