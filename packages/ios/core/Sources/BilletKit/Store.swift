import Observation

/// Runs a machine's outputs concurrently and feeds each result back, in completion order. It
/// neither matches results to outputs nor cancels them: a machine carries a request ID and models
/// timeouts as events. A result that arrives after the store is released is dropped.
@MainActor
@Observable
public final class Store<M: Machine> {
  public private(set) var state: M.State

  private let run: @Sendable (M.Output) async -> M.Event?
  @ObservationIgnored private var running: [Int: Task<Void, Never>] = [:]
  @ObservationIgnored private var nextRunID = 0

  public init(initial: M.State, run: @escaping @Sendable (M.Output) async -> M.Event?) {
    self.state = initial
    self.run = run
  }

  public func send(_ event: M.Event) {
    let (next, outputs) = M.transition(state, event)
    state = next
    outputs.forEach(start)
  }

  /// Returns once no output is running, including outputs started by events fed back meanwhile.
  public func settled() async {
    while let task = running.values.first {
      await task.value
    }
  }

  /// Unlike `settled`, waits only for the work `done` reads, not for unrelated outputs.
  public func until(_ done: @escaping () -> Bool) async {
    while !done() {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        withObservationTracking {
          _ = done()
        } onChange: {
          continuation.resume()
        }
      }
    }
  }

  private func start(_ output: M.Output) {
    let id = nextRunID
    nextRunID += 1
    running[id] = Task { [weak self, run] in
      let event = await run(output)
      guard let self else { return }
      running[id] = nil
      if let event {
        send(event)
      }
    }
  }
}
