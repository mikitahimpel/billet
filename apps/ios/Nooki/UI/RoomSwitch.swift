import FeatureGames
import SwiftUI
import Design
import TipKit
import Transport
import WidgetBridge
import Wire

/// Switches between Mochi's rooms with a small glass capsule under the header; a swipe of the scene does the same.
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
            .accessibilityHint("Swipe the room sideways, or tap, to visit the other one")
            .popoverTip(RoomsHint(), arrowEdge: .top)
        }
    }
}

/// A snapshot from `UIView.snapshotView(afterScreenUpdates:)`, filling the view it is put in.
struct SnapshotView: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView {
        let holder = UIView()
        holder.isUserInteractionEnabled = false
        view.frame = holder.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        holder.addSubview(view)
        return holder
    }

    func updateUIView(_ holder: UIView, context: Context) {}
}

/// Under the UI tests (`-uitestRoomTaps YES`), counts every tap that reaches the room and reports it as the room's
/// accessibility value, so a test can tell that a tap on the tab bar never fell through. Off otherwise.
struct RoomTapCounter: ViewModifier {
    @State private var taps = 0
    private let counts = UserDefaults.standard.bool(forKey: "uitestRoomTaps")

    func body(content: Content) -> some View {
        if counts {
            content
                .simultaneousGesture(TapGesture().onEnded { taps += 1 })
                .accessibilityElement()
                .accessibilityIdentifier("room")
                .accessibilityValue("\(taps)")
        } else {
            content
        }
    }
}
