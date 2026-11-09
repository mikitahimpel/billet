import Observation

/// Holds a machine's state and runs its outputs, feeding each result back in as an event.
///
/// `run` is the interpreter: it maps an output to calls on injected services, and returns the event
/// to send next, or `nil` when the output has no result. It is `@Sendable`, so services run off the
/// main actor.
///
/// Outputs run concurrently, so their results arrive in completion order. Machines must treat a
/// late result as a legal event in every state.
///
/// The store does not match a result to the output that produced it. A machine whose outputs can
/// overlap, such as two fetches for the same screen, carries a request ID in its state, puts it in
/// the output, and has the result bring it back; `GreetingMachine` shows the pattern, and
/// `WebSocketMachine` does the same with its attempt number. A result with an old ID changes
/// nothing.
///
/// The store does not cancel a running output, and that is a decision, not an omission. An output
/// is a call into a service, and a service that must be stoppable owns that: it takes the
/// cancellation of the task it runs in, or its own timeout, and reports the outcome as a result
/// the machine handles. A machine therefore models "stop waiting" as an event, such as a timeout
/// output that comes back as a result, and uses the request ID to drop whatever answers later.
/// Cancelling from the store would make every output cancellable without any of them being
/// written to cope, and would hide a hung call instead of bounding it.
///
/// A result that arrives after the store has been released is dropped.
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

  /// Returns once `done` holds, looking again at each change of what it read. Unlike `settled`, it
  /// waits only for the work `done` is about, so a caller isn't held by an unrelated output.
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
