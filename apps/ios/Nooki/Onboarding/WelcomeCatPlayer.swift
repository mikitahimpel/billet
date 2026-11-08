import AVFoundation
import SwiftUI

/// Mochi's welcome clips, baked offline from the real model (`scripts/welcome/bake-welcome.sh`): a looping idle and a
/// wave for a tap, both HEVC with alpha. The players are made before the screen shows, so its first frame is the
/// poster still under the video and nothing is empty or black.
@MainActor
final class WelcomeClips {
    static let shared = WelcomeClips()

    private(set) var idle: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private(set) var wave: AVPlayer?

    private init() {}

    func preload(bundle: Bundle = .main) {
        guard idle == nil, let idleURL = bundle.url(forResource: "welcome-idle", withExtension: "mov") else { return }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: idleURL))
        idle = player
        if let waveURL = bundle.url(forResource: "welcome-wave", withExtension: "mov") {
            let player = AVPlayer(url: waveURL)
            player.isMuted = true
            wave = player
        }
    }
}

/// The poster still with the idle video over it; a tap plays the wave from the rest pose and goes back to idle.
struct WelcomeCat: View {
    /// Starts the idle loop; false with Reduce Motion, which keeps the poster.
    let playing: Bool
    var waved: () -> Void = {}

    @State private var ready = false

    var body: some View {
        ZStack {
            Image("welcome-poster")
                .resizable()
                .scaledToFit()
            if playing, WelcomeClips.shared.idle != nil {
                ClipView(ready: $ready, tapped: waved)
                    .opacity(ready ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ClipView: UIViewRepresentable {
    @Binding var ready: Bool
    let tapped: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ClipUIView {
        let view = ClipUIView()
        view.backgroundColor = .clear
        let clips = WelcomeClips.shared
        view.idleLayer.player = clips.idle
        view.waveLayer.player = clips.wave
        view.waveLayer.isHidden = true
        context.coordinator.ready = $ready
        context.coordinator.attach(view, clips: clips)
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap)))
        return view
    }

    func updateUIView(_ view: ClipUIView, context: Context) {
        context.coordinator.onWave = tapped
        context.coordinator.ready = $ready
    }

    @MainActor
    final class Coordinator: NSObject {
        var onWave: () -> Void = {}
        var ready: Binding<Bool> = .constant(false)
        private weak var view: ClipUIView?
        private var observers: [NSKeyValueObservation] = []
        private var waving = false
        private var ended: NSObjectProtocol?

        func attach(_ view: ClipUIView, clips: WelcomeClips) {
            self.view = view
            observers.append(view.idleLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                Task { @MainActor in self?.ready.wrappedValue = true }
            })
            clips.idle?.play()
        }

        @objc func tap() {
            guard !waving, let view, let wave = WelcomeClips.shared.wave, let idle = WelcomeClips.shared.idle else { return }
            waving = true
            onWave()
            // Idle's first frame is the rest pose the wave starts and ends on, so the two join without a jump.
            idle.pause()
            idle.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            wave.seek(to: .zero)
            view.waveLayer.isHidden = false
            wave.play()
            ended = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: wave.currentItem, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishWave() }
            }
        }

        private func finishWave() {
            view?.waveLayer.isHidden = true
            WelcomeClips.shared.idle?.play()
            ended.map(NotificationCenter.default.removeObserver)
            ended = nil
            waving = false
        }
    }
}

private final class ClipUIView: UIView {
    let idleLayer = AVPlayerLayer()
    let waveLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        for layer in [idleLayer, waveLayer] {
            layer.videoGravity = .resizeAspect
            layer.backgroundColor = UIColor.clear.cgColor
            self.layer.addSublayer(layer)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        idleLayer.frame = bounds
        waveLayer.frame = bounds
    }
}
