import SwiftUI

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
