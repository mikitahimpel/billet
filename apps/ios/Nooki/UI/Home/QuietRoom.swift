import BilletKit
import Design
import PetScene
import RoomInterface
import SwiftUI
import UIKit

extension AppSettings {
    /// Labs: how the World's chrome steps back while the room is only watched.
    static let quietRoomKey = "labs.quietRoom"
}

enum QuietRoom {
    @MainActor
    static func store() -> Store<QuietRoomMachine> {
        Store(initial: .off(wait: 0)) { output in
            switch output {
            case .wait(let id):
                try? await Task.sleep(for: QuietRoomMachine.after)
                return .waited(id)
            }
        }
    }

    /// UI tests and perf runs drive Home from a script, which looks for the chrome where it was.
    static let scripted = ScenePerf.isOn || ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uitest") }
}

/// Fades what it wraps while the room is quiet. Only this modifier reads the store, so a touch never re-evaluates
/// Home's body.
struct QuietFade: ViewModifier {
    let store: Store<QuietRoomMachine>
    let chrome: QuietChrome

    func body(content: Content) -> some View {
        let quiet = store.state.isQuiet
        content
            .opacity(quiet ? chrome.quietOpacity : 1)
            .allowsHitTesting(!quiet || chrome.quietTakesTouches)
            .animation(.easeInOut(duration: quiet ? 1.2 : 0.25), value: quiet)
    }
}

/// Hears every touch in its window without taking part in it: the recognizer never recognizes and cancels nothing,
/// so the controls and the room get their touches as before.
struct TouchWatcher: UIViewRepresentable {
    let touched: @MainActor () -> Void

    func makeUIView(context: Context) -> WatcherView { WatcherView() }

    func updateUIView(_ view: WatcherView, context: Context) { view.touched = touched }

    final class WatcherView: UIView {
        var touched: @MainActor () -> Void = {}
        private lazy var recognizer = TouchRecognizer { [weak self] in self?.touched() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }
}

private final class TouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let touched: @MainActor () -> Void

    init(touched: @escaping @MainActor () -> Void) {
        self.touched = touched
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        touched()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        touched()
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
