import QuartzCore

/// Waits on the screen's refresh rather than a timer: `done` is checked once per frame the display shows, and the
/// display link lives only while someone waits.
@MainActor
enum ScreenFrames {
    static func until(timeout: Duration, _ done: @escaping @MainActor () -> Bool) async {
        guard !done() else { return }
        let waiter = FrameWaiter(done: done, deadline: CACurrentMediaTime() + timeout.seconds)
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiter.start($0) }
        } onCancel: {
            Task { @MainActor in waiter.finish() }
        }
    }
}

@MainActor
private final class FrameWaiter: NSObject {
    private let done: @MainActor () -> Bool
    private let deadline: CFTimeInterval
    private var link: CADisplayLink?
    private var continuation: CheckedContinuation<Void, Never>?

    init(done: @escaping @MainActor () -> Bool, deadline: CFTimeInterval) {
        self.done = done
        self.deadline = deadline
    }

    func start(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
        let link = CADisplayLink(target: self, selector: #selector(frame))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func frame(_ link: CADisplayLink) {
        if done() || link.timestamp >= deadline { finish() }
    }

    /// Runs at most once: the link holds its target, so it is invalidated here to let both go.
    func finish() {
        link?.invalidate()
        link = nil
        continuation?.resume()
        continuation = nil
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
