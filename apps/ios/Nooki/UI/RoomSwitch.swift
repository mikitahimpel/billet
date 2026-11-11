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
                identifier: "roomSwitch",
                identifiers: Dictionary(uniqueKeysWithValues: state.rooms.variant.kinds.map { ($0, $0.identifier) })
            )
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Room")
            .accessibilityValue(state.room.title)
            .accessibilityHint("Tap to go to the other room")
            .hint(RoomsHint(), arrowEdge: .top, target: Capsule())
        }
    }
}

/// Photos | Board, the Moments tab's switch: the same control, size and place as the World's `RoomSwitch`, in the
/// header's glass container.
struct MomentsSwitch: View {
    @Bindable var state: HomeState

    var body: some View {
        GlassSegmented(
            [(MomentsMode.photos, "Photos"), (MomentsMode.board, "Board")],
            selection: $state.momentsMode,
            identifier: "momentsMode"
        )
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Moments")
        .accessibilityValue(state.momentsMode == .board ? "Board" : "Photos")
        .accessibilityHint("Switches between Photos and Board")
    }
}
