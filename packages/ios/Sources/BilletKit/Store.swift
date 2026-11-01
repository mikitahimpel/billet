import Observation

/// Holds a machine's state and runs its outputs, feeding each result back in as an event.
///
/// `run` is the interpreter: it maps an output to calls on injected services, and returns the event
/// to send next, or `nil` when the output has no result. It is `@Sendable`, so services run off the
/// main actor.
///
/// Outputs run concurrently, so their results arrive in completion order. Machines must treat a
/// late result as a legal event in every state. A result that arrives after the store has been
/// released is dropped.
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
